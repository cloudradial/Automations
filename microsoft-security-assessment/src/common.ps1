# ---- shared: CloudRadial assessments (build.js prepends this to steps 2 and 3) ----
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n, $d = $null) if ($null -eq $o) { return $d }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $d }; $p = $o.PSObject.Properties[$n]; if ($p -and $null -ne $p.Value) { return $p.Value }; return $d }
function Stop-Run { param([string]$m) Set-NodeOutput @{ status = 'error'; message = $m }; throw $m }
function Read-StepInput { $i = Get-NodeInput; if ($i -is [string]) { $i = $i | ConvertFrom-Json }; return $i }

$ScoreText = @{ 2 = 'Compliant'; 1 = 'Partially Compliant'; 0 = 'N/A'; -1 = 'Missing answer'; -2 = 'Not compliant' }

#{{CLOUDRADIAL}}
# The review's questions in the shape Sync-CrAssessment takes. updateKey is the review's stable GUID per check, so a
# rerun (or an assessment first made by the old workbook upload) updates the same questions.
function ConvertTo-CrQuestions { param([object[]]$Questions)
    @(foreach ($q in $Questions) {
        $ans = [int](Get-Prop $q 'answer' -1)
        $ref = [string](Get-Prop $q 'reference' '')
        $exp = [string](Get-Prop $q 'explanation' ''); if ($ref) { $exp = ($exp + ' Reference: ' + $ref).Trim() }
        , ([ordered]@{
            updateKey = [string](Get-Prop $q 'updateKey' ''); category = [string](Get-Prop $q 'category' ''); label = [string](Get-Prop $q 'question' '')
            order = [int](Get-Prop $q 'order' 0); explanation = $exp; evaluationInfo = [string](Get-Prop $q 'evaluation' '')
            remediationInfo = [string](Get-Prop $q 'remediation' ''); remediationLineItem = [string](Get-Prop $q 'remediationSummary' '')
            controlType = [int](Get-Prop $q 'controlType' 0); likelihood = [int](Get-Prop $q 'likelihood' 0); risk = [int](Get-Prop $q 'risk' 0)
            riskCost = [int](Get-Prop $q 'risk' 0); riskImpact = [int](Get-Prop $q 'riskImpact' 0)
            value = $ans; isFlagged = ($ans -eq -2); publicNotes = [string](Get-Prop $q 'notes' ''); privateNotes = [string](Get-Prop $q 'partnerNotes' '')
        })
    })
}
function Get-Preview { param([object[]]$Questions) @($Questions | ForEach-Object { [ordered]@{ category = Get-Prop $_ 'category'; question = Get-Prop $_ 'question'; answer = $ScoreText[[int](Get-Prop $_ 'answer' -1)]; notes = Get-Prop $_ 'notes' } }) }
function Get-CompanyAssessments { param([int]$CompanyId) @(Get-CrAll "/v2/odata/assessment?`$filter=$([uri]::EscapeDataString("companyId eq $CompanyId"))") }
function Get-AssessmentType { param($Row) $t = [string](Get-Prop $Row 'type' ''); switch ($t) { 'Template' { 10 } 'Assessment' { 20 } 'Assessment_Run' { 30 } 'Assessment_Archive' { 50 } default { if ($t -match '^\d+$') { [int]$t } else { -1 } } } }
function Find-Assessment { param($Rows, [string]$Name, [int]$Type)
    @($Rows | Where-Object { ([string](Get-Prop $_ 'title' '')).Trim() -ieq $Name -and (Get-AssessmentType $_) -eq $Type -and -not (Get-Prop $_ 'isDeleted' $false) } |
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
# ---- end shared ----
