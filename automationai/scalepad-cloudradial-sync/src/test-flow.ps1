param([string]$InputJson = '{}', [string]$Tag = 'flow')
# Simulates the platform: resolve -> For Each target -> report, with the harness mocks.
$d = $PSScriptRoot
$in = "$d\$Tag-in.json"; Set-Content $in $InputJson
pwsh -NoProfile -File "$d\harness.ps1" -Step 'built-node-resolve.ps1' -InFile $in -OutFile "$d\$Tag-resolve.json" | Select-Object -First 1
if ($LASTEXITCODE) { 'RESOLVE FAILED'; exit 1 }
$resolve = Get-Content "$d\$Tag-resolve.json" -Raw | ConvertFrom-Json
$items = @()
$n = 0
foreach ($t in @($resolve.targets)) {
    $n++
    $tf = "$d\$Tag-target-$n.json"; $t | ConvertTo-Json -Depth 30 | Set-Content $tf
    pwsh -NoProfile -File "$d\harness.ps1" -Step 'built-node-sync.ps1' -InFile $in -OutFile "$d\$Tag-item-$n.json" -ItemFile $tf | Select-Object -First 1
    $o = Get-Content "$d\$Tag-item-$n.json" -Raw | ConvertFrom-Json
    "   [$($o.companyName)] " + ($o.messages -join ' | ').Substring(0, [Math]::Min(400, ($o.messages -join ' | ').Length))
    $items += $o
}
$rin = "$d\$Tag-report-in.json"
@{ sync = @{ results = $items; items = @($items | ForEach-Object { @{ index = 0; status = 'succeeded'; output = $_; error = $null } }); succeededCount = $items.Count; failedCount = 0; total = $items.Count }; resolve = $resolve } | ConvertTo-Json -Depth 40 | Set-Content $rin
pwsh -NoProfile -File "$d\harness.ps1" -Step 'built-node-summary.ps1' -InFile $rin -OutFile "$d\$Tag-report.json" 2>&1 | Where-Object { $_ -match '^\[|/v2/article|archiveitem|THREW' } | ForEach-Object { $_.Substring(0, [Math]::Min(300, $_.Length)) }
