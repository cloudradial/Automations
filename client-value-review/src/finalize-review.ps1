$nodeInput = Get-NodeInput
if ($null -eq $nodeInput) { $nodeInput = @{} }

function HtmlEncode([string]$text) {
  if ($null -eq $text) { return '' }
  [System.Net.WebUtility]::HtmlEncode($text)
}

$companyName = [string](Get-NodeInput -Name 'companyName')
$periodStart = [string](Get-NodeInput -Name 'periodStart')
$periodEnd = [string](Get-NodeInput -Name 'periodEnd')
$internalSubject = [string](Get-NodeInput -Name 'internalSubject')
$clientReportHtmlBase = [string](Get-NodeInput -Name 'clientReportHtmlBase')
# Endpoint lifecycle and Microsoft 365 security sections, from the two Planner-card steps.
function Read-VrJson { param($x) if ($x -is [string]) { try { return ($x | ConvertFrom-Json) } catch { return $null } }; return $x }
function Get-VrField { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { return $o[$n] }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
$lcOut = Read-VrJson (Get-NodeInput -Name 'lifecycle'); $ssOut = $null
$extraHtml = ''
$lcMsg = [string](Get-VrField $lcOut 'message'); if (-not $lcMsg) { $lcMsg = [string](Get-VrField $lcOut 'summary') }
$lcResults = @(@(Get-VrField $lcOut 'results') | Where-Object { $_ -and [int](Get-VrField $_ 'deviceCount') -gt 0 -and @('completed', 'error') -notcontains [string](Get-VrField $_ 'action') })
if ($lcMsg -or $lcResults.Count) {
    $evalN = [int](Get-VrField $lcOut 'evaluated'); $flagN = [int](Get-VrField $lcOut 'flaggedEndpoints')
    $extraHtml += "<div style='display:flex;align-items:center;gap:10px;margin:14px 0 6px;padding:8px 12px;background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid #B3C9D5;border-radius:10px'><span style='background:#001F54;color:#B3C9D5;width:28px;height:28px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center'><i class='fal fa-laptop'></i></span><span style='font-size:15px;font-weight:600;color:#001F54'>Endpoint lifecycle</span></div>"
    $extraHtml += "<div style='background:linear-gradient(135deg,#001F54 0%,#09507B 55%,#1282A2 100%);color:#fff;padding:14px 18px;border-radius:12px;border-left:6px solid #B3C9D5;box-shadow:0 4px 14px rgba(0,31,84,.3);margin:0 0 10px;'><div style='font-size:18px;font-weight:600;'><i class='fal fa-laptop' style='color:#B3C9D5;'></i>&nbsp; $flagN of $evalN computers need a decision</div><div style='font-size:13px;opacity:.9;margin-top:4px;'>Each group below has its own card on your Planner with the devices and next steps.</div></div>"
    $cells = foreach ($r in $lcResults) { $cat = [string](Get-VrField $r 'category'); $nDev = [int](Get-VrField $r 'deviceCount'); $note = [string](Get-VrField $r 'note'); $crit = ([string](Get-VrField $r 'priority')) -eq 'Critical'
        $ic = switch ($cat) { 'Replace' { 'fa-arrows-rotate' } 'Plan replacement' { 'fa-calendar-days' } 'Upgrade in place' { 'fa-circle-up' } 'Retain' { 'fa-shield-check' } 'Needs data' { 'fa-circle-question' } 'Human review' { 'fa-user-gear' } 'Virtual machines' { 'fa-server' } default { 'fa-laptop' } }
        $edge = if ($crit) { '#C2410C' } else { '#1282A2' }
        "<td style='width:50%;padding:5px;vertical-align:top;'><div style='background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid $edge;border-radius:10px;padding:12px;'><div style='display:flex;align-items:center;gap:10px;'><span style='background:#001F54;color:#B3C9D5;width:30px;height:30px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center;'><i class='fal $ic'></i></span><span style='font-size:15px;font-weight:600;color:#001F54;'>$([System.Net.WebUtility]::HtmlEncode($cat))</span><span style='margin-left:auto;font-size:22px;font-weight:700;color:#001F54;'>$nDev</span></div><div style='font-size:12px;color:#09507B;margin-top:6px;'>$([System.Net.WebUtility]::HtmlEncode($note))</div></div></td>" }
    $cellArr = @($cells); $rowsT = @(); for ($i = 0; $i -lt $cellArr.Count; $i += 2) { $rowsT += '<tr>' + $cellArr[$i] + $(if ($i + 1 -lt $cellArr.Count) { $cellArr[$i + 1] } else { "<td style='width:50%;'></td>" }) + '</tr>' }
    if ($rowsT.Count) { $extraHtml += "<table style='width:100%;border-collapse:collapse;'>$($rowsT -join '')</table>" } elseif ($lcMsg) { $extraHtml += "<p style='font-size:13px;color:#001F54;'>$([System.Net.WebUtility]::HtmlEncode($lcMsg))</p>" }
}
$ssStatus = [string](Get-VrField $ssOut 'status'); $ssMsg = [string](Get-VrField $ssOut 'message'); $ssCards = @(Get-VrField $ssOut 'plannerCards' | Where-Object { $_ })
if ($ssStatus -and $ssStatus -ne 'skipped') {
    $extraHtml += "<div style='display:flex;align-items:center;gap:10px;margin:22px 0 8px;padding:8px 12px;background:#E8F3F7;border:1px solid #B3D7E3;border-left:4px solid #B3C9D5;border-radius:10px'><span style='background:#001F54;color:#B3C9D5;width:32px;height:32px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center'><i class='fal fa-shield-halved'></i></span><span style='font-size:17px;font-weight:600;color:#001F54'>Microsoft 365 security</span></div><p>" + [System.Net.WebUtility]::HtmlEncode($ssMsg) + '</p>'
    if ($ssCards.Count) { $extraHtml += '<ul>' + (($ssCards | ForEach-Object { '<li>' + [System.Net.WebUtility]::HtmlEncode([string]$_) + '</li>' }) -join '') + '</ul>' }
}
function Apply-Brand { param([string]$Html, $B) if ([string]::IsNullOrEmpty($Html) -or $null -eq $B) { return $Html }; $map = [ordered]@{ '#001F54' = $B.primary; '#09507B' = $B.secondary; '#1282A2' = $B.accent; '#B3C9D5' = $B.light; '#E8F3F7' = $B.soft; '#B3D7E3' = $B.border }; foreach ($k in $map.Keys) { $val = [string]$map[$k]; if ($val -match '^#[0-9A-Fa-f]{6}$' -and $val -ne $k) { $Html = $Html.Replace($k, $val) } }; return $Html }
$finBrand = Get-NodeInput -Name 'brand'; if ($finBrand -is [string]) { try { $finBrand = $finBrand | ConvertFrom-Json } catch { $finBrand = $null } }
if ($extraHtml) { $clientReportHtmlBase = $clientReportHtmlBase + (Apply-Brand $extraHtml $finBrand) }
$internalSectionsHtml = [string](Get-NodeInput -Name 'internalSectionsHtml')
$buildGaps = @(Get-NodeInput -Name 'buildGaps')
$cwMatchCount = Get-NodeInput -Name 'cwMatchCount'
$cwMatches = @(Get-NodeInput -Name 'cwMatches')
$lookupArchiveGapText = [string](Get-NodeInput -Name 'lookupArchiveGapText')
$archivePosted = Get-NodeInput -Name 'archivePosted'
$archiveGapText = [string](Get-NodeInput -Name 'archiveGapText')
$emailGapText = [string](Get-NodeInput -Name 'emailGapText')

$gaps = New-Object System.Collections.Generic.List[string]
foreach ($g in @($buildGaps)) {
  if (-not [string]::IsNullOrWhiteSpace([string]$g)) { [void]$gaps.Add([string]$g) }
}
if (-not [string]::IsNullOrWhiteSpace($lookupArchiveGapText) -and $lookupArchiveGapText -notlike 'CloudRadial archive skipped because ConnectWise company was not uniquely resolved.*') {
  [void]$gaps.Add($lookupArchiveGapText)
}
if ($null -ne $archivePosted) {
  if ((([string]$archivePosted) -ne 'true') -and -not [string]::IsNullOrWhiteSpace($archiveGapText)) { [void]$gaps.Add($archiveGapText) }
}
if (-not [string]::IsNullOrWhiteSpace($emailGapText)) { [void]$gaps.Add($emailGapText) }

if ([int]$cwMatchCount -gt 1) {
  $matchText = (@($cwMatches) | ForEach-Object { "$(HtmlEncode ([string]$_.name)) (ID $(HtmlEncode ([string]$_.id)))" }) -join ', '
  [void]$gaps.Add("Workflow stopped after ConnectWise company lookup because multiple exact matches were returned: $matchText")
}

$flags = @(Get-NodeInput -Name 'flags')
$startItems = @(@($gaps.ToArray()) + @($flags) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$startBody = if ($startItems.Count -gt 0) {
  "<ul style='margin:0;padding-left:18px;line-height:1.5;'><li>$((@($startItems) | ForEach-Object { HtmlEncode ([string]$_) }) -join '</li><li>')</li></ul>"
} else {
  "<div style='line-height:1.5;'>No data gaps or flagged items.</div>"
}
$gapHtml = "<table role='presentation' width='100%' cellpadding='0' cellspacing='0' style='margin:8px 0 12px 0;'><tr><td style='background:#fef2f2;border:1px solid #fecaca;border-radius:6px;padding:12px 16px;'><div style='font-size:14px;font-weight:bold;color:#b91c1c;margin-bottom:6px;'>Start here</div>$startBody</td></tr></table>"

if ($internalSectionsHtml.Contains('<!--START_HERE-->')) {
  $internalReportHtml = $internalSectionsHtml.Replace('<!--START_HERE-->', $gapHtml)
} else {
  $internalReportHtml = "<html><body style='font-family:Segoe UI,Arial,sans-serif;'>$gapHtml$internalSectionsHtml</body></html>"
}

Set-NodeOutput @{
  status = 'success'
  message = 'Finalized review outputs.'
  internalSubject = $internalSubject
  internalReportHtml = $internalReportHtml
  clientReportHtml = $clientReportHtmlBase
  finalGaps = @($gaps.ToArray())
}
