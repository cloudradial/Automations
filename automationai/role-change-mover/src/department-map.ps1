# ---------- department map: read the KB article and check its rows ----------
# The map is a CSV pasted into a CloudRadial KB article:
#   department,group,kind,license_sku
# group is a display name or an object id; kind is security, distribution or m365;
# license_sku (optional) is a SKU part number such as SPE_E3, or a SKU id.
# A row may name only a licence (group and kind left blank).

# Turns a KB article body into plain text lines. Handles text pasted as paragraphs,
# line breaks, a code block, or an HTML table.
function ConvertFrom-RcArticleBody {
    param([string]$Html)
    $t = $Html -replace '\r', ''
    $t = $t -replace '(?i)<br\s*/?>', "`n"
    $t = $t -replace '(?i)</(p|div|tr|li|h[1-6]|pre)>', "`n"
    # Table cells become quoted CSV fields so commas inside a cell survive.
    $t = $t -replace '(?is)<t[dh][^>]*>(.*?)</t[dh]>', '"$1",'
    $t = $t -replace '<[^>]+>', ''
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t -replace [char]0x00A0, ' ' -replace [char]0xFEFF, ''
    # Smart quotes from the editor break CSV quoting.
    $t = $t -replace "[$([char]0x201C)$([char]0x201D)]", '"' -replace "[$([char]0x2018)$([char]0x2019)]", "'"
    $t = $t -replace '(?m)",\s*$', '"'
    return @($t -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# The kinds the map accepts, and the words people tend to write for them.
function ConvertTo-RcKind {
    param([string]$Value)
    $v = ([string]$Value).Trim().ToLowerInvariant() -replace '[\s_]+', ' '
    if ($v -eq '') { return '' }
    switch -Regex ($v) {
        '^(security|security group|sg)$' { return 'security' }
        '^(distribution|distribution list|distribution group|dl)$' { return 'distribution' }
        '^(m365|microsoft 365|microsoft 365 group|m365 group|o365|office 365|unified)$' { return 'm365' }
        '^(mail enabled security|mail-enabled security|mesg)$' { return 'mail-enabled security' }
    }
    return $null
}

# Reads the map. Returns @{ Rows = @(@{ line; department; group; kind; license }); Errors = @(); Warnings = @() }.
function Read-RcDepartmentMap {
    param([string[]]$Lines)
    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $rows = New-Object System.Collections.ArrayList
    # The table starts at its header row; titles and notes above it are ignored.
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^\s*"?department"?\s*,') { $start = $i; break } }
    if ($start -lt 0) {
        $null = $errors.Add('The department map has no header row. The first line of the table must be: department,group,kind,license_sku')
        return @{ Rows = @(); Errors = @($errors); Warnings = @($warnings) }
    }
    $body = @($Lines | Select-Object -Skip $start)
    $parsed = @($body | ConvertFrom-Csv)
    $cols = @(); if ($parsed.Count) { $cols = @($parsed[0].PSObject.Properties | ForEach-Object { ([string]$_.Name).Trim().ToLowerInvariant() }) }
    foreach ($need in @('department', 'group', 'kind')) { if ($parsed.Count -and $cols -notcontains $need) { $null = $errors.Add("The department map has no '$need' column. The header must be: department,group,kind,license_sku") } }
    if ($errors.Count) { return @{ Rows = @(); Errors = @($errors); Warnings = @($warnings) } }
    $n = $start + 1
    foreach ($r in $parsed) {
        $n++
        $get = @{}
        foreach ($p in $r.PSObject.Properties) { $get[([string]$p.Name).Trim().ToLowerInvariant()] = ([string]$p.Value).Trim() }
        foreach ($k in @('department', 'group', 'kind', 'license_sku')) { if (-not $get.ContainsKey($k)) { $get[$k] = '' } }
        if (-not $get.department -and -not $get.group -and -not $get.license_sku) { continue }
        if (-not $get.department) { $null = $errors.Add("Row $($n): no department."); continue }
        if (-not $get.group -and -not $get.license_sku) { $null = $errors.Add("Row $($n) ($($get.department)): give a group, a license_sku, or both."); continue }
        $kind = ConvertTo-RcKind $get.kind
        if ($null -eq $kind) { $null = $errors.Add("Row $($n) ($($get.department), $($get.group)): kind '$($get.kind)' isn't one of security, distribution or m365."); continue }
        if ($get.group -and -not $kind) { $null = $warnings.Add("Row $($n) ($($get.department), $($get.group)) has no kind, so the kind Microsoft 365 reports is used.") }
        $null = $rows.Add(@{ line = $n; department = $get.department; group = $get.group; kind = $kind; license = $get.license_sku })
    }
    if (-not $rows.Count -and -not $errors.Count) { $null = $errors.Add('The department map has a header but no rows.') }
    return @{ Rows = @($rows); Errors = @($errors); Warnings = @($warnings) }
}

# The rows for one department (case and spacing don't matter).
function Select-RcDepartment {
    param($Rows, [string]$Department)
    $want = (([string]$Department).Trim() -replace '\s+', ' ').ToLowerInvariant()
    return @(@($Rows) | Where-Object { $null -ne $_ -and ((([string]$_.department).Trim() -replace '\s+', ' ').ToLowerInvariant()) -eq $want })
}
