# ---- shared: CloudRadial assessment import (build.js prepends this to steps 2 and 3) ----
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n, $d = $null) if ($null -eq $o) { return $d }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $d }; $p = $o.PSObject.Properties[$n]; if ($p -and $null -ne $p.Value) { return $p.Value }; return $d }
function Stop-Run { param([string]$m) Set-NodeOutput @{ status = 'error'; message = $m }; throw $m }
function Read-StepInput { $i = Get-NodeInput; if ($i -is [string]) { $i = $i | ConvertFrom-Json }; return $i }

# Import workbook: sheet "Assessment" with the 51 headers of the blank template (radials.io/blankassessment).
$TemplateColumns = @('Partner Notes', 'Monthly Unit Cost', 'Project Unit Cost', 'Psa Board', 'Psa Item', 'Psa Status', 'Psa Category', 'Psa Sub Type', 'Psa Type', 'Psa Priority', 'Psa Source', 'Psa Estimated Time', 'Email List', 'Teams Webhook', 'Slack Webhook', 'Flow Webhook', 'Json Webhook', 'Script', 'Checklist', 'Category', 'Question', 'Order', 'Explanation', 'Type', 'Answer', 'Text Answer', 'Responses', 'Is Flagged', 'Notes', 'Evaluation', 'Remediation Summary', 'Remediation', 'Reference', 'Monthly Units', 'Monthly Unit Price', 'Project Units', 'Project Unit Price', 'Control Type', 'Likelihood', 'Risk', 'Risk Cost', 'Risk Impact', 'Owner', 'Updated by', 'Update Key', 'Content Update Key', 'Note Compliant', 'Note Partially Compliant', 'Note NA', 'Note Missing', 'Note Not Compliant')
$ScoreText = @{ 2 = 'Compliant'; 1 = 'Partially Compliant'; 0 = 'N/A'; -1 = 'Missing answer'; -2 = 'Not compliant' }
$Responses = 'Yes,Partially+,Not applicable=,Not checked*,No-'

function New-XlsxBytes {
    # Minimal Office Open XML workbook: one sheet named Assessment, shared strings, header + rows.
    param([string[]]$Header, [object[]]$Rows)
    Add-Type -AssemblyName System.IO.Compression
    $clean = { param($s) [System.Security.SecurityElement]::Escape(([string]$s -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')) }
    $colName = { param([int]$n) $s = ''; $n++; while ($n -gt 0) { $m = ($n - 1) % 26; $s = [char](65 + $m) + $s; $n = [int][Math]::Floor(($n - 1) / 26) }; $s }
    $strings = New-Object System.Collections.Generic.List[string]; $index = @{}
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>')
    $all = @(, $Header) + $Rows
    for ($r = 0; $r -lt $all.Count; $r++) {
        $null = $sb.Append("<row r=""$($r + 1)"">")
        $row = @($all[$r])
        for ($c = 0; $c -lt $row.Count; $c++) {
            $ref = (& $colName $c) + ($r + 1)
            $val = $row[$c]
            if ($val -is [int] -or $val -is [long] -or $val -is [double]) { $null = $sb.Append("<c r=""$ref""><v>$val</v></c>") }
            elseif (-not [string]::IsNullOrEmpty([string]$val)) {
                $sv = [string]$val
                if (-not $index.ContainsKey($sv)) { $index[$sv] = $strings.Count; $strings.Add($sv) }
                $null = $sb.Append("<c r=""$ref"" t=""s""><v>$($index[$sv])</v></c>")
            }
        }
        $null = $sb.Append('</row>')
    }
    $null = $sb.Append('</sheetData></worksheet>')
    $sst = New-Object System.Text.StringBuilder
    $null = $sst.Append("<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?><sst xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"" count=""$($strings.Count)"" uniqueCount=""$($strings.Count)"">")
    foreach ($sv in $strings) { $null = $sst.Append("<si><t xml:space=""preserve"">$(& $clean $sv)</t></si>") }
    $null = $sst.Append('</sst>')
    $files = [ordered]@{
        '[Content_Types].xml'        = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
        '_rels/.rels'                = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl/workbook.xml'            = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Assessment" sheetId="1" r:id="rId1"/></sheets></workbook>'
        'xl/_rels/workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
        'xl/styles.xml'              = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>'
        'xl/worksheets/sheet1.xml'   = $sb.ToString()
        'xl/sharedStrings.xml'       = $sst.ToString()
    }
    $ms = New-Object System.IO.MemoryStream
    $zip = New-Object System.IO.Compression.ZipArchive($ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
    foreach ($k in $files.Keys) {
        $entry = $zip.CreateEntry($k)
        $w = New-Object System.IO.StreamWriter($entry.Open(), (New-Object System.Text.UTF8Encoding($false)))
        $w.Write($files[$k]); $w.Dispose()
    }
    $zip.Dispose()
    return , $ms.ToArray()
}
function New-AssessmentWorkbook { param([object[]]$Questions)
    $wbRows = New-Object System.Collections.ArrayList
    foreach ($q in $Questions) {
        $ans = [int](Get-Prop $q 'answer' -1)
        $v = @{
            'Partner Notes' = [string](Get-Prop $q 'partnerNotes' ''); 'Category' = [string](Get-Prop $q 'category' ''); 'Question' = [string](Get-Prop $q 'question' '')
            'Order' = [int](Get-Prop $q 'order' 0); 'Explanation' = [string](Get-Prop $q 'explanation' ''); 'Type' = 'List'
            'Answer' = $ans; 'Text Answer' = $ScoreText[$ans]; 'Responses' = $Responses; 'Is Flagged' = $(if ($ans -eq -2) { 'Yes' } else { 'No' })
            'Notes' = [string](Get-Prop $q 'notes' ''); 'Evaluation' = [string](Get-Prop $q 'evaluation' '')
            'Remediation Summary' = [string](Get-Prop $q 'remediationSummary' ''); 'Remediation' = [string](Get-Prop $q 'remediation' ''); 'Reference' = [string](Get-Prop $q 'reference' '')
            'Control Type' = [int](Get-Prop $q 'controlType' 0); 'Likelihood' = [int](Get-Prop $q 'likelihood' 0); 'Risk' = [int](Get-Prop $q 'risk' 0)
            'Risk Cost' = [int](Get-Prop $q 'risk' 0); 'Risk Impact' = [int](Get-Prop $q 'riskImpact' 0); 'Updated by' = 'AutomationAI Workflow'; 'Update Key' = [string](Get-Prop $q 'updateKey' '')
        }
        $null = $wbRows.Add(@($TemplateColumns | ForEach-Object { if ($v.ContainsKey($_)) { $v[$_] } else { $null } }))
    }
    return , (New-XlsxBytes -Header $TemplateColumns -Rows $wbRows.ToArray())
}
function Get-Preview { param([object[]]$Questions) @($Questions | ForEach-Object { [ordered]@{ category = Get-Prop $_ 'category'; question = Get-Prop $_ 'question'; answer = $ScoreText[[int](Get-Prop $_ 'answer' -1)]; notes = Get-Prop $_ 'notes' } }) }

# ---- CloudRadial API ----
function Connect-Cr {
    $get = { param([string]$Name) Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue }
    $script:crBase = ([string](& $get 'CloudRadial-BaseUrl')).TrimEnd('/')
    $script:crAuth = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$(& $get 'CloudRadial-PublicKey'):$(& $get 'CloudRadial-PrivateKey')"))
    $script:crHeaders = @{ Authorization = $script:crAuth; Accept = 'application/json' }
}
if (-not (Get-Command Send-CrMultipart -ErrorAction SilentlyContinue)) {
    function script:Send-CrMultipart {
        param([string]$Path, [string]$DataJson, [byte[]]$FileBytes, [string]$FileName)
        Add-Type -AssemblyName System.Net.Http
        $client = New-Object System.Net.Http.HttpClient
        $client.DefaultRequestHeaders.Add('Authorization', $script:crAuth)
        $form = New-Object System.Net.Http.MultipartFormDataContent
        $form.Add((New-Object System.Net.Http.StringContent($DataJson, [Text.Encoding]::UTF8, 'application/json')), 'data')
        $fc = New-Object System.Net.Http.ByteArrayContent(, $FileBytes)
        $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        $form.Add($fc, 'file', $FileName)
        $resp = $client.PostAsync("$($script:crBase)$Path", $form).GetAwaiter().GetResult()
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $client.Dispose()
        if (-not $resp.IsSuccessStatusCode) { throw "HTTP $([int]$resp.StatusCode): $text" }
        return $text
    }
}
function Get-CompanyAssessments { param([int]$CompanyId) @(Get-Prop (Invoke-RestMethod -Method Get -Uri "$($script:crBase)/v2/odata/assessment?`$filter=companyId eq $CompanyId&`$top=200" -Headers $script:crHeaders) 'value' @()) }
function Find-Assessment { param($Rows, [string]$Name, [int]$Type)
    @($Rows | Where-Object { ([string](Get-Prop $_ 'title' '')).Trim() -ieq $Name -and [int](Get-Prop $_ 'type' -1) -eq $Type -and -not (Get-Prop $_ 'isDeleted' $false) } |
        Sort-Object { [int](Get-Prop $_ 'assessmentId' 0) } -Descending) | Select-Object -First 1 }
function Get-Fields { param($Row)
    # Every scalar field (long text trimmed), for comparing a run with its assessment.
    $o = [ordered]@{}
    if ($null -eq $Row) { return $o }
    foreach ($p in $Row.PSObject.Properties) {
        $v = $p.Value
        if ($null -eq $v -or $v -is [string] -or $v -is [ValueType]) { $s = [string]$v; $o[$p.Name] = $(if ($s.Length -gt 80) { $s.Substring(0, 80) + '...' } else { $v }) }
    }
    return $o }
function Get-Listing { param($Rows) @($Rows | Sort-Object { [int](Get-Prop $_ 'assessmentId' 0) } -Descending | Select-Object -First 25 | ForEach-Object { Get-Fields $_ }) }
function Invoke-AssessmentUpload {
    # The v2 API has no create endpoint (POST /v2/assessment returns 404). Like the portal's Import
    # Assessment dialog, the upload creates an assessment when assessmentId is 0, named by `name`,
    # and returns 204 with no body, so the new row is found afterwards by title and type.
    param([int]$CompanyId, [string]$CompanyName, [string]$Name, [int]$Type, [byte[]]$Bytes, [string]$Label, [hashtable]$Extra = @{})
    $data = [ordered]@{ name = $Name; assessmentId = 0; type = $Type; companyId = $CompanyId }
    foreach ($k in $Extra.Keys) { $data[$k] = $Extra[$k] }
    $fileName = 'm365-security-' + $Label + '-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd') + '.xlsx'
    $reply = ''
    try { $reply = [string](Send-CrMultipart -Path '/v2/assessment/upload' -DataJson ($data | ConvertTo-Json -Compress) -FileBytes $Bytes -FileName $fileName) }
    catch { Stop-Run "The $Label upload ('$Name', type $Type) failed, so it wasn't created: $($_.Exception.Message)" }
    $found = $null; $seen = @()
    foreach ($wait in @(0, 3, 10)) {
        if ($wait) { Start-Sleep -Seconds $wait }
        try { $seen = @(Get-CompanyAssessments $CompanyId) } catch { continue }
        $found = Find-Assessment $seen $Name $Type
        if ($found) { return $found }
    }
    $recent = @($seen | Sort-Object { [int](Get-Prop $_ 'assessmentId' 0) } -Descending | Select-Object -First 5 | ForEach-Object { "$(Get-Prop $_ 'assessmentId') '$(Get-Prop $_ 'title')' type $(Get-Prop $_ 'type')" })
    Stop-Run "CloudRadial accepted the $Label upload (reply: '$reply') but no type $Type assessment titled '$Name' appeared for $CompanyName. Newest assessments for this company: $($recent -join '; ')."
}
# ---- end shared ----
