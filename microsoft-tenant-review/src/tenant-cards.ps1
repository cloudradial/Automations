# =====================================================================
#  Secure Score -> CloudRadial Assessment (deterministic, in-memory xlsx)
#  Run input: {"companyId":123,"tenantId":"<client Graph tenant GUID>","assessmentTitle":"Microsoft Secure Score","mode":"apply"}
#    companyId  - CloudRadial company the assessment is created under (required)
#    tenantId   - the CLIENT's Entra tenant id to pull Secure Score from (required)
#    mode       - "apply" (default) writes; "plan" previews only
#  Secrets (runner Key Vault): CloudRadial-BaseUrl / -PublicKey / -PrivateKey,
#    and M365-ClientID / M365-ClientSecret (an Entra app with
#    SecurityEvents.Read.All application permission, consented in the client tenant).
# =====================================================================
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

function Get-Secret { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
function Get-Prop { param($o,$n) if($null -eq $o){return $null}; if($o -is [System.Collections.IDictionary]){ if($o.Contains($n)){return $o[$n]}; return $null }; $p=$o.PSObject.Properties[$n]; if($p){return $p.Value}; return $null }

# ---- run input ----
$in = Get-NodeInput
$t = Get-Prop $in 'trigger'; if ($null -ne $t) { $in = $t }
if ($in -is [string]) { $s = $in.Trim(); if ($s.StartsWith('{')) { $in = $s | ConvertFrom-Json } }
$companyId = Get-Prop $in 'companyId'
$tenantId  = Get-Prop $in 'tenantId'
$title     = [string](Get-Prop $in 'assessmentTitle'); if ([string]::IsNullOrWhiteSpace($title)) { $title = 'Microsoft Secure Score' }
$mode      = [string](Get-Prop $in 'mode'); if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'apply' }
if ([string]::IsNullOrWhiteSpace([string]$tenantId) -or [string]$tenantId -match '^0{8}-') { Set-NodeOutput ([ordered]@{ status = 'skipped'; message = 'Microsoft 365 is not connected for this client (no tenant on the portal company), so the tenant review was skipped.' }); return }
if (-not $companyId -or [string]::IsNullOrWhiteSpace([string]$tenantId)) {
    $m = 'Need companyId (CloudRadial) and tenantId (the client Entra tenant). e.g. {"companyId":123,"tenantId":"00000000-0000-0000-0000-000000000000"}.'
    Set-NodeOutput @{ status = 'error'; message = $m }; throw $m
}

# ---- secrets ----
$crBaseRaw = Get-Secret 'CloudRadial-BaseUrl'; $pub = Get-Secret 'CloudRadial-PublicKey'; $prv = Get-Secret 'CloudRadial-PrivateKey'
$appId = Get-Secret 'M365-ClientID'; $appSecret = Get-Secret 'M365-ClientSecret'
$missing = foreach ($pair in @(
    @{ n='CloudRadial-BaseUrl'; v=$crBaseRaw }, @{ n='CloudRadial-PublicKey'; v=$pub }, @{ n='CloudRadial-PrivateKey'; v=$prv },
    @{ n='M365-ClientID'; v=$appId }, @{ n='M365-ClientSecret'; v=$appSecret }
)) { if ([string]::IsNullOrWhiteSpace([string]$pair.v)) { $pair.n } }
if (@($missing).Count -gt 0) { $m = "Add these runner Key Vault secret(s) and re-run: $($missing -join ', ')."; Set-NodeOutput @{ status='error'; message=$m }; throw $m }
$crBase = ([string]$crBaseRaw).TrimEnd('/')
$crAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$pub`:$prv"))

# ---- CloudRadial helpers ----
function Invoke-Cr {
    param([string]$Method,[string]$Path,[object]$Body)
    $u = if ($Path -match '^https?://') { $Path } else { "$crBase$Path" }
    $h = @{ Authorization = $crAuth; Accept = 'application/json' }
    $a = @{ Uri = $u; Method = $Method; Headers = $h; ContentType = 'application/json' }
    if ($null -ne $Body) { $a.Body = ($Body | ConvertTo-Json -Depth 10) }
    Invoke-RestMethod @a
}
function Get-CrAll {
    param([string]$Path)
    $all = @(); $skip = 0
    for ($p = 0; $p -lt 500; $p++) {
        $sep = if ($Path -match '\?') { '&' } else { '?' }
        $r = Invoke-Cr -Method GET -Path "${Path}${sep}`$top=100&`$skip=$skip"
        $rows = if ($r.PSObject.Properties['value']) { @($r.value) } elseif ($r -is [System.Array]) { @($r) } else { @() }
        $all += $rows
        if (@($rows).Count -lt 100) { break }
        $skip += 100
    }
    return $all
}
function Send-CrMultipart {
    param([string]$Path,[string]$DataJson,[byte[]]$FileBytes,[string]$FileName)
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.DefaultRequestHeaders.Add('Authorization', $crAuth)
    $form = New-Object System.Net.Http.MultipartFormDataContent
    $form.Add((New-Object System.Net.Http.StringContent($DataJson, [Text.Encoding]::UTF8, 'application/json')), 'data')
    $fc = New-Object System.Net.Http.ByteArrayContent(, $FileBytes)
    $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    $form.Add($fc, 'file', $FileName)
    $resp = $client.PostAsync("$crBase$Path", $form).GetAwaiter().GetResult()
    $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $client.Dispose()
    if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $text" }
    return $text
}

# ---- assessment template (51-col) + a 15-col working subset ----
$Columns = @('Category','Question','Order','Explanation','Type','Answer','Text Answer','Responses','Is Flagged','Notes','Evaluation','Remediation Summary','Remediation','Reference','Partner Notes')
$TemplateColumns = @('Partner Notes','Monthly Unit Cost','Project Unit Cost','Psa Board','Psa Item','Psa Status','Psa Category','Psa Sub Type','Psa Type','Psa Priority','Psa Source','Psa Estimated Time','Email List','Teams Webhook','Slack Webhook','Flow Webhook','Json Webhook','Script','Checklist','Category','Question','Order','Explanation','Type','Answer','Text Answer','Responses','Is Flagged','Notes','Evaluation','Remediation Summary','Remediation','Reference','Monthly Units','Monthly Unit Price','Project Units','Project Unit Price','Control Type','Likelihood','Risk','Risk Cost','Risk Impact','Owner','Updated by','Update Key','Content Update Key','Note Compliant','Note Partially Compliant','Note NA','Note Missing','Note Not Compliant')
function ConvertTo-TemplateRows { param([object[]]$Rows)
    $idx = @{}; for ($i = 0; $i -lt $Columns.Count; $i++) { $idx[$Columns[$i]] = $i }
    $out = New-Object System.Collections.ArrayList
    foreach ($r in $Rows) { $row = @($r); $null = $out.Add(@($TemplateColumns | ForEach-Object { if ($idx.ContainsKey($_)) { $row[$idx[$_]] } else { $null } })) }
    return $out.ToArray()
}
function New-XlsxBytes {
    param([string[]]$Header,[object[]]$Rows)
    Add-Type -AssemblyName System.IO.Compression
    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }
    $colName = { param([int]$n) $s=''; $n++; while ($n -gt 0) { $m = ($n-1) % 26; $s = [char](65 + $m) + $s; $n = [int][Math]::Floor(($n-1)/26) }; $s }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
    $all = @(, $Header) + $Rows
    for ($r = 0; $r -lt $all.Count; $r++) {
        $null = $sb.Append("<row r=""$($r+1)"">")
        $row = @($all[$r])
        for ($c = 0; $c -lt $row.Count; $c++) {
            $ref = (& $colName $c) + ($r+1); $val = $row[$c]
            if ($val -is [int] -or $val -is [long] -or $val -is [double]) { $null = $sb.Append("<c r=""$ref""><v>$val</v></c>") }
            elseif (-not [string]::IsNullOrEmpty([string]$val)) { $null = $sb.Append("<c r=""$ref"" t=""inlineStr""><is><t xml:space=""preserve"">$(& $esc $val)</t></is></c>") }
        }
        $null = $sb.Append('</row>')
    }
    $null = $sb.Append('</sheetData></worksheet>')
    $files = [ordered]@{
        '[Content_Types].xml'        = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
        '_rels/.rels'                = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl/workbook.xml'            = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Assessment" sheetId="1" r:id="rId1"/></sheets></workbook>'
        'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
        'xl/worksheets/sheet1.xml'   = $sb.ToString()
    }
    $ms = New-Object System.IO.MemoryStream
    $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($k in $files.Keys) { $entry = $zip.CreateEntry($k); $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false))); $w.Write($files[$k]); $w.Dispose() }
    $zip.Dispose()
    return , $ms.ToArray()
}


# ==== Tenant review Planner cards: unused Microsoft 365 licenses and accounts without MFA ====
$tok = (Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method Post -ContentType 'application/x-www-form-urlencoded' -Body @{ grant_type = 'client_credentials'; client_id = $appId; client_secret = $appSecret; scope = 'https://graph.microsoft.com/.default' }).access_token
if (-not $tok) { throw 'Could not get a Microsoft Graph token. Check the app id and secret, and that the app is consented in the client tenant.' }
$gh = @{ Authorization = "Bearer $tok"; ConsistencyLevel = 'eventual' }
function Get-GraphAll { param([string]$Url) $all = @(); $u = $Url; for ($i = 0; $i -lt 60 -and $u; $i++) { $r = Invoke-RestMethod -Uri $u -Headers $gh; $all += @($r.value); $nl = $r.PSObject.Properties['@odata.nextLink']; $u = if ($nl) { [string]$nl.Value } else { $null } }; return $all }
function Enc { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
$warn = @(); $cardNotes = @(); $asOf = (Get-Date).ToString('d MMM yyyy')
# Licenses
$skuNames = @{ 'SPB' = 'Microsoft 365 Business Premium'; 'O365_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'; 'O365_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'; 'O365_BUSINESS' = 'Microsoft 365 Apps for business'; 'OFFICESUBSCRIPTION' = 'Microsoft 365 Apps for enterprise'; 'ENTERPRISEPACK' = 'Office 365 E3'; 'ENTERPRISEPREMIUM' = 'Office 365 E5'; 'STANDARDPACK' = 'Office 365 E1'; 'SPE_E3' = 'Microsoft 365 E3'; 'SPE_E5' = 'Microsoft 365 E5'; 'SPE_F1' = 'Microsoft 365 F3'; 'EXCHANGESTANDARD' = 'Exchange Online (Plan 1)'; 'EXCHANGEENTERPRISE' = 'Exchange Online (Plan 2)'; 'AAD_PREMIUM' = 'Microsoft Entra ID P1'; 'AAD_PREMIUM_P2' = 'Microsoft Entra ID P2'; 'EMS' = 'Enterprise Mobility + Security E3'; 'POWER_BI_PRO' = 'Power BI Pro'; 'PROJECTPROFESSIONAL' = 'Project Plan 3'; 'VISIOCLIENT' = 'Visio Plan 2'; 'ATP_ENTERPRISE' = 'Defender for Office 365 (Plan 1)'; 'Microsoft_Teams_Premium' = 'Teams Premium'; 'MCOEV' = 'Teams Phone Standard' }
$skus = @(); try { $skus = Get-GraphAll 'https://graph.microsoft.com/v1.0/subscribedSkus' } catch { $warn += "Licenses were not read: $($_.Exception.Message) The app needs Organization.Read.All (application) with admin consent." }
$unused = @($skus | Where-Object { [string]$_.capabilityStatus -eq 'Enabled' -and [string]$_.appliesTo -eq 'User' } | ForEach-Object { $en = [int]$_.prepaidUnits.enabled; $used = [int]$_.consumedUnits; $p = [string]$_.skuPartNumber; [pscustomobject]@{ name = $(if ($skuNames.ContainsKey($p)) { $skuNames[$p] } else { $p }); enabled = $en; used = $used; free = ($en - $used) } } | Where-Object { $_.free -gt 0 -and $_.enabled -lt 1000 -and $_.name -notmatch '(?i)free|trial|viral' } | Sort-Object free -Descending)
$freeTotal = [int](($unused | Measure-Object free -Sum).Sum)
# MFA
$noMfa = @(); $mfaSource = ''
try { $reg = Get-GraphAll "https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails?`$filter=isMfaRegistered eq false"; $noMfa = @($reg | Where-Object { [string]$_.userType -ne 'guest' } | ForEach-Object { [pscustomobject]@{ name = [string]$_.userDisplayName; upn = [string]$_.userPrincipalName; admin = [bool]$_.isAdmin } }); $mfaSource = 'Microsoft Entra MFA registration report' }
catch {
    try { $users = @(Get-GraphAll "https://graph.microsoft.com/v1.0/users?`$filter=accountEnabled eq true and userType eq 'Member'&`$select=id,displayName,userPrincipalName,assignedLicenses&`$top=999&`$count=true")
        $users = @($users | Where-Object { @($_.assignedLicenses).Count -gt 0 } | Select-Object -First 300)
        foreach ($u in $users) { $m = @((Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users/$($u.id)/authentication/methods" -Headers $gh).value); $strong = @($m | Where-Object { [string]$_.'@odata.type' -notmatch 'passwordAuthenticationMethod' }); if (-not $strong.Count) { $noMfa += [pscustomobject]@{ name = [string]$u.displayName; upn = [string]$u.userPrincipalName; admin = $false } } }
        $mfaSource = 'sign-in methods on each licensed account'
    } catch { $warn += "MFA was not checked: $($_.Exception.Message) The app needs AuditLog.Read.All, or UserAuthenticationMethod.Read.All, as application permissions with admin consent." }
}
$noMfa = @($noMfa | Sort-Object @{ Expression = { -not $_.admin } }, name)

# Stale accounts: enabled, licensed accounts with no sign-in for 90+ days (or never, when older than 30 days)
$stale = @(); $staleSource = ''; $staleDays = 90; $cut = (Get-Date).ToUniversalTime().AddDays(-$staleDays)
try {
    $su = @(Get-GraphAll "https://graph.microsoft.com/v1.0/users?`$filter=accountEnabled eq true and userType eq 'Member'&`$select=displayName,userPrincipalName,createdDateTime,assignedLicenses,signInActivity&`$top=120")
    foreach ($u in $su) { if (-not @($u.assignedLicenses).Count) { continue }
        $last = $null; $sa = $u.signInActivity; if ($sa) { foreach ($k in @('lastSuccessfulSignInDateTime', 'lastSignInDateTime', 'lastNonInteractiveSignInDateTime')) { $vv = $sa.$k; if ($vv) { $d = [datetime]$vv; if (-not $last -or $d -gt $last) { $last = $d } } } }
        $created = if ($u.createdDateTime) { [datetime]$u.createdDateTime } else { $null }
        if (($last -and $last -lt $cut) -or (-not $last -and $created -and $created -lt (Get-Date).ToUniversalTime().AddDays(-30))) { $stale += [pscustomobject]@{ name = [string]$u.displayName; upn = [string]$u.userPrincipalName; last = $(if ($last) { $last.ToString('d MMM yyyy') } else { 'Never' }); days = $(if ($last) { [int]((Get-Date).ToUniversalTime() - $last).TotalDays } else { 9999 }) } } }
    $staleSource = 'Microsoft Entra sign-in activity'
} catch {
    $siErr = $_.Exception.Message
    try { $csv = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/reports/getOffice365ActiveUserDetail(period='D180')" -Headers $gh
        $rows = @([string]$csv -replace '^﻿', '' | ConvertFrom-Csv)
        foreach ($r in $rows) { $isDel = ($r.PSObject.Properties | Where-Object { $_.Name -eq 'Is Deleted' } | Select-Object -First 1).Value; $prods = ($r.PSObject.Properties | Where-Object { $_.Name -eq 'Assigned Products' } | Select-Object -First 1).Value; if ([string]$isDel -eq 'True' -or -not [string]$prods) { continue }
            $d = $null; foreach ($pp in $r.PSObject.Properties) { if ($pp.Name -match 'Last Activity Date$' -and [string]$pp.Value) { $dd = [datetime][string]$pp.Value; if (-not $d -or $dd -gt $d) { $d = $dd } } }
            if (-not $d -or $d -lt $cut) { $stale += [pscustomobject]@{ name = [string]$r.'Display Name'; upn = [string]$r.'User Principal Name'; last = $(if ($d) { $d.ToString('d MMM yyyy') } else { 'No activity in 180 days' }); days = $(if ($d) { [int]((Get-Date) - $d).TotalDays } else { 9999 }) } } }
        $staleSource = 'Microsoft 365 active user report'; $warn += "Sign-in activity was not available ($siErr), so the Microsoft 365 active user report was used instead."
    } catch { $warn += "Stale accounts were not checked: $($_.Exception.Message) The app needs AuditLog.Read.All (with Entra ID P1) or Reports.Read.All, as application permissions with admin consent." }
}
$stale = @($stale | Sort-Object days -Descending)
# Card helpers (branded, updated in place)
function New-Banner { param([string]$Icon, [string]$Big, [string]$Unit, [string]$Title, [string]$Sub) "<div style='background:linear-gradient(135deg,#001F54 0%,#09507B 55%,#1282A2 100%);color:#fff;padding:16px 20px;border-radius:12px;border-left:6px solid #B3C9D5;box-shadow:0 4px 14px rgba(0,31,84,.3);display:flex;align-items:center;gap:16px;flex-wrap:wrap;margin:0 0 12px;'><div style='background:#fff;color:#001F54;border-radius:10px;min-width:64px;padding:8px 10px;text-align:center;'><div style='font-size:26px;font-weight:700;line-height:1;'>$(Enc $Big)</div><div style='font-size:11px;text-transform:uppercase;letter-spacing:.04em;'>$(Enc $Unit)</div></div><div style='flex:1;min-width:200px;'><div style='font-size:19px;font-weight:600;'><i class='fal $Icon' style='color:#B3C9D5;'></i>&nbsp; $(Enc $Title)</div><div style='font-size:14px;opacity:.9;margin-top:4px;'>$(Enc $Sub)</div></div></div>" }
function New-Head { param([string]$Icon, [string]$Text) "<div style='display:flex;align-items:center;gap:10px;margin:14px 0 6px;padding:8px 12px;background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid #B3C9D5;border-radius:10px;'><span style='background:#001F54;color:#B3C9D5;width:28px;height:28px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center;'><i class='fal $Icon'></i></span><span style='font-size:15px;font-weight:600;color:#001F54;'>$(Enc $Text)</span></div>" }
function New-Tbl { param([string[]]$Head, [object[]]$Rows) $th = ($Head | ForEach-Object { "<th style='background:#001F54;color:#fff;text-align:left;padding:7px 9px;font-size:12px;'>$(Enc $_)</th>" }) -join ''; $n = 0; $tr = foreach ($r in $Rows) { $n++; $bg = if ($n % 2) { '#FFFFFF' } else { '#E8F3F7' }; "<tr style='background:$bg;'>" + ((@($r) | ForEach-Object { "<td style='padding:6px 9px;font-size:13px;color:#001F54;border-bottom:1px solid #B3D7E3;'>$_</td>" }) -join '') + '</tr>' }; "<div style='border:1px solid #B3D7E3;border-radius:10px;overflow:hidden;margin:6px 0;'><table style='width:100%;border-collapse:collapse;'><tr>$th</tr>$($tr -join '')</table></div>" }
$existing = @(); try { $existing = @(Get-CrAll "/v2/odata/product?`$filter=companyId eq $companyId") } catch { }
function Save-Card { param([string]$Subject, [string]$Summary, [string]$Body, [string]$Category, [int]$CatId)
    $oldSubject = $Subject -replace 'nses$', 'nces'
    $ex = $existing | Where-Object { [string]$_.subject -eq $Subject -or [string]$_.subject -eq $oldSubject } | Select-Object -First 1
    try {
        if ($ex) { $ops = @(@{ op = 'replace'; path = '/subject'; value = $Subject }, @{ op = 'replace'; path = '/summary'; value = $Summary }, @{ op = 'replace'; path = '/body'; value = $Body }); $null = Invoke-RestMethod -Uri "$crBase/v2/product/$($ex.productId)" -Method PATCH -Headers @{ Authorization = $crAuth; Accept = 'application/json' } -ContentType 'application/json-patch+json' -Body (ConvertTo-Json -InputObject $ops -Depth 5); return "Updated: $Subject" }
        else { $null = Invoke-Cr -Method POST -Path '/v2/product' -Body @{ companyId = [int]$companyId; subject = $Subject; summary = $Summary; body = $Body; category = $Category; productCategoryId = $CatId; isClientVisible = $true }; return "Created: $Subject" }
    } catch { return "Could not save $($Subject): $($_.Exception.Message)" }
}
if ($mode -eq 'apply') {
    if ($skus.Count) {
        $lsum = if ($freeTotal) { "You are paying for $freeTotal Microsoft 365 license$(if ($freeTotal -ne 1) { 's' }) that nobody is using." } else { 'Every Microsoft 365 license you pay for is in use.' }
        $lTitle = if ($freeTotal) { "You have $freeTotal license$(if ($freeTotal -ne 1) { 's' }) nobody is using" } else { 'Every license is in use' }
        $lbody = (New-Banner 'fa-id-card' ([string]$freeTotal) 'spare' $lTitle "We checked your Microsoft 365 subscriptions on $asOf.") +
            $(if ($unused.Count) { (New-Head 'fa-list-check' 'Where the spare licenses are') + (New-Tbl @('Subscription', 'You pay for', 'In use', 'Spare') @($unused | ForEach-Object { ,@((Enc $_.name), $_.enabled, $_.used, "<b>$($_.free)</b>") })) + "<p style='font-size:13px;color:#001F54;margin:10px 0 0;'><b>What we suggest:</b> before buying licenses for new starters, we will use these spares first. If you do not expect to grow into them, we can lower the count at your next renewal so you stop paying for them. Just reply on this card and we will take care of it.</p>" } else { "<p style='font-size:13px;color:#001F54;'>Nice work: there is nothing to reclaim. We will keep an eye on this at every review.</p>" })
        $cardNotes += Save-Card 'Unused Microsoft 365 licenses' $lsum $lbody 'Efficiency' 7
    }
    if ($mfaSource) {
        $admins = @($noMfa | Where-Object { $_.admin }).Count; $nm = $noMfa.Count
        $msum = if ($nm) { "$nm $(if ($nm -eq 1) { 'person' } else { 'people' }) can still sign in with just a password$(if ($admins) { ", including $admins admin account$(if ($admins -ne 1) { 's' })" })." } else { 'Everyone is protected with multi-factor authentication.' }
        $mTitle = if ($nm) { "$nm account$(if ($nm -ne 1) { 's are' } else { ' is' }) not protected by MFA" } else { 'Everyone is protected by MFA' }
        $rows = @($noMfa | Select-Object -First 25 | ForEach-Object { ,@((Enc $_.name), (Enc $_.upn), $(if ($_.admin) { "<span style='background:#C2410C;color:#fff;font-size:11px;font-weight:700;padding:2px 7px;border-radius:999px;'>ADMIN</span>" } else { 'User' })) })
        $mbody = (New-Banner 'fa-user-lock' ([string]$nm) $(if ($nm -eq 1) { 'account' } else { 'accounts' }) $mTitle "Multi-factor authentication (MFA) stops most account takeovers. We checked every licensed account on $asOf.") +
            $(if ($nm) { (New-Head 'fa-list-check' 'Who needs to set up MFA') + (New-Tbl @('Name', 'Sign-in', 'Role') $rows) + $(if ($nm -gt 25) { "<p style='font-size:12px;color:#09507B;'>Showing 25 of $nm.</p>" } else { '' }) + "<p style='font-size:13px;color:#001F54;margin:10px 0 0;'><b>What we suggest:</b> we will help each person set up the Microsoft Authenticator app, which takes about five minutes, starting with any admin accounts. Then we will turn on a policy that requires MFA for everyone, so new accounts are protected from day one. Let us know a good time and we will walk them through it.</p>" } else { "<p style='font-size:13px;color:#001F54;'>Great job: every account has a second sign-in step set up. We will keep checking at every review.</p>" })
        $cardNotes += Save-Card 'Accounts without MFA' $msum $mbody 'Security' 6
    }
    if ($staleSource) {
        $ns = $stale.Count
        $ssum = if ($ns) { "$ns account$(if ($ns -ne 1) { 's have' } else { ' has' }) not been used in over $staleDays days but still hold$(if ($ns -eq 1) { 's' }) a license." } else { "Every licensed account has been used in the last $staleDays days." }
        $sTitle = if ($ns) { "$ns account$(if ($ns -ne 1) { 's' }) nobody has used in $staleDays days" } else { 'No stale accounts' }
        $srows = @($stale | Select-Object -First 25 | ForEach-Object { ,@((Enc $_.name), (Enc $_.upn), (Enc $_.last)) })
        $sbody = (New-Banner 'fa-user-clock' ([string]$ns) $(if ($ns -eq 1) { 'account' } else { 'accounts' }) $sTitle "Accounts that stay licensed after someone leaves cost money every month and are an easy way in for attackers. Checked $asOf from the $staleSource.") +
            $(if ($ns) { (New-Head 'fa-list-check' 'Accounts to review') + (New-Tbl @('Name', 'Sign-in', 'Last used') $srows) + $(if ($ns -gt 25) { "<p style='font-size:12px;color:#09507B;'>Showing 25 of $ns.</p>" } else { '' }) + "<p style='font-size:13px;color:#001F54;margin:10px 0 0;'><b>What we suggest:</b> tell us which of these people have left or no longer need an account. We will block sign-in, keep their mailbox and files where you need them, and take back the license so you stop paying for it.</p>" } else { "<p style='font-size:13px;color:#001F54;'>Nice: every licensed account is in use. We will keep checking at every review.</p>" })
        $cardNotes += Save-Card 'Stale Microsoft 365 accounts' $ssum $sbody 'Efficiency' 7
    }
}
$msg = "Tenant review: $freeTotal unused license$(if ($freeTotal -ne 1) { 's' }), $($noMfa.Count) account$(if ($noMfa.Count -ne 1) { 's' }) without MFA, $($stale.Count) stale account$(if ($stale.Count -ne 1) { 's' })."
Set-NodeOutput ([ordered]@{ status = $(if ($warn.Count) { 'warning' } else { 'success' }); message = $msg; plannerCards = $cardNotes; unusedLicences = $unused; accountsWithoutMfa = @($noMfa | Select-Object -First 50); staleAccounts = @($stale | Select-Object -First 50); staleSource = $staleSource; warnings = $warn })
