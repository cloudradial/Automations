# === STEP: Add to QBR prep card ===
# Puts this value review on the client's "QBR prep: <quarter>" Planner card, the same card QBR Data Pack keeps
# (subject "QBR prep: Q<n> <year>", stable key qbr-data-pack:<year>-Q<n>, for the quarter this run falls in).
# It only replaces its own section, the paragraphs from value-review:start to value-review:end, and QBR Data Pack
# keeps that section when it refreshes the card. With no card yet, it creates one (internal only, open).
# The section holds a summary and the full client report. This card is the workflow's only write.
# Secrets: CloudRadial-BaseUrl, CloudRadial-PublicKey, CloudRadial-PrivateKey. Set Company on this step the same
# as the step before it, so it talks to the same portal as Lookup CloudRadial Company.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Get-VrProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Get-VrSecret { param([string]$Name) $v = $null; try { $v = Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $Name -AsPlainText -ErrorAction SilentlyContinue } catch { }; return $v }
function Enc { param($s) return [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Send-VrResult { param([string]$Status, [string]$Action, [string]$Id, [string]$Subject, [string]$Message)
    Set-NodeOutput ([ordered]@{ status = $Status; cardAction = $Action; productId = $Id; cardSubject = $Subject; message = $Message; warnings = @(if ($Status -ne 'success') { $Message }) }) }
$ci = [System.Globalization.CultureInfo]::InvariantCulture

$in = Get-NodeInput
$companyId = 0; $null = [int]::TryParse([string](Get-VrProp $in 'crCompanyId'), [ref]$companyId)
$companyName = [string](Get-VrProp $in 'companyName')
if ($companyId -le 0) { Send-VrResult 'error' 'skipped' '' '' "$(if ($companyName) { $companyName } else { 'The client' }) wasn't matched to one CloudRadial company, so no Planner card was written."; return }
$periodStart = [string](Get-VrProp $in 'periodStart'); $periodEnd = [string](Get-VrProp $in 'periodEnd')
# The client report, without any page wrapper, styles or scripts, so it sits inside the card body.
$report = [string](Get-VrProp $in 'clientReportHtml')
$m = [regex]::Match($report, '(?is)<body[^>]*>(.*)</body>'); if ($m.Success) { $report = $m.Groups[1].Value }
$report = [regex]::Replace($report, '(?is)<(script|style|head|title)[^>]*>.*?</\1>', '')
$report = [regex]::Replace($report, '(?is)</?(html|body|meta|link)[^>]*>', '').Trim()
$kpis = Get-VrProp $in 'kpis'
if ($kpis -is [string]) { try { $kpis = $kpis | ConvertFrom-Json } catch { $kpis = $null } }

# This run's quarter, so the section lands on the same card QBR Data Pack posts this quarter.
$now = (Get-Date).ToUniversalTime()
$q = [int][Math]::Ceiling($now.Month / 3.0)
$Key = "qbr-data-pack:$($now.Year)-Q$q"
$Subject = "QBR prep: Q$q $($now.Year)"

# ---- the section ----
function Get-VrNum { param($v, [string]$Fmt = 'N0') if ($null -eq $v -or [string]$v -eq '') { return '' }; $d = 0.0; if ([double]::TryParse([string]$v, [System.Globalization.NumberStyles]::Float, $ci, [ref]$d)) { return $d.ToString($Fmt, $ci) }; return [string]$v }
$opened = Get-VrNum (Get-VrProp $kpis 'ticketsOpened'); $closed = Get-VrNum (Get-VrProp $kpis 'ticketsClosed')
$hours = Get-VrNum (Get-VrProp $kpis 'hoursDelivered') 'N1'
$value = Get-VrNum (Get-VrProp $kpis 'valueDelivered')
$savings = Get-VrNum (Get-VrProp $kpis 'clientSavingsDisplayValue'); if (-not $savings) { $savings = Get-VrNum (Get-VrProp $kpis 'clientSavings') }
$savingsLabel = [string](Get-VrProp $kpis 'savingsLabel'); if (-not $savingsLabel) { $savingsLabel = 'Client savings' }
$period = if ($periodStart -and $periodEnd) { "$periodStart to $periodEnd" } else { 'the requested period' }

$sec = New-Object System.Text.StringBuilder
$qbrHtml = [string](Get-VrProp $in 'qbrHtml')
$lc = Get-VrProp $in 'lifecycle'; if ($lc -is [string]) { try { $lc = $lc | ConvertFrom-Json } catch { $lc = $null } }
$lcRes = @(@(Get-VrProp $lc 'results') | Where-Object { $_ -and [int](Get-VrProp $_ 'deviceCount') -gt 0 -and @('completed', 'error', 'skipped') -notcontains [string](Get-VrProp $_ 'action') })
$order = @{ 'Replace' = 1; 'Plan replacement' = 2; 'Upgrade in place' = 3; 'Retain' = 4; 'Human review' = 5; 'Virtual machines' = 6; 'Needs data' = 7 }
$lcRes = @($lcRes | Sort-Object { $k = [string](Get-VrProp $_ 'category'); if ($order.ContainsKey($k)) { $order[$k] } else { 9 } })
$plan = ''; $talk = ''
if ($lcRes.Count) {
    $max = [math]::Max(1, (@($lcRes | ForEach-Object { [int](Get-VrProp $_ 'deviceCount') }) | Measure-Object -Maximum).Maximum)
    $trs = foreach ($r in $lcRes) { $cat = [string](Get-VrProp $r 'category'); $nd = [int](Get-VrProp $r 'deviceCount'); $crit = ([string](Get-VrProp $r 'priority')) -eq 'Critical'; $pct = [math]::Max(4, [math]::Round(100 * $nd / $max, 0)); $col = if ($crit) { '#C2410C' } else { '#1282A2' }
        "<tr><td style='width:34%;padding:4px 8px 4px 0;font-size:13px;color:#001F54;'>$(Enc $cat)$(if ($crit) { " <span style='background:#C2410C;color:#fff;font-size:10px;font-weight:700;padding:1px 6px;border-radius:999px;'>CRITICAL</span>" })</td><td style='padding:4px 0;'><div style='background:#E8F3F7;border-radius:4px;height:16px;width:100%;'><div style='background:$col;border-radius:4px;height:16px;width:$pct%;'></div></div></td><td style='width:14%;padding:4px 0 4px 8px;text-align:right;font-size:13px;font-weight:600;color:#001F54;'>$nd</td></tr>" }
    $evalN = [int](Get-VrProp $lc 'evaluated')
    $plan = "<p style='margin:18px 0 6px 0;font-size:14px;font-weight:600;color:#001F54;'>Endpoint refresh plan ($(@($lcRes | ForEach-Object { [int](Get-VrProp $_ 'deviceCount') } | Measure-Object -Sum).Sum) of $evalN computers)</p><table style='width:100%;border-collapse:collapse;'>$($trs -join '')</table>"
    $rep = @($lcRes | Where-Object { [string](Get-VrProp $_ 'category') -eq 'Replace' }) | Select-Object -First 1
    $pl = @($lcRes | Where-Object { [string](Get-VrProp $_ 'category') -eq 'Plan replacement' }) | Select-Object -First 1
    $tl = @()
    if ($rep) { $tl += "<b>$([int](Get-VrProp $rep 'deviceCount')) computers are due for replacement.</b> Bring a refresh quote and agree a schedule." }
    if ($pl) { $tl += "<b>$([int](Get-VrProp $pl 'deviceCount')) more are approaching the end of their refresh cycle.</b> Plan them into next year's budget." }
    if ($tl.Count) { $talk = "<ul style='margin:0 0 0 18px;color:#001F54;font-size:14px;line-height:1.6;'>" + (($tl | ForEach-Object { "<li>$_</li>" }) -join '') + '</ul>' }
}
$brief = $qbrHtml.Replace('<!--ENDPOINT-PLAN-->', $plan).Replace('<!--ENDPOINT-TALK-->', $talk)
$sec = New-Object System.Text.StringBuilder
$null = $sec.Append('<p><em>value-review:start</em></p>')
$null = $sec.Append($brief)
$null = $sec.Append("<p style='font-size:12px;color:#09507B;margin:12px 0 0;'>The full client report is in the Report Archive under Value Reviews. Added $($now.ToString('yyyy-MM-dd HH:mm', $ci)) UTC by the Value Review workflow; a new value review replaces this section.</p><p><em>value-review:end</em></p>")
$section = $sec.ToString()

# ---- the card ----
try {
    $base = [string](Get-VrSecret 'CloudRadial-BaseUrl'); $pub = [string](Get-VrSecret 'CloudRadial-PublicKey'); $priv = [string](Get-VrSecret 'CloudRadial-PrivateKey')
    if (-not $base -or -not $pub -or -not $priv) { throw 'CloudRadial-BaseUrl, CloudRadial-PublicKey or CloudRadial-PrivateKey is missing for this step.' }
    $base = $base.Trim().TrimEnd('/')
    $h = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($pub.Trim()):$($priv.Trim())")); Accept = 'application/json' }

    # Every card for this company (the list stops at 200 rows, so page it).
    $cards = New-Object System.Collections.ArrayList; $skip = 0
    for ($n = 0; $n -lt 50; $n++) {
        $resp = Invoke-RestMethod -Method Get -Uri "$base/v2/odata/product?`$filter=companyId eq $companyId&`$top=200&`$skip=$skip" -Headers $h
        $batch = @(@(Get-VrProp $resp 'value') | Where-Object { $null -ne $_ })
        foreach ($c in $batch) { if ([int](Get-VrProp $c 'companyId') -eq $companyId) { $null = $cards.Add($c) } }
        if ($batch.Count -lt 200) { break }
        $skip += 200
    }
    $card = @($cards | Where-Object { ([string](Get-VrProp $_ 'subject')).Trim() -ieq $Subject -or ([string](Get-VrProp $_ 'body')).Contains($Key) }) | Select-Object -First 1

    if ($null -ne $card) {
        $id = [string](Get-VrProp $card 'productId')
        $body = [string](Get-VrProp $card 'body')
        $st = $body.IndexOf('value-review:start'); $en = $(if ($st -ge 0) { $body.IndexOf('value-review:end', $st) } else { -1 })
        if ($st -ge 0 -and $en -ge 0 -and $body.LastIndexOf('<p', $st) -ge 0 -and $body.IndexOf('</p>', $en) -ge 0) {
            $from = $body.LastIndexOf('<p', $st); $to = $body.IndexOf('</p>', $en) + 4
            $new = $body.Substring(0, $from) + $section + $body.Substring($to)
        }
        else {
            # Above QBR Data Pack's footer, else above the key marker, else at the end.
            $at = $body.IndexOf('This card is prepared by the QBR Data Pack')
            if ($at -lt 0) { $at = $body.IndexOf($Key) }
            $at = $(if ($at -ge 0) { $body.LastIndexOf('<p', $at) } else { -1 })
            $new = $(if ($at -ge 0) { $body.Substring(0, $at) + $section + $body.Substring($at) } else { $body + $section })
        }
        $ops = @(@{ op = 'replace'; path = '/body'; value = $new })
        $null = Invoke-RestMethod -Method Patch -Uri "$base/v2/product/$id" -Headers $h -ContentType 'application/json-patch+json' -Body (ConvertTo-Json -InputObject $ops -Depth 5)
        Send-VrResult 'success' 'updated' $id $Subject "The value review was added to the '$Subject' Planner card on $companyName's board."
        return
    }

    $intro = "<p>This CloudRadial Planner card gathers $(Enc $companyName)'s numbers for the quarterly business review (Q$q $($now.Year)). The QBR Data Pack automation adds devices, tickets and licenses when it runs.</p>"
    $new = [ordered]@{
        companyId = $companyId; subject = $Subject; body = "$intro$section<p><em>$Key</em></p>"; summary = "Value review for $period."
        category = 'Efficiency'; productCategoryId = 7; status = 0; priority = 0
        datePublished = $now.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', $ci); isRequired = $false; isShowPrice = $false; isClientVisible = $false
    }
    $r = Invoke-RestMethod -Method Post -Uri "$base/v2/product" -Headers $h -ContentType 'application/json' -Body (ConvertTo-Json -InputObject $new -Depth 5)
    $newId = [string](Get-VrProp (Get-VrProp $r 'data') 'productId'); if (-not $newId) { $newId = [string](Get-VrProp $r 'productId') }
    Send-VrResult 'success' 'created' $newId $Subject "The '$Subject' Planner card was created on $companyName's board with the value review."
}
catch {
    Send-VrResult 'error' 'failed' '' $Subject "The value review was built, but the Planner card couldn't be written: $($_.Exception.Message)"
}