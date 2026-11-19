$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
# === NODE: Put the employee on leave ===
# Runs from the "Employee Leave" portal form (Action question). Disables the employee's Microsoft 365 sign-in
# and signs them out everywhere, then writes an internal note on the request ticket and sends the manager a Signal.
# Form Field IDs: leaveUser (employee email), leaveType, returnDate. A leave type containing "return" turns sign-in
# back on. Optional input: cloudradial_company (use that portal's CloudRadial-*-<suffix> secrets). A run with
# "confirm": false previews only.
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function J { param($x) if ($x -is [string]) { try { return ($x | ConvertFrom-Json) } catch { return $null } }; return $x }
function Sec { param([string[]]$names) foreach ($n in $names) { $v = [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue); if ($v) { return $v.Trim() } }; return '' }
function ErrText { param($e) $t = $e.Exception.Message; if ($e.ErrorDetails -and $e.ErrorDetails.Message) { try { $j = $e.ErrorDetails.Message | ConvertFrom-Json; if ($j.error.message) { $t = $j.error.message } } catch { $t = $e.ErrorDetails.Message } }; return $t }

$in = Get-NodeInput; $trig = J (P $in 'trigger'); if ($null -eq $trig) { $trig = $in }
function Ans { param([string]$key, [string]$label) $v = P $trig $key; if ($null -eq $v -or [string]$v -eq '') { $qs = @(P (P $trig 'Ticket') 'Questions'); foreach ($q in $qs) { if ([string](P $q 'Id') -eq $key -or [string](P $q 'Label') -eq $label) { $v = P $q 'Value' } } }; $s = ([string]$v).Trim(); if ($s -match '^@') { $s = '' }; return $s }

$target = Ans 'leaveUser' 'Employee going on leave'
$leaveType = Ans 'leaveType' 'Type of leave'; if (-not $leaveType) { $leaveType = 'Leave' }
$returnDate = Ans 'returnDate' 'Expected return date'
$returnTxt = ''; if ($returnDate) { try { $returnTxt = ([datetime]$returnDate).ToString('MMMM d, yyyy') } catch { $returnTxt = $returnDate } }
$confirmTxt = [string](P $trig 'confirm'); $confirm = -not ($confirmTxt -match '^(?i)(false|0|no)$')
$ticketId = [string](P (P $trig 'ticket') 'id'); if (-not $ticketId) { $ticketId = [string](P $trig 'ticketId') }
$company = P $trig 'company'; $companyId = [int](P $company 'id'); $companyName = [string](P $company 'name')
$tenantId = [string](P $company 'tenantId'); if (-not $tenantId) { $tenantId = [string](P $trig 'tenantId') }
$user = P $trig 'user'; $userId = [string](P $user 'id'); $userName = [string](P $user 'name'); $userEmail = [string](P $user 'email')
$crSuffix = [string](P $trig 'cloudradial_company')
$crSuffix = ($crSuffix.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')

$status = 'error'; $msg = ''; $done = New-Object System.Collections.Generic.List[string]; $warnings = New-Object System.Collections.Generic.List[string]; $display = $target

if (-not $target -or $target -notmatch '@') { $msg = 'Nothing was changed. Enter the email address of the employee going on leave.' }
elseif (-not $tenantId) { $msg = "Nothing was changed. $companyName has no Microsoft 365 tenant ID saved in the portal." }
elseif ($userEmail -and $target -ieq $userEmail) { $msg = 'Nothing was changed. You can''t put your own account on leave from this form.' }
else {
    try {
        $cid = Sec @('M365-ClientId', 'M365-ClientID', 'Entra-ClientID', 'Graph-ClientId'); $csec = Sec @('M365-ClientSecret', 'Entra-ClientSecret', 'Graph-ClientSecret')
        if (-not $cid -or -not $csec) { throw 'The M365-ClientId or M365-ClientSecret runner secret is missing.' }
        try { $tok = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body @{ client_id = $cid; client_secret = $csec; scope = 'https://graph.microsoft.com/.default'; grant_type = 'client_credentials' } }
        catch { throw "Couldn't sign in to the client's Microsoft 365 tenant: $(ErrText $_)" }
        $gh = @{ Authorization = "Bearer $($tok.access_token)"; 'Content-Type' = 'application/json' }
        $g = 'https://graph.microsoft.com/v1.0'
        try { $u = Invoke-RestMethod -Method GET -Uri "$g/users/$([uri]::EscapeDataString($target))?`$select=id,displayName,userPrincipalName,accountEnabled" -Headers $gh }
        catch { throw "There is no Microsoft 365 user $target in $($companyName)'s tenant." }
        $display = "$($u.displayName) ($($u.userPrincipalName))"
        $returning = $leaveType -match '(?i)return|back'
        if ($returning) {
            if (-not $confirm) { $status = 'preview'; $msg = "Preview: would turn Microsoft 365 sign-in back on for $display." }
            else { if (-not $u.accountEnabled) { try { $null = Invoke-RestMethod -Method PATCH -Uri "$g/users/$($u.id)" -Headers $gh -Body (@{ accountEnabled = $true } | ConvertTo-Json); $done.Add('Microsoft 365 sign-in turned back on') } catch { throw "Microsoft 365 didn't turn sign-in back on: $(ErrText $_)" } } else { $done.Add('Microsoft 365 sign-in was already on') }
                $status = 'success'; $msg = "Welcome back, $($u.displayName): $($done -join ', ')." }
        }
        elseif (-not $confirm) { $status = 'preview'; $msg = "Preview: would disable Microsoft 365 sign-in for $display and sign them out of every device$(if (-not $u.accountEnabled) { ' (sign-in is already disabled)' })." }
        else {
            if ($u.accountEnabled) { try { $null = Invoke-RestMethod -Method PATCH -Uri "$g/users/$($u.id)" -Headers $gh -Body (@{ accountEnabled = $false } | ConvertTo-Json) ; $done.Add('Microsoft 365 sign-in disabled') } catch { throw "Microsoft 365 didn't disable sign-in: $(ErrText $_)" } }
            else { $done.Add('Microsoft 365 sign-in was already disabled') }
            try { $null = Invoke-RestMethod -Method POST -Uri "$g/users/$($u.id)/revokeSignInSessions" -Headers $gh; $done.Add('signed out of every device') } catch { $warnings.Add("Sessions not revoked: $(ErrText $_)") }
            $status = 'success'
            $msg = "$($u.displayName) is set up for $($leaveType.ToLower()): $($done -join ', ').$(if ($returnTxt) { " Expected back $returnTxt." })"
        }
    } catch { $status = 'error'; $msg = "Nothing was changed. $($_.Exception.Message)" }
}

# ---- Internal note on the request ticket (ConnectWise) ----
$noted = $false
if ($ticketId -match '^\d+$' -and [int64]$ticketId -gt 0 -and $status -ne 'preview') {
    try {
        $cwApiUrl = (Sec @('CW-ApiUrl')).TrimEnd('/'); $pair = "{0}+{1}:{2}" -f (Sec @('CW-CompanyID')), (Sec @('CW-PublicKey')), (Sec @('CW-PrivateKey'))
        $cwH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair)); clientId = (Sec @('CW-ClientId')); Accept = 'application/json' }
        try { $rawB = Invoke-WebRequest -Method Get -Uri "$cwApiUrl/service/boards?pageSize=1" -Headers $cwH; $mB = [regex]::Match([string]$rawB.Content, 'https://[^/"]+/[^/"]+/apis/3\.0'); if ($mB.Success) { $cwApiUrl = $mB.Value } } catch { }
        $note = "Employee leave (AutomationAI)`nRequested by: $userName`nEmployee: $display`nLeave: $leaveType$(if ($returnTxt) { ", back $returnTxt" })`nResult: $msg$(if ($warnings.Count) { "`nWarnings: $($warnings -join '; ')" })"
        $nb = @{ text = $note; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false } | ConvertTo-Json
        try { $null = Invoke-WebRequest -Method Post -Uri "$cwApiUrl/service/tickets/$ticketId/notes" -Headers $cwH -ContentType 'application/json' -Body $nb -MaximumRedirection 0 -SkipHttpErrorCheck; $noted = $true } catch { if ($_.Exception.Message -match '(?i)redirect|current state of the object') { $noted = $true } else { throw } }
    } catch { $warnings.Add("Ticket note not added: $($_.Exception.Message)") }
}

# ---- Signal to the manager who submitted the form ----
$signaled = $false
if ($status -ne 'preview' -and $companyId -gt 0 -and $userId) {
    try {
        $sfx = if ($crSuffix) { "-$crSuffix" } else { '' }; $crB = (Sec @("CloudRadial-BaseUrl$sfx", 'CloudRadial-BaseUrl')).TrimEnd('/'); $crPu = Sec @("CloudRadial-PublicKey$sfx", 'CloudRadial-PublicKey'); $crPr = Sec @("CloudRadial-PrivateKey$sfx", 'CloudRadial-PrivateKey')
        $crH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPu):$($crPr)")); Accept = 'application/json' }
        $short = $display; $ix = $short.IndexOf(' ('); if ($ix -gt 0) { $short = $short.Substring(0, $ix) }
        $title = if ($status -eq 'success' -and $leaveType -match '(?i)return|back') { "$short is back" } elseif ($status -eq 'success') { "Leave is set up for $short" } else { 'Your leave request needs a technician' }
        $sb = @{ companyIds = @($companyId); users = @($userId); priority = $(if ($status -eq 'success') { 0 } else { 1 }); title = $title; body = $msg; expiresAt = (Get-Date).ToUniversalTime().AddDays(1).ToString('o'); dedupeKey = "leave-$ticketId-$status" } | ConvertTo-Json -Depth 5
        $null = Invoke-RestMethod -Method Post -Uri "$crB/v2/signalmessage" -Headers $crH -ContentType 'application/json' -Body $sb; $signaled = $true
    } catch { $warnings.Add("Signal not sent: $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })") }
}

Set-NodeOutput ([ordered]@{
    status = $status; message = $msg; employee = $display; leaveType = $leaveType; returnDate = $returnTxt
    ticketId = $ticketId; ticketNoted = $noted; signalSent = $signaled; done = @($done); warnings = @($warnings)
    internal_note = "Employee leave for $display requested by $userName ($companyName): $msg"
})
