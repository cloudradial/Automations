# =====================================================================
#  EDIT THIS STEP: your routing table.
#  Paste your own settings, engineers and skills between the @' and '@
#  lines below, then Publish and Deploy. Keep the '@ lines at the very
#  start of their line. Check the table first with Test-RoutingTable.ps1
#  (see ROUTING-TABLE.md for every column and setting).
#
#  TableSource:
#    'inline' (default)  use the three blocks below. No portal needed.
#    'knowledge'         use Settings and Engineers below, but read the
#                        skills from a CSV in AutomationAI Knowledge.
#                        Ground the "Pick the skill" node on that folder.
#    'ucp'               ignore all three and read the two CloudRadial KB
#                        articles instead (UCP partners only).
# =====================================================================
$TableSource = 'inline'

$Settings = @'
#@@SETTINGS@@
'@

$Engineers = @'
#@@ENGINEERS@@
'@

$Skills = @'
#@@SKILLS@@
'@

# ---------- nothing to edit below this line ----------
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$lines = { param($t) @(([string]$t) -split "`r?`n" | ForEach-Object { ($_ -replace [char]0xFEFF, '').Trim() } | Where-Object { $_ -ne '' }) }
Set-NodeOutput ([ordered]@{
    tableSource = ([string]$TableSource).Trim().ToLowerInvariant()
    settings    = @(& $lines $Settings)
    engineers   = @(& $lines $Engineers)
    skills      = @(& $lines $Skills)
})
