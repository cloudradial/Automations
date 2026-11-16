# Runs the goal workflow's "Read the run input" step in strict mode, in a child scope, with several inputs.
# Usage: pwsh -NoProfile -File test-step.ps1 <path to the extracted step script>
param([Parameter(Mandatory)][string]$StepPath)
Set-StrictMode -Version Latest
$src = Get-Content -Raw $StepPath
$cases = @(
    @{ in = $null; want = 'every active client' },
    @{ in = ''; want = 'every active client' },
    @{ in = '{"clients":"Contoso Ltd, Fabrikam Inc"}'; want = 'limited to: Contoso Ltd, Fabrikam Inc' },
    @{ in = [pscustomobject]@{ trigger = [pscustomobject]@{ clients = 'Contoso Ltd' } }; want = 'limited to: Contoso Ltd' },
    @{ in = @{ other = 1 }; want = 'every active client' },
    @{ in = 'not json'; want = 'every active client' }
)
$fail = 0
foreach ($c in $cases) {
    $global:ChIn = $c.in; $global:ChOut = $null
    function Get-NodeInput { $global:ChIn }
    function Set-NodeOutput { param($o) $global:ChOut = $o }
    try { & ([scriptblock]::Create($src)) } catch { $fail++; "FAIL threw: $($_.Exception.Message)"; continue }
    if ($global:ChOut.status -ne 'success' -or -not ([string]$global:ChOut.message).Contains($c.want) -or -not ([string]$global:ChOut.request).Contains('Today is')) { $fail++; "FAIL want '$($c.want)', got '$($global:ChOut.message)'" }
}
"step cases: $($cases.Count - $fail) passed, $fail failed"
exit $fail
