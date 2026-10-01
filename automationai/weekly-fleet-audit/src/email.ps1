# =====================================================================
#  Weekly Fleet Audit - Build Email step
#  Turns the Fleet Audit step's output (its node output arrives as this
#  step's input) into the subject and HTML body Deliver Result sends.
#  The body is one line with single-quoted attributes and no double quotes
#  or backslashes, because Send Audit's binding puts it inside a JSON string.
# =====================================================================
$ErrorActionPreference = 'Stop'
function Get-Prop { param($o, $n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function Enc { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
function Num { param($v) $n = 0; [void][int]::TryParse([string]$v, [ref]$n); $n }
function Plural { param([int]$n, [string]$one, [string]$many) "$n $(if ($n -eq 1) { $one } else { $many })" }

$a = $null; try { $a = Get-NodeInput } catch { }
if ($a -is [string]) { $a = $(if ($a.Trim().StartsWith('{')) { $a | ConvertFrom-Json } else { $null }) }
$ci = [System.Globalization.CultureInfo]::InvariantCulture
$date = [string](Get-Prop $a 'auditDate'); if (-not $date) { $date = (Get-Date).ToString('yyyy-MM-dd', $ci) }
$niceDate = ([datetime]::ParseExact($date, 'yyyy-MM-dd', $ci)).ToString('d MMMM yyyy', $ci)
$totals = Get-Prop $a 'totals'; $cats = Get-Prop $totals 'categories'
$companies = @(Get-Prop $a 'companies' | Where-Object { $null -ne $_ })
$amOk = [string](Get-Prop $a 'accountManagerCheck') -eq 'ok'

# ---- styles (inline: most mail clients drop <style> blocks) ----
$font = "font-family:Segoe UI,Helvetica,Arial,sans-serif"
$ink = '#1f2328'; $muted = '#59636e'; $line = '#d1d9e0'; $red = '#b42318'; $amber = '#9a6700'; $green = '#1a7f37'
$th = "padding:8px 10px;border-bottom:2px solid $line;text-align:center;font-size:12px;color:$muted;font-weight:600"
$thL = $th -replace 'text-align:center', 'text-align:left'
$td = "padding:8px 10px;border-bottom:1px solid $line;text-align:center;font-size:14px"
$tdL = $td -replace 'text-align:center', 'text-align:left'
function Cell { param([int]$n, [string]$color = $ink) if ($n -eq 0) { "<td style='$td;color:#8c959f'>0</td>" } else { "<td style='$td;color:$color;font-weight:600'>$n</td>" } }
function Tile { param([int]$n, [string]$label, [string]$color) "<td style='padding:12px 14px;border:1px solid $line;border-radius:6px;text-align:center;width:16%'><div style='font-size:24px;font-weight:700;color:$(if ($n) { $color } else { '#8c959f' })'>$n</div><div style='font-size:12px;color:$muted'>$label</div></td>" }
function Badge { param([string]$tier) $c = $(if ($tier -eq 'Critical') { $red } else { $amber }); "<span style='display:inline-block;padding:1px 6px;border:1px solid $c;border-radius:10px;color:$c;font-size:11px;font-weight:600'>$tier</span>" }

$failed = $false
$b = New-Object System.Text.StringBuilder
function W { param([string]$s) $null = $b.Append($s) }
W "<html><body style='margin:0;padding:16px;background:#ffffff'><div style='$font;color:$ink;max-width:820px'>"
W "<h2 style='margin:0 0 4px;font-size:22px'>Weekly Fleet Audit</h2>"

if ($null -eq $totals -or -not $companies.Count) {
    # The runner carries on after a failed step, so say plainly that this week's audit didn't run.
    $why = [string](Get-Prop $a 'message')
    W "<p style='font-size:14px;color:$red'><strong>The audit didn't run this week.</strong> The Fleet Audit step failed or returned no data. Check this run's log in AutomationAI.</p>"
    if ($why) { W "<p style='font-size:13px;color:$muted'>$(Enc $why)</p>" }
    $critical = 0; $failed = $true
}
else {
    $n = Num (Get-Prop $totals 'computers'); $critical = Num (Get-Prop $totals 'critical')
    $replace = Num (Get-Prop $cats 'Replace'); $plan = Num (Get-Prop $cats 'Plan replacement')
    $wExp = Num (Get-Prop $totals 'warrantyExpired'); $wUnk = Num (Get-Prop $totals 'warrantyUnknown'); $noAm = Num (Get-Prop $totals 'noAccountManager')
    W "<div style='font-size:13px;color:$muted;margin-bottom:16px'>$niceDate &middot; $(Plural $companies.Count 'company' 'companies') &middot; $(Plural $n 'computer' 'computers') reviewed &middot; read-only</div>"

    # ---- headline numbers ----
    W "<table role='presentation' cellspacing='6' cellpadding='0' style='border-collapse:separate;width:100%;margin:0 -6px 8px'><tr>"
    W (Tile $critical 'Critical' $red); W (Tile $replace 'Replace' $red); W (Tile $plan 'Plan replacement' $amber)
    W (Tile $wExp 'Warranty expired' $amber); W (Tile $wUnk 'No warranty date' $amber)
    W $(if ($amOk) { Tile $noAm 'No account manager' $amber } else { "<td style='padding:12px 14px;border:1px solid $line;border-radius:6px;text-align:center;width:16%'><div style='font-size:24px;font-weight:700;color:#8c959f'>&ndash;</div><div style='font-size:12px;color:$muted'>Account manager not checked</div></td>" })
    W "</tr></table>"

    # ---- what to do first ----
    $todo = New-Object System.Collections.ArrayList
    foreach ($c in @($companies | Where-Object { (Num (Get-Prop $_ 'critical')) -gt 0 -or (Num (Get-Prop (Get-Prop $_ 'categories') 'Replace')) -gt 0 } | Select-Object -First 3)) {
        $cc = Num (Get-Prop $c 'critical'); $cr = Num (Get-Prop (Get-Prop $c 'categories') 'Replace')
        $parts = @(); if ($cc) { $parts += "$(Plural $cc 'critical computer' 'critical computers')" }; if ($cr) { $parts += "$cr due for replacement" }
        $null = $todo.Add("<strong>$(Enc (Get-Prop $c 'name'))</strong>: $($parts -join ', ').")
    }
    if ($amOk -and $noAm) {
        $who = @($companies | Where-Object { -not [string](Get-Prop $_ 'accountManager') } | ForEach-Object { Enc (Get-Prop $_ 'name') })
        $shown = ($who | Select-Object -First 5) -join ', '; if ($who.Count -gt 5) { $shown += " and $($who.Count - 5) more" }
        $null = $todo.Add("<strong>$(Plural $noAm 'company has' 'companies have') no account manager</strong>: $shown.")
    }
    if ($wUnk) { $null = $todo.Add("<strong>$(Plural $wUnk 'computer has' 'computers have') no warranty date.</strong> Run the ScalePad sync or add the dates, so warranty gaps show up here.") }
    if (-not $amOk) { $null = $todo.Add("Account managers could not be checked: the CloudRadial API did not return the field.") }
    $orph = Num (Get-Prop $totals 'orphanedEndpoints'); if ($orph) { $null = $todo.Add($(if ($orph -eq 1) { '1 endpoint belongs to a deleted company and was left out.' } else { "$orph endpoints belong to deleted companies and were left out." })) }
    if ($todo.Count) {
        W "<h3 style='margin:20px 0 8px;font-size:16px'>Start here</h3><ul style='margin:0;padding-left:20px;font-size:14px;line-height:1.6'>"
        foreach ($t in $todo) { W "<li>$t</li>" }
        W "</ul>"
    }
    else { W "<p style='font-size:14px;color:$green'><strong>Nothing needs attention this week.</strong></p>" }

    # ---- by company ----
    W "<h3 style='margin:24px 0 8px;font-size:16px'>By company</h3>"
    W "<table cellspacing='0' cellpadding='0' style='border-collapse:collapse;width:100%'><tr>"
    W "<th style='$thL'>Company</th><th style='$th'>Computers</th><th style='$th'>Critical</th><th style='$th'>Replace</th><th style='$th'>Plan replacement</th><th style='$th'>Windows 11 upgrade</th><th style='$th'>Needs data</th><th style='$th'>Warranty expired</th><th style='$th'>No warranty date</th><th style='$thL'>Account manager</th></tr>"
    foreach ($c in $companies) {
        $cc = Get-Prop $c 'categories'
        $amTxt = $(if (-not $amOk) { "<span style='color:#8c959f'>&ndash;</span>" } elseif ([string](Get-Prop $c 'accountManager')) { Enc (Get-Prop $c 'accountManager') } else { "<span style='color:$red;font-weight:600'>None</span>" })
        W "<tr><td style='$tdL;min-width:150px;font-weight:600'>$(Enc (Get-Prop $c 'name'))</td>$(Cell (Num (Get-Prop $c 'computers')))$(Cell (Num (Get-Prop $c 'critical')) $red)$(Cell (Num (Get-Prop $cc 'Replace')) $red)$(Cell (Num (Get-Prop $cc 'Plan replacement')) $amber)$(Cell (Num (Get-Prop $cc 'Upgrade in place')))$(Cell (Num (Get-Prop $cc 'Needs data')))$(Cell (Num (Get-Prop $c 'warrantyExpired')) $amber)$(Cell (Num (Get-Prop $c 'warrantyUnknown')))<td style='$tdL;white-space:nowrap'>$amTxt</td></tr>"
    }
    W "</table>"

    # ---- most urgent computers ----
    $withUrgent = @($companies | Where-Object { @(Get-Prop $_ 'urgent' | Where-Object { $null -ne $_ }).Count -gt 0 })
    if ($withUrgent.Count) {
        W "<h3 style='margin:24px 0 4px;font-size:16px'>Most urgent computers</h3><div style='font-size:13px;color:$muted;margin-bottom:8px'>Up to three per company. The Endpoint Hardware Refresh cards in Planner list every computer.</div>"
        foreach ($c in $withUrgent) {
            W "<div style='font-size:14px;font-weight:600;margin:12px 0 4px'>$(Enc (Get-Prop $c 'name'))</div><ul style='margin:0;padding-left:20px;font-size:13px;line-height:1.5'>"
            foreach ($u in @(Get-Prop $c 'urgent' | Where-Object { $null -ne $_ })) { W "<li style='margin-bottom:4px'>$(Badge ([string](Get-Prop $u 'tier'))) <span style='color:$muted'>$(Enc (Get-Prop $u 'category'))</span> &middot; $([string](Get-Prop $u 'line'))</li>" }
            $more = Num (Get-Prop $c 'moreFlagged'); if ($more -gt 0) { W "<li style='color:$muted;list-style:none'>+ $(Plural $more 'more flagged computer' 'more flagged computers')</li>" }
            W "</ul>"
        }
    }
}

W "<p style='margin-top:24px;padding-top:12px;border-top:1px solid $line;font-size:12px;color:$muted;line-height:1.5'>Computers are graded with the Endpoint LifeCycle Manager rules: <strong>Replace</strong> at 5 or more years old, on an unsupported operating system that can't take Windows 11, or under 4 GB of memory. <strong>Plan replacement</strong> at 3 or more years. <strong>Critical</strong> means 7 or more years old, Windows 10 or older, macOS 12 or older, or under 4 GB of memory. Servers and virtual machines are listed separately. This report is read-only: nothing in CloudRadial was changed.</p>"
W "</div></body></html>"

# One line, and nothing that would break the JSON string the Send Audit binding puts it in.
$body = $b.ToString() -replace '[\r\n\t]+', ' ' -replace '\\', '&#92;' -replace '"', '&quot;'
$subject = "Weekly Fleet Audit - $date$(if ($failed) { ' - audit failed' } elseif ($critical) { " - $critical critical" })"
Set-NodeOutput ([ordered]@{
    channel = 'email'
    subject = $subject
    body    = $body
    message = "Audit email ready ($([math]::Round($body.Length / 1024, 1)) KB)."
})
