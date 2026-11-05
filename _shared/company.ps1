# ---------- _shared/company.ps1: run as the client the run input names ----------
# Edit this file, then run: node _shared/inject.js <automation-folder>
# A step's Company setting picks whose secrets the step reads: the client's Microsoft 365 tenant AND its
# CloudRadial portal. A pinned Company serves one client only, and import strips it. With the step's
# "Include all companies" on (includeAllCompanies: true, which import keeps), the runner loads every
# AutomationAI company into $companies, and Set-DefaultCompany switches the step's secrets to one of them.
#   $co = Select-RunCompany (Get-Prop $in 'company')
# A blank name keeps the step's own Company (or the runner's shared secrets), so a Routine with no input
# still works. A name is matched to exactly one AutomationAI company by external id, then by name or alias
# (case doesn't matter). No match, or more than one, throws, so a run never uses the wrong client's secrets.
# Each step is its own script: call it in every step that reads a client secret.
# Returns @{ selected; externalId; name; how }.

function Get-CompanyField {
    param($Company, [string]$Name)
    if ($null -eq $Company) { return $null }
    if ($Company -is [System.Collections.IDictionary]) { if ($Company.Contains($Name)) { return $Company[$Name] }; return $null }
    $p = $Company.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Select-RunCompany {
    param([string]$Name)
    $want = ([string]$Name).Trim()
    if (-not $want) { return @{ selected = $false; externalId = ''; name = ''; how = "the step's own Company setting" } }
    $all = Get-Variable -Name companies -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $all) { throw "The run names the company '$want', but this step can't switch companies. Turn on Include all companies in the step's Company settings." }
    if (-not (Get-Command Set-DefaultCompany -ErrorAction SilentlyContinue)) { throw "The run names the company '$want', but this runner has no Set-DefaultCompany command." }
    $key = $want.ToLowerInvariant()
    $same = { param($v) $null -ne $v -and ([string]$v).Trim().ToLowerInvariant() -eq $key }
    $list = @($all)
    $hits = @($list | Where-Object { & $same (Get-CompanyField $_ 'externalId') })
    if ($hits.Count -eq 0) {
        $hits = @($list | Where-Object {
            $c = $_
            (& $same (Get-CompanyField $c 'name')) -or (@(@(Get-CompanyField $c 'aliases') | Where-Object { & $same $_ }).Count -gt 0)
        })
    }
    if ($hits.Count -eq 0) { throw "No AutomationAI company matches '$want'. Add the client under Companies with its Microsoft 365 and CloudRadial secrets, or use its exact name or external id." }
    if ($hits.Count -gt 1) {
        $names = @($hits | ForEach-Object { "$(Get-CompanyField $_ 'name') ($(Get-CompanyField $_ 'externalId'))" }) -join ', '
        throw "'$want' matches $($hits.Count) AutomationAI companies: $names. Use the external id instead."
    }
    $m = $hits[0]
    $id = [string](Get-CompanyField $m 'externalId')
    Set-DefaultCompany -Company $id
    return @{ selected = $true; externalId = $id; name = [string](Get-CompanyField $m 'name'); how = "the run's company input" }
}
