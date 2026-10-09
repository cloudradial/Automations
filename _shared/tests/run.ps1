# Runs every _shared test: the five PowerShell library suites (each in its own pwsh process) and the inject.js test.
# Usage: pwsh -NoProfile -File _shared/tests/run.ps1
# The inject.js test needs js-yaml: run "npm install" in _shared, or set JS_YAML_PATH.
$ErrorActionPreference = 'Stop'
$failed = @()
foreach ($t in @('test-psa.ps1', 'test-graph.ps1', 'test-plan.ps1', 'test-cloudradial.ps1', 'test-exchange.ps1')) {
    Write-Host "--- $t"
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot $t)
    if ($LASTEXITCODE -ne 0) { $failed += $t }
}
# Ticket lists, notes, ConnectWise reply shape and redirects, and Postmark (psa-tickets.ps1, the ticket and
# redirect functions in psa.ps1, postmark.ps1).
foreach ($t in @('test-psa-tickets.ps1', 'test-psa-redirects.ps1', 'test-postmark.ps1')) {
    Write-Host "--- $t"
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot $t)
    if ($LASTEXITCODE -ne 0) { $failed += $t }
}
Write-Host '--- test-inject.js'
& node (Join-Path $PSScriptRoot 'test-inject.js')
if ($LASTEXITCODE -ne 0) { $failed += 'test-inject.js' }
if ($failed.Count) { Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host 'All _shared tests passed.'
exit 0
