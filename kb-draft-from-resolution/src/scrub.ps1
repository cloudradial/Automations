# ---------- src/scrub.ps1: take client and personal details out of text ----------
# Used before the AI sees the resolution and again on the AI's draft, so a knowledge base article never
# carries a client's name or domain, a person's name or address, a phone number, an IP address, a server
# path or a secret. Returns @{ text; removed (the kinds of detail taken out) }.
#   -Companies  the client company's name and its distinctive words
#   -People     the contact's and the technicians' names, whole and in parts
#   -Domains    the client's email domains
function Invoke-KbScrub {
    param([string]$Text, [string[]]$Companies = @(), [string[]]$People = @(), [string[]]$Domains = @())
    $state = @{ t = [string]$Text; removed = (New-Object System.Collections.ArrayList) }
    $sub = {
        param([string]$Pattern, [string]$With, [string]$Kind)
        if ([regex]::IsMatch($state.t, $Pattern)) {
            $state.t = [regex]::Replace($state.t, $Pattern, $With)
            if (-not $state.removed.Contains($Kind)) { $null = $state.removed.Add($Kind) }
        }
    }
    # Secrets first: the value after "password:", "pwd=", "PIN is", "API key" and the like, and product keys.
    & $sub '(?i)\b(pass(?:word|wd|code|phrase)?|pwd|pin|secret|api[ -]?key|token|recovery code|license key|product key)(\s*(?:is|was|:|=|-)\s*)\S+' '$1$2[removed]' 'a password or key'
    & $sub '\b[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}\b' '[removed]' 'a password or key'
    # People, places and addresses.
    & $sub '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b' 'the user''s email address' 'an email address'
    # A full stop may end the sentence after a number; a dot followed by a digit means a version, not a phone or IP.
    & $sub '(?<![\d.])(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{2,4}\)|\d{2,4})[\s.-]\d{3,4}[\s.-]\d{3,4}(?!\d|\.\d)' 'the phone number' 'a phone number'
    & $sub '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?!\d|\.\d)' 'the IP address' 'an IP address'
    & $sub '\\\\[A-Za-z0-9._-]+(?:\\[^\s]*)?' '\\server\share' 'a server path'
    foreach ($d in @($Domains | Where-Object { $_ -and $_.Length -ge 4 })) { & $sub ('(?i)\b[\w.-]*' + [regex]::Escape($d) + '\b') 'the company domain' 'a company domain' }
    # A whole name (two or more words) matches in any case; a single word only as written, capitalized, so the
    # name Will or Mark never removes the words will and mark.
    $case = { param([string]$n) if ($n -match '\s') { '(?i)' } else { '' } }
    foreach ($n in @($Companies | Where-Object { $_ } | Sort-Object -Property Length -Descending)) { & $sub ((& $case $n) + '\b' + [regex]::Escape($n) + '\b') 'the company' 'a company name' }
    foreach ($n in @($People | Where-Object { $_ } | Sort-Object -Property Length -Descending)) { & $sub ((& $case $n) + '\b' + [regex]::Escape($n) + '\b') 'the user' 'a name' }
    return @{ text = $state.t; removed = @($state.removed) }
}
# The names on a ticket worth removing. Common company words (Ltd, Group, Services...) and anything under
# three letters are skipped, so "Al" doesn't eat "Alert".
function Get-KbNames {
    param([string]$Company, [string[]]$People = @())
    $c = New-Object System.Collections.ArrayList; $p = New-Object System.Collections.ArrayList
    $add = { param($List, [string]$s) $s = ([string]$s).Trim(); if ($s.Length -ge 3 -and -not $List.Contains($s)) { $null = $List.Add($s) } }
    & $add $c $Company
    foreach ($w in @(([string]$Company) -split '[\s,]+' | Where-Object { $_.Length -ge 4 -and $_ -notmatch '^(?i)(ltd|inc|llc|corp|group|company|limited|services|solutions|technologies|systems|the|and)\.?$' })) { & $add $c $w }
    foreach ($n in @($People)) { & $add $p $n; foreach ($w in @(([string]$n) -split '[\s,.]+' | Where-Object { $_.Length -ge 3 })) { & $add $p $w } }
    return @{ companies = @($c); people = @($p) }
}
# ---------- end src/scrub.ps1 ----------
