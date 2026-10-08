# ---------- src/common.ps1: helpers shared by the Auto-Close Resolved steps ----------
# Paste after _shared/psa.ps1 and src/psa-extra.ps1. Every note this workflow writes ends with a marker:
#   [auto-close-resolved: <tag>, resolved since <yyyy-MM-ddTHH:mmZ>]
# Tags: "final notice" (sent to the client), "closed" (closing now), "failed".
# A later run reads the markers, so the final notice is never sent twice, and a failed close is retried
# without another notice.

$AcrMarkerPattern = '\[auto-close-resolved: (?<tag>[^,\]]+), resolved since (?<since>[^\]]+)\]'

function Format-AcrStamp { param($Value) $d = ConvertTo-PsaDate $Value; if ($null -eq $d) { return '' }; return $d.ToString('yyyy-MM-ddTHH:mmZ', [Globalization.CultureInfo]::InvariantCulture) }
function Format-AcrDay { param($Value) $d = ConvertTo-PsaDate $Value; if ($null -eq $d) { return '' }; return $d.ToString('dddd, MMMM d, yyyy', [Globalization.CultureInfo]::GetCultureInfo('en-US')) }
function Get-AcrMarker { param([string]$Tag, $Since) return "[auto-close-resolved: $Tag, resolved since $(Format-AcrStamp $Since)]" }
function Get-AcrPlural { param([int]$n, [string]$One, [string]$Many) if ($n -eq 1) { return "1 $One" }; return "$n $Many" }

function ConvertTo-AcrHash {
    param($o)
    if ($null -eq $o) { return @{} }
    if ($o -is [System.Collections.IDictionary]) { $h = @{}; foreach ($k in $o.Keys) { $h[[string]$k] = $o[$k] }; return $h }
    $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }; return $h
}

# Reads what the previous step handed on: @{ settings; found; truncated; plan; skipped; warnings }.
function Read-AcrState {
    $in = Get-NodeInput
    if ($in -is [string]) { $in = $in | ConvertFrom-Json }
    $s = Get-PsaProp $in 'settings'
    if ($null -eq $s) { throw 'This step needs the output of the step before it. Run the workflow from the start.' }
    $settings = ConvertTo-AcrHash $s
    $settings.preview = [bool]$settings.preview
    return @{
        settings  = $settings
        found     = [int](Get-PsaProp $in 'found')
        truncated = [bool](Get-PsaProp $in 'truncated')
        plan      = @(Get-PsaProp $in 'plan' | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-AcrHash $_ })
        skipped   = @(Get-PsaProp $in 'skipped' | Where-Object { $null -ne $_ } | ForEach-Object { ConvertTo-AcrHash $_ })
        warnings  = @(Get-PsaProp $in 'warnings' | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
    }
}
function Write-AcrState {
    param([hashtable]$State)
    Set-NodeOutput ([ordered]@{ settings = $State.settings; found = $State.found; truncated = $State.truncated; plan = @($State.plan); skipped = @($State.skipped); warnings = @($State.warnings) })
}

function Get-AcrTicketLabel { param($p) $l = "#$($p.number)"; if ($p.companyName) { $l += " ($($p.companyName))" }; return $l }

# The client-facing final notice.
function Get-AcrNoticeText {
    param($p)
    $subject = if ($p.summary) { " `"$($p.summary)`"" } else { '' }
    return @(
        'Hello,'
        ''
        "We marked ticket #$($p.number)$subject as resolved $($p.daysResolved) days ago and haven't heard back, so we're closing it now."
        ''
        "If the problem isn't fixed, or you need anything else, just reply to this message or contact us and we'll pick it up again."
        ''
        (Get-AcrMarker 'final notice' $p.since)
    ) -join "`n"
}
# ---------- end src/common.ps1 ----------
