# Strict-mode harness for the Offline Device Sweep.
# Runs each PowerShell step exactly as it is in offline-device-sweep.yml (shared libraries included), through
# & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault, Invoke-RestMethod,
# Start-Sleep, Get-NodeInput and Set-NodeOutput mocked (_shared/tests/mock.ps1).
# Placeholder data only (Contoso, Fabrikam, Northwind, Example MSP).
# Test variables start with T: a step runs in a child scope of this script, and a step variable of the
# same name would hide a test variable from the mocks (PowerShell names ignore case).
# Usage: pwsh -NoProfile -File offline-device-sweep/src/test.ps1
#        (needs node and js-yaml: JS_YAML_PATH, NODE_PATH, or npm install in _shared)
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\offline-device-sweep.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.type==='powershell-script'){o[a.id]=a.properties.script;o[a.id+'.params']=JSON.stringify(a.properties.parameters);o[a.id+'.test']=a.properties.testInput||''}}console.log(JSON.stringify(o));"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'workflow has the find, wake and ticket steps' ($Steps.Contains('node-find') -and $Steps.Contains('node-wake') -and $Steps.Contains('node-ticket'))
Check 'every step is unbound (Get-NodeInput)' ($Steps['node-find.params'] -eq '[]' -and $Steps['node-wake.params'] -eq '[]' -and $Steps['node-ticket.params'] -eq '[]')
Check 'first step Test Input is a preview' (($Steps['node-find.test'] | ConvertFrom-Json).preview -eq $true)

# ---- runner mocks ----
$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-Step {
    param([string]$Id, $In = $null)
    $global:NodeIn = $In; $global:NodeOut = $null
    $err = ''
    try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps[$Id])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 14 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}
# find -> wake -> ticket, each fed the one before's output, the way the runner chains unbound steps.
function Invoke-Flow {
    param($Body = $null)
    $f = Invoke-Step 'node-find' $(if ($null -ne $Body) { ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json) } else { $null })
    if ($f.error) { return @{ stage = 'find'; r = $f; find = $f.out; wake = $null } }
    $w = Invoke-Step 'node-wake' $f.out
    if ($w.error) { return @{ stage = 'wake'; r = $w; find = $f.out; wake = $w.out } }
    $t = Invoke-Step 'node-ticket' $w.out
    return @{ stage = 'ticket'; r = $t; find = $f.out; wake = $w.out }
}

# ---- placeholder data ----
$TDA = 'https://platform-api.example.net'
$TCW = 'https://api-na.example.com/v4_6_release/apis/3.0'; $TAT = 'https://webservices5.autotask.example/atservicesrest/v1.0'; $TZD = 'https://example.zendesk.com/api/v2'
$TDatto = @{ 'Datto-ApiUrl' = "$TDA/api/"; 'Datto-ApiKey' = 'dk-placeholder'; 'Datto-ApiSecret' = 'ds-placeholder' }
$TPsa = @{
    connectwise = @{ 'PSA-Type' = 'connectwise'; 'CW-ApiUrl' = $TCW; 'CW-CompanyID' = 'examplemsp'; 'CW-PublicKey' = 'pub'; 'CW-PrivateKey' = 'priv'; 'CW-ClientId' = 'cid' }
    autotask    = @{ 'PSA-Type' = 'autotask'; 'Autotask-ApiUrl' = 'https://webservices5.autotask.example'; 'Autotask-ApiIntegrationCode' = 'code'; 'Autotask-Username' = 'api@example.com'; 'Autotask-Secret' = 'sec' }
    zendesk     = @{ 'PSA-Type' = 'zendesk'; 'Zendesk-BaseUrl' = 'https://example.zendesk.com'; 'Zendesk-Email' = 'agent@example.com'; 'Zendesk-ApiToken' = 'tok' }
}
function Get-TSecrets { param([string]$P, [switch]$NoDatto) $s = @{}; foreach ($k in $TPsa[$P].Keys) { $s[$k] = $TPsa[$P][$k] }; if (-not $NoDatto) { foreach ($k in $TDatto.Keys) { $s[$k] = $TDatto[$k] } }; return $s }
function TMs { param([double]$HoursAgo) return [DateTimeOffset]::UtcNow.AddHours(-$HoursAgo).ToUnixTimeMilliseconds() }
function TJ { param($h) return ($h | ConvertTo-Json -Depth 10 | ConvertFrom-Json) }
# On a second read of a site (after the wake-ups), the hostnames in $TS.wakeBack are online.
function TAfterWake { param($List, [int]$N) if ($N -lt 2 -or -not @($TS.wakeBack).Count) { return @($List) }; return @(@($List) | ForEach-Object { $c = @{} + $_; if ($TS.wakeBack -contains $c.hostname) { $c.online = $true }; $c }) }
function TDev { param([string]$HostName, [string]$Cat, $Online, $LastSeen, [string]$Os = 'Windows 11 Pro', [switch]$Suspended, [switch]$Deleted) return @{ uid = "uid-$HostName"; hostname = $HostName; deviceType = @{ category = $Cat; type = $Cat }; deviceClass = 'device'; online = $Online; lastSeen = $LastSeen; operatingSystem = $Os; suspended = [bool]$Suspended; deleted = [bool]$Deleted } }
$TToday = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$TCompanies = @{ connectwise = @{ 'Contoso' = 42; 'Fabrikam' = 43 }; autotask = @{ 'Contoso' = 42; 'Fabrikam' = 43 }; zendesk = @{ 'Contoso' = 77; 'Fabrikam' = 78 } }

$TS = @{}
function Reset-Scenario {
    $TS.tokenFail = 0; $TS.token429 = 0; $TS.fab429 = 0; $TS.retryAfter = ''; $TS.foreignNext = $false
    $TS.cwOpen = @(); $TS.cwNotes = @{}; $TS.atOpen = @(); $TS.atNotes = @(); $TS.zdOpen = @(); $TS.zdComments = @(); $TS.nextId = 5001
    # Wake-on-LAN: audit network cards, the account's components, the quick job, and who is back online on the re-read.
    $TS.nics = @{ 'uid-CONTOSO-PC01' = @(@{ instance = 'Ethernet'; macAddress = '00-11-22-AA-BB-01'; ipv4 = '10.0.1.21' })
        'uid-CONTOSO-PC03' = @(@{ instance = 'Ethernet'; macAddress = '00:11:22:aa:bb:03'; ipv4 = '10.0.1.23' }, @{ instance = 'Wi-Fi'; macAddress = '00:11:22:aa:cc:03'; ipv4 = '169.254.3.3' })
        'uid-FABRIKAM-PC01' = @(@{ instance = 'Ethernet'; macAddress = '00-11-22-FA-00-01'; ipv4 = '10.9.0.11' })
        'uid-FABRIKAM-PC02' = @(@{ instance = 'Ethernet'; macAddress = '00-11-22-FA-00-02'; ipv4 = '10.9.0.12' }) }
    $TS.components = @(@{ uid = 'comp-other'; name = 'Disk Cleanup' }, @{ uid = 'comp-wol'; name = 'Wake-on-LAN' })
    $TS.wakeBack = @(); $TS.jobFail = 0; $TS.jobStatus = 'Success'
    $TS.sites1 = @(@{ uid = 's-contoso'; name = 'Contoso' }, @{ uid = 's-deleted'; name = 'Deleted Devices' }, @{ uid = 's-north'; name = 'Northwind Traders' })
    $TS.sites2 = @(@{ uid = 's-fab'; name = 'Fabrikam' }, @{ uid = 's-lab'; name = 'Contoso Lab' }, @{ uid = 's-managed'; name = 'Managed' })
    $TS.contoso1 = @(
        (TDev 'CONTOSO-PC01' 'Desktop' $false (TMs 240)),                         # 10 days: offline workstation
        (TDev 'CONTOSO-LT02' 'Laptop' $false (TMs 72)),                           # 3 days: under 7, not ticketed
        (TDev 'CONTOSO-SRV01' 'Server' $false (TMs 6) 'Windows Server 2022'),     # 6 hours: offline server
        (TDev 'CONTOSO-SRV02' 'Server' $false (TMs 2) 'Windows Server 2022'),     # 2 hours: under 4, not ticketed
        (TDev 'CONTOSO-PC03' 'Desktop' $true (TMs 0.1)))                          # online
    $TS.contoso2 = @(
        (TDev 'CONTOSO-PC04' 'Desktop' $false (TMs 960) -Suspended),              # suspended: skipped
        (TDev 'CONTOSO-PC05' 'Desktop' $false (TMs 2880) -Deleted),               # deleted: skipped
        (TDev 'CONTOSO-PRN01' 'Printer' $false (TMs 720) 'Printer'),              # printers aren't included by default
        (TDev 'CONTOSO-LT06' 'Laptop' $false ([DateTime]::UtcNow.AddDays(-100).ToString('yyyy-MM-ddTHH:mm:ssZ'))))  # ISO lastSeen, 100 days
    $TS.devices = @{
        's-north' = @((TDev 'NORTHWIND-PC01' 'Desktop' $false (TMs 216)))
        's-fab'   = @((TDev 'FABRIKAM-PC01' 'Desktop' $true (TMs 0.2)))
        's-lab'   = @((TDev 'CONTOSO-LAB01' 'Desktop' $false (TMs 480)))
    }
}

$Handler = {
    param($c, $n)
    $k = "$($c.Method) $($c.Uri)"
    $u = [uri]::UnescapeDataString([string]$c.Uri)
    switch -Wildcard -CaseSensitive ($k) {
        # ---- Datto RMM ----
        "POST $TDA/auth/oauth/token" {
            if ($TS.tokenFail) { New-HttpError $TS.tokenFail '{"error":"unauthorized","error_description":"Bad credentials"}' }
            if ($TS.token429 -and $n -le $TS.token429) { New-HttpError 429 '' }
            return [pscustomobject]@{ access_token = 'tok-placeholder'; token_type = 'bearer'; expires_in = 359999 }
        }
        "GET $TDA/api/v2/account/sites?max=250" {
            $nx = $(if ($TS.foreignNext) { 'https://elsewhere.example.org/api/v2/account/sites?max=250&page=2' } else { "$TDA/api/v2/account/sites?max=250&page=2" })
            return (TJ @{ pageDetails = @{ count = 3; prevPageUrl = $null; nextPageUrl = $nx }; sites = $TS.sites1 })
        }
        "GET $TDA/api/v2/account/sites?max=250&page=2" { return (TJ @{ pageDetails = @{ count = 3; prevPageUrl = "$TDA/api/v2/account/sites?max=250"; nextPageUrl = $null }; sites = $TS.sites2 }) }
        "GET $TDA/api/v2/site/s-contoso/devices?max=250" { return (TJ @{ pageDetails = @{ nextPageUrl = "$TDA/api/v2/site/s-contoso/devices?max=250&page=2" }; devices = @(TAfterWake $TS.contoso1 $n) }) }
        "GET $TDA/api/v2/site/s-contoso/devices?max=250&page=2" { return (TJ @{ pageDetails = @{ nextPageUrl = $null }; devices = $TS.contoso2 }) }
        "GET $TDA/api/v2/site/*/devices?max=250" {
            $uid = ([regex]::Match($c.Uri, '/site/([^/]+)/devices')).Groups[1].Value
            if ($uid -eq 's-fab' -and $TS.fab429 -and $n -le $TS.fab429) { New-HttpError 429 '' $TS.retryAfter }
            if (-not $TS.devices.Contains($uid)) { throw "Unexpected Datto device read for $uid" }
            return (TJ @{ pageDetails = @{ nextPageUrl = $null }; devices = @(TAfterWake $TS.devices[$uid] $n) })
        }
        "GET $TDA/api/v2/audit/device/*" {
            $uid = ([regex]::Match($u, '/audit/device/(.+)$')).Groups[1].Value
            return (TJ @{ nics = @($(if ($TS.nics.Contains($uid)) { $TS.nics[$uid] } else { @() })) })
        }
        "GET $TDA/api/v2/account/components?max=250" { return (TJ @{ pageDetails = @{ nextPageUrl = $null }; components = @($TS.components) }) }
        "PUT $TDA/api/v2/device/*/quickjob" {
            if ($TS.jobFail) { New-HttpError $TS.jobFail '{"message":"Access denied"}' }
            $uid = ([regex]::Match($u, '/device/([^/]+)/quickjob')).Groups[1].Value
            return (TJ @{ job = @{ uid = "job-$uid"; status = 'active' } })
        }
        "GET $TDA/api/v2/job/*/results/*" { return (TJ @{ jobUid = 'job'; deviceUid = 'dev'; jobDeploymentStatus = $TS.jobStatus }) }
        # ---- ConnectWise ----
        "GET $TCW/company/companies?*" {
            $m = [regex]::Match($u, 'name(?: contains)?\s*=?\s*"(?<n>[^"]+)"'); $exact = $u -notmatch 'name contains'
            $rows = @(foreach ($nm in $TCompanies.connectwise.Keys) { if (($exact -and $nm -eq $m.Groups['n'].Value) -or (-not $exact -and $nm.Contains($m.Groups['n'].Value))) { [pscustomobject]@{ id = $TCompanies.connectwise[$nm]; name = $nm } } })
            return , @($rows)
        }
        "GET $TCW/service/tickets/*/notes*" {
            $tid = ([regex]::Match($c.Uri, '/tickets/(\d+)/notes')).Groups[1].Value
            if ($u -match 'page=([2-9])') { return , @() }
            return , @($(if ($TS.cwNotes.Contains($tid)) { @($TS.cwNotes[$tid]) } else { @() }))
        }
        "GET $TCW/service/tickets?*" { if ($u -match '&page=([2-9])') { return , @() }; return , @($TS.cwOpen | ForEach-Object { TJ $_ }) }
        "GET $TCW/service/priorities*" { return , @([pscustomobject]@{ id = 1; name = 'Priority 1 - Critical' }, [pscustomobject]@{ id = 2; name = 'Priority 2 - High' }, [pscustomobject]@{ id = 3; name = 'Priority 3 - Medium' }, [pscustomobject]@{ id = 4; name = 'Priority 4 - Low' }) }
        "POST $TCW/service/tickets" { $id = $TS.nextId; $TS.nextId++; return [pscustomobject]@{ id = $id } }
        "POST $TCW/service/tickets/*/notes" {
            $tid = ([regex]::Match($c.Uri, '/tickets/(\d+)/notes')).Groups[1].Value
            $b = Read-Body $c
            $have = @(); if ($TS.cwNotes.Contains($tid)) { $have = @($TS.cwNotes[$tid]) }
            $TS.cwNotes[$tid] = @($have) + @([pscustomobject]@{ id = 9000 + $have.Count; text = $b.text; internalAnalysisFlag = $b.internalAnalysisFlag; detailDescriptionFlag = $b.detailDescriptionFlag; resolutionFlag = $false; dateCreated = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ') })
            return [pscustomobject]@{ id = 9000 + $have.Count }
        }
        # ---- Autotask ----
        "GET $TAT/Companies/query?search=*" {
            $q = ($u -replace '^.*search=', '') | ConvertFrom-Json
            $want = [string]$q.filter[0].value; $op = [string]$q.filter[0].op
            $rows = @(foreach ($nm in $TCompanies.autotask.Keys) { if (($op -eq 'eq' -and $nm -eq $want) -or ($op -eq 'contains' -and $nm.Contains($want))) { [pscustomobject]@{ id = $TCompanies.autotask[$nm]; companyName = $nm } } })
            return [pscustomobject]@{ items = @($rows); pageDetails = [pscustomobject]@{ nextPageUrl = $null } }
        }
        "GET $TAT/Tickets/entityInformation/fields" { return (TJ @{ fields = @(
                        @{ name = 'status'; picklistValues = @(@{ value = '1'; label = 'New'; isActive = $true }, @{ value = '5'; label = 'Complete'; isActive = $true }) },
                        @{ name = 'priority'; picklistValues = @(@{ value = '4'; label = 'Critical'; isActive = $true }, @{ value = '1'; label = 'High'; isActive = $true }, @{ value = '2'; label = 'Medium'; isActive = $true; isDefaultValue = $true }, @{ value = '3'; label = 'Low'; isActive = $true }) },
                        @{ name = 'queueID'; picklistValues = @(@{ value = '29683'; label = 'Monitoring Alert'; isActive = $true }) },
                        @{ name = 'ticketType'; picklistValues = @(@{ value = '1'; label = 'Service Request'; isActive = $true }) }) }) }
        "GET $TAT/Tickets/query?search=*" { return [pscustomobject]@{ items = @($TS.atOpen | ForEach-Object { TJ $_ }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "GET $TAT/TicketNotes/entityInformation/fields" { return (TJ @{ fields = @(
                        @{ name = 'publish'; picklistValues = @(@{ value = '1'; label = 'All Autotask Users'; isActive = $true }, @{ value = '2'; label = 'Internal Only'; isActive = $true }) },
                        @{ name = 'noteType'; picklistValues = @(@{ value = '13'; label = 'System Workflow Note'; isActive = $true }, @{ value = '1'; label = 'Task Detail'; isActive = $true }) }) }) }
        "GET $TAT/TicketNotes/query*" { return [pscustomobject]@{ items = @($TS.atNotes | ForEach-Object { TJ $_ }); pageDetails = [pscustomobject]@{ nextPageUrl = $null } } }
        "POST $TAT/Tickets" { return [pscustomobject]@{ itemId = 6001 } }
        "POST $TAT/Tickets/*/Notes" { return [pscustomobject]@{ itemId = 3001 } }
        # ---- Zendesk ----
        "GET $TZD/organizations/autocomplete?name=*" {
            $want = $u -replace '^.*name=', ''
            $rows = @(foreach ($nm in $TCompanies.zendesk.Keys) { if ($nm.StartsWith($want)) { [pscustomobject]@{ id = $TCompanies.zendesk[$nm]; name = $nm } } })
            return [pscustomobject]@{ organizations = @($rows) }
        }
        "GET $TZD/search?query=*" { return [pscustomobject]@{ results = @($TS.zdOpen | ForEach-Object { TJ $_ }); next_page = $null } }
        "GET $TZD/tickets/*/comments*" { return [pscustomobject]@{ comments = @($TS.zdComments | ForEach-Object { TJ $_ }); next_page = $null } }
        "POST $TZD/tickets" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 8001 } } }
        "PUT $TZD/tickets/*" { return [pscustomobject]@{ ticket = [pscustomobject]@{ id = 8100 } } }
    }
    throw "Unexpected call in test: $k"
}
function Get-WriteCalls { return @($Mock.Calls | Where-Object { $_.Method -ne 'GET' -and $_.Uri -notlike "$TDA/auth/*" }) }
function Get-Plan { param($Find, [string]$Company) return @(@($Find.plan) | Where-Object { $_.companyName -eq $Company }) | Select-Object -First 1 }
function Get-Row { param($Out, [string]$Company) return @(@($Out.companies) | Where-Object { $_.company -eq $Company }) | Select-Object -First 1 }

# ---- 1. ConnectWise preview: token, paging, thresholds, skips, unmatched site, nothing written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ preview = $true }
$o = $f.r.out; $fo = $f.find
Check 'preview: both steps ran' ($f.stage -eq 'ticket' -and -not $f.r.error) "$($f.stage) $($f.r.error)"
$tok = @(Get-Calls 'POST' "$TDA/auth/oauth/token")
Check 'token: one POST to /auth/oauth/token on the API URL (trailing /api/ stripped)' ($tok.Count -eq 1) (Show-Calls)
Check 'token: Basic auth with the public-client OAuth client' ($tok[0].Headers['Authorization'] -eq ('Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))))
Check 'token: password grant with the API key and secret' ($tok[0].Body -eq 'grant_type=password&username=dk-placeholder&password=ds-placeholder' -and $tok[0].ContentType -eq 'application/x-www-form-urlencoded') $tok[0].Body
Check 'reads send the Bearer token' (@($Mock.Calls | Where-Object { $_.Uri -like "$TDA/api/*" -and $_.Headers['Authorization'] -ne 'Bearer tok-placeholder' }).Count -eq 0)
Check 'paging: sites page 2 read through nextPageUrl' (@(Get-Calls 'GET' "$TDA/api/v2/account/sites?max=250&page=2").Count -eq 1)
Check 'paging: devices page 2 read through nextPageUrl' (@(Get-Calls 'GET' "$TDA/api/v2/site/s-contoso/devices?max=250&page=2").Count -eq 1)
Check 'placeholder sites (Deleted Devices, Managed) not read' (@(Get-Calls 'GET' "$TDA/api/v2/site/s-deleted/*").Count -eq 0 -and @(Get-Calls 'GET' "$TDA/api/v2/site/s-managed/*").Count -eq 0)
Check 'Datto is only read' (@($Mock.Calls | Where-Object { $_.Uri -like "$TDA/api/*" -and $_.Method -ne 'GET' }).Count -eq 0)
$TP = Get-Plan $fo 'Contoso'
$THosts = @($TP.devices | ForEach-Object { $_.hostname })
Check 'threshold: workstation 10 days offline is ticketed, laptop 3 days is not' ($THosts -contains 'CONTOSO-PC01' -and $THosts -notcontains 'CONTOSO-LT02') ($THosts -join ',')
Check 'servers by hours: 6 hours is ticketed, 2 hours is not' ($THosts -contains 'CONTOSO-SRV01' -and $THosts -notcontains 'CONTOSO-SRV02') ($THosts -join ',')
Check 'suspended and deleted devices skipped' ($THosts -notcontains 'CONTOSO-PC04' -and $THosts -notcontains 'CONTOSO-PC05' -and $fo.counts.suspendedOrDeleted -eq 2)
Check 'printers skipped by default; online device skipped' ($THosts -notcontains 'CONTOSO-PRN01' -and $THosts -notcontains 'CONTOSO-PC03')
Check 'ISO lastSeen read too (CONTOSO-LT06, 100 days)' ($THosts -contains 'CONTOSO-LT06')
Check 'servers listed first' ($THosts[0] -eq 'CONTOSO-SRV01') ($THosts -join ',')
Check 'unmatched site: Northwind in unmatchedSites and warned, never ticketed' (@($o.unmatchedSites | Where-Object { $_.site -eq 'Northwind Traders' -and $_.offline -eq 1 }).Count -eq 1 -and @($o.warnings | Where-Object { $_ -like "*'Northwind Traders' has 1 offline device but no ticket was opened*companyMap*" }).Count -eq 1 -and $null -eq (Get-Row $o 'Northwind Traders')) (@($o.warnings) -join ' | ')
Check 'Contoso Lab has no exact company match, so it is unmatched (not added to Contoso)' ($THosts -notcontains 'CONTOSO-LAB01' -and @($o.unmatchedSites | Where-Object { $_.site -eq 'Contoso Lab' }).Count -eq 1)
Check 'preview: status pending_confirmation' ($o.status -eq 'pending_confirmation' -and $o.preview -eq $true) "$($o.status) $($o.message)"
Check 'preview: nothing written to the PSA' (@(Get-WriteCalls).Count -eq 0) (Show-Calls)
$TRow = Get-Row $o 'Contoso'
Check 'preview: Contoso would get a ticket listing 3 devices' ($TRow.action -eq 'would create' -and $TRow.offline -eq 3 -and $TRow.servers -eq 1 -and $o.counts.wouldCreate -eq 1 -and $o.counts.ticketsCreated -eq 0) ($TRow | ConvertTo-Json -Depth 4)
Check 'preview: summary and body returned' ($TRow.summary -eq 'Offline devices: 3 not seen recently, including 1 server' -and $TRow.text -like '*Servers first*CONTOSO-SRV01*') $TRow.summary
Check 'counts: sites, devicesChecked, offline, unmatchedSites' ($o.counts.sites -eq 4 -and $o.counts.devicesChecked -eq 9 -and $o.counts.offline -eq 5 -and $o.counts.unmatchedSites -eq 2) ($o.counts | ConvertTo-Json -Compress)
Check 'no em dashes or secrets in the output' ((($o | ConvertTo-Json -Depth 10) -notmatch [char]0x2014) -and (($o | ConvertTo-Json -Depth 10) -notlike '*ds-placeholder*') -and (($o | ConvertTo-Json -Depth 10) -notlike '*tok-placeholder*'))

# ---- 2. ConnectWise live: one new ticket, servers at the higher priority, marker note ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab, Northwind Traders' }
$o = $f.r.out
$TNew = @(Get-Calls 'POST' "$TCW/service/tickets")
$TB = $(if ($TNew.Count) { Read-Body $TNew[0] } else { $null })
Check 'ignoreSites: Contoso Lab and Northwind not read' (@(Get-Calls 'GET' "$TDA/api/v2/site/s-lab/*").Count -eq 0 -and @(Get-Calls 'GET' "$TDA/api/v2/site/s-north/*").Count -eq 0 -and $o.counts.unmatchedSites -eq 0) (Show-Calls)
Check 'new ticket: one ticket for Contoso (company 42)' ($TNew.Count -eq 1 -and $TB.company.id -eq 42) (Show-Calls)
Check 'new ticket: summary in plain words' ($TB.summary -eq 'Offline devices: 3 not seen recently, including 1 server') $TB.summary
Check 'new ticket: server present, so high priority' ($TB.priority.id -eq 2 -and $TB.impact -eq 'High') ($TB | ConvertTo-Json -Compress)
$TD = [string]$TB.initialDescription
Check 'new ticket: servers line at the top, then other devices' ($TD.IndexOf('Servers first') -ge 0 -and $TD.IndexOf('Servers first') -lt $TD.IndexOf('other devices have')) $TD
Check 'new ticket: each device has type, OS, last seen date and days ago, and a first step' ($TD -match '- CONTOSO-PC01 \(Desktop, Windows 11 Pro\): last seen \d{4}-\d\d-\d\d \d\d:\d\d UTC, 10 days ago\. Suggested first step: Check that the device has power' -and $TD -match 'CONTOSO-LT06 .*100 days ago\. Suggested first step: This device looks retired.*remove it from Datto RMM' -and $TD -match 'CONTOSO-SRV01 \(Server, Windows Server 2022\): .*6 hours ago') $TD
Check 'new ticket: list line for later runs' ($TD -like '*Offline in this check: CONTOSO-SRV01, CONTOSO-LT06, CONTOSO-PC01.*') $TD
$TN = @(Get-Calls 'POST' "$TCW/service/tickets/5001/notes")
Check 'new ticket: internal note with the day marker' ($TN.Count -eq 1 -and (Read-Body $TN[0]).internalAnalysisFlag -eq $true -and (Read-Body $TN[0]).text -like "*[[]offline-device-sweep: $TToday]*") (Show-Calls)
Check 'new ticket: output counts and company row' ($o.status -eq 'success' -and $o.counts.ticketsCreated -eq 1 -and (Get-Row $o 'Contoso').ticketId -eq '5001' -and (Get-Row $o 'Contoso').action -eq 'created') "$($o.status) $($o.message) $($f.r.error)"
Check 'output: message, internal_note, public_note empty' ($o.message -like 'Checked * devices across 2 Datto RMM sites and found 3 offline devices. Opened 1 ticket and updated 0 tickets.' -and $o.internal_note -like '*Contoso: opened ticket #5001*' -and $o.public_note -eq '') $o.message

# ---- 2b. Rerun the same day: the open ticket is found by its summary and nothing new is written ----
$TKeepNotes = $TS.cwNotes
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.cwNotes = $TKeepNotes
$TS.cwOpen = @(@{ id = 5001; summary = $TB.summary; initialDescription = $TD; closedFlag = $false; company = @{ id = 42; name = 'Contoso' }; status = @{ name = 'New' } })
$f = Invoke-Flow @{ ignoreSites = @('Contoso Lab', 'Northwind Traders') }
Check 'rerun: no second ticket, no note' (@(Get-WriteCalls).Count -eq 0 -and (Get-Row $f.r.out 'Contoso').action -eq 'unchanged' -and $f.r.out.counts.ticketsUnchanged -eq 1) "$(Show-Calls) $($f.r.error)"

# ---- 3. companyMap: a site whose name doesn't match goes to the mapped company, merged into one ticket ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ companyMap = '{"Contoso Lab": "42", "s-north": "Fabrikam"}' }
$o = $f.r.out
$TNew = @(Get-Calls 'POST' "$TCW/service/tickets")
$TBodies = @($TNew | ForEach-Object { Read-Body $_ })
$TContoso = @($TBodies | Where-Object { $_.company.id -eq 42 })
$TFab = @($TBodies | Where-Object { $_.company.id -eq 43 })
Check 'companyMap: Contoso Lab (by name) joins the Contoso ticket' ($TContoso.Count -eq 1 -and $TContoso[0].initialDescription -like '*CONTOSO-LAB01*' -and $TContoso[0].initialDescription -like '*Datto RMM sites: Contoso, Contoso Lab.*') (Show-Calls)
Check 'companyMap: Northwind (by site uid, to a company name) goes to Fabrikam' ($TFab.Count -eq 1 -and $TFab[0].initialDescription -like '*NORTHWIND-PC01*' -and $TFab[0].summary -eq 'Offline devices: 1 not seen for 7+ days' -and $TFab[0].impact -eq 'Medium') ($TFab | ConvertTo-Json -Depth 4)
Check 'no servers: the device line does not say "other"' ($TFab.Count -eq 1 -and $TFab[0].initialDescription -like '*1 device has not been seen for 7 days or more:*' -and $TFab[0].initialDescription -notlike '*other device*') ($TFab | ConvertTo-Json -Depth 4)
Check 'companyMap: the mapped name was looked up once, Contoso Lab never searched by its own name' (@(Get-Calls 'GET' "$TCW/company/companies?*" | Where-Object { [uri]::UnescapeDataString($_.Uri) -like '*Contoso Lab*' }).Count -eq 0 -and $o.counts.unmatchedSites -eq 0) (Show-Calls)

# ---- 4. Existing ticket: an internal note with newly offline and recovered devices ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.cwOpen = @(@{ id = 7001; summary = 'Offline devices: 3 not seen for 7+ days'; initialDescription = 'Offline in this check: CONTOSO-PC01, CONTOSO-PC03, CONTOSO-PC09.'; closedFlag = $false; company = @{ id = 42; name = 'Contoso' }; status = @{ name = 'New' } },
    @{ id = 7002; summary = 'Offline devices: 1 not seen for 7+ days'; initialDescription = ''; closedFlag = $false; company = @{ id = 43; name = 'Fabrikam' }; status = @{ name = 'New' } },
    @{ id = 7003; summary = 'Printer jam on floor 2'; initialDescription = ''; closedFlag = $false; company = @{ id = 42; name = 'Contoso' }; status = @{ name = 'New' } })
$TS.cwNotes['7001'] = @([pscustomobject]@{ id = 1; text = "Offline Device Sweep opened this ticket.`nOffline in this check: CONTOSO-PC01, CONTOSO-PC03, CONTOSO-PC09.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' },
    [pscustomobject]@{ id = 2; text = 'Spoke to the client, PC09 is at the repair shop.'; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-02T08:00:00Z' })
$TS.cwNotes['7002'] = @([pscustomobject]@{ id = 3; text = "Offline in this check: FABRIKAM-PC01.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab' }
$o = $f.r.out
$TN = @(Get-Calls 'POST' "$TCW/service/tickets/7001/notes")
$TT = $(if ($TN.Count) { [string](Read-Body $TN[0]).text } else { '' })
Check 'update: no new ticket' (@(Get-Calls 'POST' "$TCW/service/tickets").Count -eq 0) (Show-Calls)
Check 'update: one internal note on the open ticket' ($TN.Count -eq 1 -and (Read-Body $TN[0]).internalAnalysisFlag -eq $true -and $TT -like "*[[]offline-device-sweep: $TToday]") $TT
Check 'update: newly offline and still offline listed' ($TT -like '*2 devices are newly offline, 1 device is still offline, 2 devices have recovered*' -and $TT -match '(?s)Newly offline:.*CONTOSO-SRV01.*CONTOSO-LT06.*Still offline:.*CONTOSO-PC01') $TT
Check 'update: recovered devices noted with the reason' ($TT -like '*- CONTOSO-PC03 is back online in Datto RMM.*' -and $TT -like '*- CONTOSO-PC09 is no longer in Datto RMM.*') $TT
Check 'update: a newly offline server is called out' ($TT -like '*A server is newly offline*raising*priority*') $TT
$TF = @(Get-Calls 'POST' "$TCW/service/tickets/7002/notes")
$TFT = $(if ($TF.Count) { [string](Read-Body $TF[0]).text } else { '' })
Check 'update: every device recovered, so the note says close the ticket' ($TF.Count -eq 1 -and $TFT -like '*1 device has recovered*' -and $TFT -like '*Nothing on this ticket is offline any more*' -and $TFT -like '*FABRIKAM-PC01 is back online*' -and $TFT -like '*Offline in this check: none.*') $TFT
Check 'update: the non-sweep ticket is left alone' (@(Get-Calls 'POST' "$TCW/service/tickets/7003/*").Count -eq 0)
Check 'update: counts' ($o.status -eq 'success' -and $o.counts.ticketsUpdated -eq 2 -and $o.counts.ticketsCreated -eq 0 -and (Get-Row $o 'Contoso').action -eq 'updated' -and @((Get-Row $o 'Contoso').recovered).Count -eq 2) "$($o.status) $($f.r.error) $($o.counts | ConvertTo-Json -Compress)"

# ---- 4b. Preview of the same: would update, nothing written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler
$TS.cwNotes['7001'] = @($TS.cwNotes['7001'] | Where-Object { [string]$_.text -notlike "*$TToday*" })
$TS.cwNotes['7002'] = @($TS.cwNotes['7002'] | Where-Object { [string]$_.text -notlike "*$TToday*" })
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab'; dryRun = 'true' }
Check 'dry run (dryRun alias): would update 2, nothing written' ($f.r.out.status -eq 'pending_confirmation' -and $f.r.out.counts.wouldUpdate -eq 2 -and @(Get-WriteCalls).Count -eq 0 -and $f.r.out.message -like 'Preview:*Nothing was changed.*') "$($f.r.out.message) $(Show-Calls)"

# ---- 5. 429 from Datto: waits Retry-After (or 60 seconds) and tries again ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.fab429 = 1; $TS.retryAfter = '7'
$f = Invoke-Flow @{ preview = $true }
Check '429: Fabrikam devices read twice, waited 7 seconds' (@(Get-Calls 'GET' "$TDA/api/v2/site/s-fab/devices*").Count -eq 2 -and @($Mock.Sleeps) -contains 7 -and $f.r.out.status -eq 'pending_confirmation') "$(@($Mock.Sleeps) -join ',') $($f.r.error)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.fab429 = 2; $TS.token429 = 1
$f = Invoke-Flow @{ preview = $true }
Check '429 without Retry-After: waits 60 seconds each time (token and reads)' (@($Mock.Sleeps | Where-Object { $_ -eq 60 }).Count -eq 3 -and $f.r.out.status -eq 'pending_confirmation') "$(@($Mock.Sleeps) -join ',') $($f.r.error)"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.fab429 = 10
$f = Invoke-Flow @{ preview = $true }
Check '429 that never clears: stops with a plain sentence' ($f.stage -eq 'find' -and $f.r.error -like "*Couldn't read the devices at the Datto RMM site 'Fabrikam'*HTTP 429 (too many requests)*600 reads a minute*") $f.r.error

# ---- 6. Datto sign-in failure and missing secrets: clear errors, nothing written ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.tokenFail = 401
$f = Invoke-Flow @{}
Check 'auth failure: stops at find with a clear error' ($f.stage -eq 'find' -and $f.r.out.status -eq 'error' -and $f.r.error -like 'Datto RMM refused the sign-in (HTTP 401). Check that Datto-ApiKey and Datto-ApiSecret*') $f.r.error
Check 'auth failure: no reads, no writes, no secret in the message' (@($Mock.Calls | Where-Object { $_.Uri -like "$TDA/api/*" }).Count -eq 0 -and @(Get-WriteCalls).Count -eq 0 -and $f.r.error -notlike '*ds-placeholder*') (Show-Calls)
Reset-Mock (Get-TSecrets 'connectwise' -NoDatto) $Handler; Reset-Scenario
$f = Invoke-Flow @{}
Check 'missing Datto secrets: names them' ($f.r.out.status -eq 'error' -and $f.r.error -like "*Datto RMM isn't set up. Add these secrets to the runner Key Vault: Datto-ApiUrl, Datto-ApiKey, Datto-ApiSecret.") $f.r.error
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.foreignNext = $true
$f = Invoke-Flow @{ preview = $true }
Check 'a next-page link on another host is not followed (the token stays home)' ($f.stage -eq 'find' -and $f.r.error -like '*next-page link on another host (elsewhere.example.org)*' -and @($Mock.Calls | Where-Object { $_.Uri -like 'https://elsewhere.example.org*' }).Count -eq 0) $f.r.error

# ---- 7. Bad input fails closed ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
foreach ($TBad in @(@{ offlineDays = 'soon' }, @{ serverOfflineHours = 0 }, @{ includeCategories = 'toasters' }, @{ companyMap = 'not json' }, @{ priority = 'whenever' }, @{ preview = 'maybe' })) {
    $f = Invoke-Flow $TBad
    Check "bad input $(($TBad | ConvertTo-Json -Compress)): error, no calls" ($f.stage -eq 'find' -and $f.r.out.status -eq 'error' -and $Mock.Calls.Count -eq 0) "$($f.r.error) $(Show-Calls)"
}
$f = Invoke-Flow @{ offlineDays = 'soon' }
Check 'bad input: the message is a plain sentence' ($f.r.error -eq "offlineDays must be a whole number from 1 to 3650, not 'soon'.") $f.r.error

# ---- 8. includeCategories and thresholds from input ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ preview = $true; includeCategories = @('printers', 'laptop'); offlineDays = 2 }
$THosts = @((Get-Plan $f.find 'Contoso').devices | ForEach-Object { $_.hostname })
Check 'includeCategories: printers and laptops only, offlineDays 2' ((($THosts | Sort-Object) -join ',') -eq 'CONTOSO-LT02,CONTOSO-LT06,CONTOSO-PRN01') ($THosts -join ',')

# ---- 9. Autotask: new ticket at high priority, internal note ----
Reset-Mock (Get-TSecrets 'autotask') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab' }
$o = $f.r.out
$TA = @(Get-Calls 'POST' "$TAT/Tickets")
$TAB = $(if ($TA.Count) { Read-Body $TA[0] } else { $null })
Check 'autotask: one ticket for Contoso, priority High from the picklist' ($TA.Count -eq 1 -and $TAB.companyID -eq 42 -and $TAB.priority -eq 1 -and $TAB.title -like 'Offline devices: 3 *' -and $TAB.description -like '*Servers first*') "$(Show-Calls) $($f.r.error)"
$TAN = @(Get-Calls 'POST' "$TAT/Tickets/6001/Notes")
Check 'autotask: internal note (Internal Only) with the marker' ($TAN.Count -eq 1 -and (Read-Body $TAN[0]).publish -eq 2 -and (Read-Body $TAN[0]).description -like "*[[]offline-device-sweep: $TToday]*") (Show-Calls)
Check 'autotask: Northwind unmatched, success' ($o.status -eq 'success' -and $o.counts.ticketsCreated -eq 1 -and $o.counts.unmatchedSites -eq 1) "$($o.status) $($o.message)"

# ---- 10. Zendesk: existing ticket updated with a private comment ----
Reset-Mock (Get-TSecrets 'zendesk') $Handler; Reset-Scenario
$TS.zdOpen = @(@{ id = 8100; subject = 'Offline devices: 1 not seen for 7+ days'; description = 'Offline in this check: CONTOSO-PC01.'; status = 'open'; organization_id = 77; created_at = '2026-10-01T08:00:00Z' })
$TS.zdComments = @(@{ id = 1; body = "Offline in this check: CONTOSO-PC01.`n[offline-device-sweep: 2026-10-01]"; public = $false; author_id = 5; created_at = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab' }
$o = $f.r.out
$TZ = @(Get-Calls 'PUT' "$TZD/tickets/8100")
$TZB = $(if ($TZ.Count) { Read-Body $TZ[0] } else { $null })
Check 'zendesk: no new ticket, one private comment' (@(Get-Calls 'POST' "$TZD/tickets").Count -eq 0 -and $TZ.Count -eq 1 -and $TZB.ticket.comment.public -eq $false) "$(Show-Calls) $($f.r.error)"
Check 'zendesk: comment lists the newly offline server and laptop' ($TZB.ticket.comment.body -like '*2 devices are newly offline, 1 device is still offline.*' -and $TZB.ticket.comment.body -like "*[[]offline-device-sweep: $TToday]*") $TZB.ticket.comment.body
Check 'zendesk: counts' ($o.status -eq 'success' -and $o.counts.ticketsUpdated -eq 1 -and (Get-Row $o 'Contoso').ticketId -eq '8100') "$($o.status) $($o.message)"

# ---- 11. The ticket step on its own ----
$t = Invoke-Step 'node-ticket' $null
Check 'ticket step with no input: plain error' ($t.out.status -eq 'error' -and $t.error -like '*Run the workflow from the start*') $t.error

# ---- 12. Site down: every server past its threshold and most devices offline now gets one line at the top ----
# Fabrikam: its only server 6 hours offline, two desktops offline 6 hours (under 7 days, so not listed), one online.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 6) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 6)),
    (TDev 'FABRIKAM-PC02' 'Desktop' $false (TMs 6)), (TDev 'FABRIKAM-PC03' 'Desktop' $true (TMs 0.1)))
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab, Northwind Traders' }
$o = $f.r.out
$TFP = Get-Plan $f.find 'Fabrikam'
Check 'site down: find counts the site (3 of 4 offline, 1 server)' ($f.find.counts.sitesDown -eq 1 -and @($TFP.sitesDown).Count -eq 1 -and $TFP.sitesDown[0].checked -eq 4 -and $TFP.sitesDown[0].offline -eq 3 -and $TFP.sitesDown[0].servers -eq 1) "$($f.r.error) $($TFP | ConvertTo-Json -Depth 4)"
$TFB = @(Get-Calls 'POST' "$TCW/service/tickets" | ForEach-Object { Read-Body $_ } | Where-Object { $_.company.id -eq 43 })
$TFD = $(if ($TFB.Count) { [string]$TFB[0].initialDescription } else { '' })
Check 'site down: the line sits above the device list' ($TFD -like '*The whole Fabrikam site may be down: Datto RMM shows 3 of its 4 devices offline right now, including its only server. Check the site''s power, internet connection and firewall*' -and $TFD.IndexOf('may be down') -lt $TFD.IndexOf('Servers first')) $TFD
Check 'site down: only the server is listed (the desktops are under 7 days)' ($TFD -like '*Offline in this check: FABRIKAM-SRV01.*' -and $TFB[0].impact -eq 'High') $TFD
$TCB = @(Get-Calls 'POST' "$TCW/service/tickets" | ForEach-Object { Read-Body $_ } | Where-Object { $_.company.id -eq 42 })
Check 'site down: Contoso has a server under its threshold, so no line' ($TCB.Count -eq 1 -and [string]$TCB[0].initialDescription -notlike '*may be down*' -and @((Get-Plan $f.find 'Contoso').sitesDown).Count -eq 0) ([string]$TCB[0].initialDescription)
Check 'site down: output row, count and run summary' (@((Get-Row $o 'Fabrikam').sitesDown) -contains 'Fabrikam' -and @((Get-Row $o 'Contoso').sitesDown).Count -eq 0 -and $o.counts.sitesDown -eq 1 -and $o.internal_note -like '*Fabrikam: the whole Datto RMM site Fabrikam may be down (power, internet or firewall).*') $o.internal_note

# ---- 12b. Not a site down: most devices online, a lone server, or a second server still online ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 6) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $true (TMs 0.1)),
    (TDev 'FABRIKAM-PC02' 'Desktop' $true (TMs 0.1)), (TDev 'FABRIKAM-PC03' 'Desktop' $false (TMs 6)))
$TS.devices['s-north'] = @((TDev 'NORTHWIND-SRV01' 'Server' $false (TMs 6) 'Windows Server 2022'))
$TS.devices['s-lab'] = @((TDev 'CONTOSO-LABSRV1' 'Server' $false (TMs 6) 'Windows Server 2022'), (TDev 'CONTOSO-LABSRV2' 'Server' $true (TMs 0.1)), (TDev 'CONTOSO-LAB01' 'Desktop' $false (TMs 480)), (TDev 'CONTOSO-LAB02' 'Desktop' $false (TMs 480)), (TDev 'CONTOSO-LAB03' 'Desktop' $false (TMs 480)))
$f = Invoke-Flow @{ preview = $true }
Check 'not site down: 2 of 4 offline, a one-device site, a server still online' ($f.stage -eq 'ticket' -and $f.find.counts.sitesDown -eq 0 -and $f.r.out.counts.sitesDown -eq 0 -and (Get-Row $f.r.out 'Fabrikam').text -notlike '*may be down*') "$($f.r.error) $($f.find.counts | ConvertTo-Json -Compress)"

# ---- 12c. Site down on an open ticket: the update note carries the line under its first sentence ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 6) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 300)))
$TS.cwOpen = @(@{ id = 7002; summary = 'Offline devices: 1 not seen for 7+ days'; initialDescription = ''; closedFlag = $false; company = @{ id = 43; name = 'Fabrikam' }; status = @{ name = 'New' } })
$TS.cwNotes['7002'] = @([pscustomobject]@{ id = 3; text = "Offline in this check: FABRIKAM-PC01.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ ignoreSites = 'Contoso, Contoso Lab, Northwind Traders' }
$TN = @(Get-Calls 'POST' "$TCW/service/tickets/7002/notes")
$TT = $(if ($TN.Count) { [string](Read-Body $TN[0]).text } else { '' })
Check 'site down on update: note has the line after its first sentence, all servers' ($TN.Count -eq 1 -and $TT -match '(?s)^Offline Device Sweep checked Fabrikam again[^\n]*\n\nThe whole Fabrikam site may be down: Datto RMM shows 2 of its 2 devices offline right now, including its only server\..*Newly offline:.*FABRIKAM-SRV01') $TT


# ---- 12d. The site goes down after the ticket already lists its server: a note, even with no new device listed ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 30) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 6)),
    (TDev 'FABRIKAM-PC02' 'Desktop' $false (TMs 6)), (TDev 'FABRIKAM-PC03' 'Desktop' $false (TMs 6)))
$TS.cwOpen = @(@{ id = 7003; summary = 'Offline devices: 1 not seen for 7+ days'; initialDescription = ''; closedFlag = $false; company = @{ id = 43; name = 'Fabrikam' }; status = @{ name = 'New' } })
$TS.cwNotes['7003'] = @([pscustomobject]@{ id = 4; text = "Offline Device Sweep checked Fabrikam again on 2026-10-01 08:00 UTC: 1 device is newly offline.`nOffline in this check: FABRIKAM-SRV01.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ ignoreSites = 'Contoso, Contoso Lab, Northwind Traders' }
$TN = @(Get-Calls 'POST' "$TCW/service/tickets/7003/notes")
$TT = $(if ($TN.Count) { [string](Read-Body $TN[0]).text } else { '' })
Check 'site newly down, same list: one note with the line' ($TN.Count -eq 1 -and $TT -like '*The whole Fabrikam site may be down: Datto RMM shows 4 of its 4 devices offline right now*' -and $TT -like '*Still offline:*FABRIKAM-SRV01*' -and $TT -notlike '*Newly offline:*' -and $f.r.out.counts.ticketsUpdated -eq 1) "$($f.r.error) $TT"

# ---- 12e. The last note already says the site is down and nothing else changed: no note ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 30) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 6)),
    (TDev 'FABRIKAM-PC02' 'Desktop' $false (TMs 6)), (TDev 'FABRIKAM-PC03' 'Desktop' $false (TMs 6)))
$TS.cwOpen = @(@{ id = 7004; summary = 'Offline devices: 1 not seen for 7+ days'; initialDescription = "Offline Device Sweep found 1 device at Fabrikam.`n`nThe whole Fabrikam site may be down: Datto RMM shows 4 of its 4 devices offline right now, including its only server.`n`nOffline in this check: FABRIKAM-SRV01."; closedFlag = $false; company = @{ id = 43; name = 'Fabrikam' }; status = @{ name = 'New' } })
$TS.cwNotes['7004'] = @([pscustomobject]@{ id = 5; text = "Offline Device Sweep opened this ticket on 2026-10-01 08:00 UTC for 1 device that Datto RMM has not seen recently.`nOffline in this check: FABRIKAM-SRV01.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ ignoreSites = 'Contoso, Contoso Lab, Northwind Traders' }
Check 'site already noted as down at opening: no note' (@(Get-Calls 'POST' "$TCW/service/tickets/7004/notes").Count -eq 0 -and $f.r.out.counts.ticketsUnchanged -eq 1) "$($f.r.error) $($f.r.out.counts | ConvertTo-Json -Compress)"

# ---- 13. Wake-on-LAN off (the default): the wake step hands on what it got and calls nothing ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'wake off: no audit, component or job calls, no wake summary' ($f.stage -eq 'ticket' -and @($Mock.Calls | Where-Object { $_.Uri -like "$TDA/api/v2/audit/*" -or $_.Uri -like "$TDA/api/v2/account/components*" -or $_.Method -eq 'PUT' }).Count -eq 0 -and $null -eq $f.r.out.wake -and $f.r.out.counts.wakeSent -eq 0) "$($f.r.error) $(Show-Calls)"
Check 'wake off: no peers listed by the find step' (@($f.find.wakeSites).Count -eq 0) ($f.find.wakeSites | ConvertTo-Json -Depth 4)

# ---- 14. Wake preview: only the desktop, from an online desktop on its network; nothing sent ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ preview = $true; wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
$o = $f.r.out
$TRow = Get-Row $o 'Contoso'
Check 'wake preview: one would-wake (the desktop, not the laptop or server)' ($f.stage -eq 'ticket' -and $o.wake.wouldWake -eq 1 -and $o.counts.wouldWake -eq 1 -and $o.wake.sent -eq 0) "$($f.r.error) $($o.wake | ConvertTo-Json -Depth 4)"
Check 'wake preview: nothing written anywhere, no Datto job' (@(Get-WriteCalls).Count -eq 0 -and @(Get-Calls 'PUT' "$TDA/*").Count -eq 0 -and @($Mock.Sleeps).Count -eq 0) (Show-Calls)
Check 'wake preview: the ticket text names the peer' ($TRow.text -match 'CONTOSO-PC01 [^\n]*A wake-up would be sent from CONTOSO-PC03 before ticketing\.' -and $TRow.text -notmatch 'CONTOSO-LT06 [^\n]*wake') $TRow.text
Check 'wake preview: the run summary says so' ($o.message -like '*Would send 1 wake-up first.') $o.message

# ---- 15. Wake live, the desktop comes back: left off the ticket, which still lists the rest ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.wakeBack = @('CONTOSO-PC01')
$f = Invoke-Flow @{ wake = 'yes'; wakeWaitMinutes = 3; ignoreSites = 'Contoso Lab, Northwind Traders' }
$o = $f.r.out
$TJob = @(Get-Calls 'PUT' "$TDA/api/v2/device/*/quickjob")
$TJB = $(if ($TJob.Count) { Read-Body $TJob[0] } else { $null })
Check 'wake live: one quick job, on the peer, with the wake component' ($TJob.Count -eq 1 -and $TJob[0].Uri -eq "$TDA/api/v2/device/uid-CONTOSO-PC03/quickjob" -and $TJB.jobComponent.componentUid -eq 'comp-wol') "$($f.r.error) $(Show-Calls)"
Check 'wake live: the MAC address goes in the MacAddress variable' (@($TJB.jobComponent.variables | Where-Object { $_.name -eq 'MacAddress' -and $_.value -eq '001122AABB01' }).Count -eq 1) ($TJB | ConvertTo-Json -Depth 5)
Check 'wake live: the job is never retried or redirected' ($TJob[0].MaxRedirect -eq 0) "$($TJob[0].MaxRedirect)"
Check 'wake live: waited 3 minutes, then read the site again' (@($Mock.Sleeps) -contains 180 -and @(Get-Calls 'GET' "$TDA/api/v2/site/s-contoso/devices?max=250").Count -eq 2) "$(@($Mock.Sleeps) -join ',')"
$TB = Read-Body @(Get-Calls 'POST' "$TCW/service/tickets")[0]
$TD = [string]$TB.initialDescription
Check 'wake live: the desktop that came back is not on the ticket' ($TD -like '*Offline in this check: CONTOSO-SRV01, CONTOSO-LT06.*' -and $TD -like '*Came back online after a wake-up, so not listed: CONTOSO-PC01.*' -and $TB.summary -eq 'Offline devices: 2 not seen recently, including 1 server') $TD
Check 'wake live: counts and run summary' ($o.counts.wakeSent -eq 1 -and $o.counts.wokeUp -eq 1 -and $o.wake.attempts[0].cameBack -eq $true -and $o.wake.attempts[0].peer -eq 'CONTOSO-PC03' -and $o.message -like '*Sent 1 wake-up first; 1 came back online.') "$($o.message) $($o.wake | ConvertTo-Json -Depth 4)"

# ---- 15b. Wake live, still offline and the job failed: ticketed with a line saying so ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.jobStatus = 'Failure'
$f = Invoke-Flow @{ wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
$TD = [string](Read-Body @(Get-Calls 'POST' "$TCW/service/tickets")[0]).initialDescription
Check 'wake still offline: listed, with the wake-up and the job result' ($TD -match 'CONTOSO-PC01 [^\n]*A wake-up was sent from CONTOSO-PC03 at \d\d:\d\d UTC; it was still offline 5 minutes later\. The Datto job on CONTOSO-PC03 ended as ''Failure''' -and $TD -like '*Offline in this check: CONTOSO-SRV01, CONTOSO-LT06, CONTOSO-PC01.*') "$($f.r.error) $TD"
Check 'wake still offline: default wait 5 minutes' (@($Mock.Sleeps) -contains 300 -and $f.r.out.counts.wokeUp -eq 0) "$(@($Mock.Sleeps) -join ',')"

# ---- 15c. Every desktop came back: no ticket at all ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 240)), (TDev 'FABRIKAM-PC02' 'Desktop' $true (TMs 0.1)))
$TS.wakeBack = @('FABRIKAM-PC01')
$f = Invoke-Flow @{ wake = $true; ignoreSites = 'Contoso, Contoso Lab, Northwind Traders' }
$o = $f.r.out
Check 'all woke: no ticket, the run summary says why' (@(Get-Calls 'POST' "$TCW/service/tickets").Count -eq 0 -and (Get-Row $o 'Fabrikam').action -eq 'woke' -and $o.internal_note -like '*Fabrikam: no ticket opened, because FABRIKAM-PC01 came back online after a wake-up.*') "$($f.r.error) $($o.internal_note)"

# ---- 15d. Open ticket: a desktop on its last list came back, so it is noted as recovered ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.wakeBack = @('CONTOSO-PC01')
$TS.cwOpen = @(@{ id = 7001; summary = 'Offline devices: 3 not seen recently, including 1 server'; initialDescription = ''; closedFlag = $false; company = @{ id = 42; name = 'Contoso' }; status = @{ name = 'New' } })
$TS.cwNotes['7001'] = @([pscustomobject]@{ id = 1; text = "Offline in this check: CONTOSO-SRV01, CONTOSO-LT06, CONTOSO-PC01.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
$TN = @(Get-Calls 'POST' "$TCW/service/tickets/7001/notes")
$TT = $(if ($TN.Count) { [string](Read-Body $TN[0]).text } else { '' })
Check 'wake on an open ticket: one note, PC01 recovered after the wake-up' ($TN.Count -eq 1 -and $TT -like '*- CONTOSO-PC01 came back online after a wake-up sent from CONTOSO-PC03.*' -and $TT -like '*Offline in this check: CONTOSO-SRV01, CONTOSO-LT06.*' -and (Get-Row $f.r.out 'Contoso').action -eq 'updated') "$($f.r.error) $TT"

# ---- 15e. A site newly down still gets its note when the only new device at the company's other site woke ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 30) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 6)),
    (TDev 'FABRIKAM-PC02' 'Desktop' $false (TMs 6)), (TDev 'FABRIKAM-PC03' 'Desktop' $false (TMs 6)))
$TS.devices['s-lab'] = @((TDev 'CONTOSO-LAB01' 'Desktop' $false (TMs 240)), (TDev 'CONTOSO-LAB02' 'Desktop' $true (TMs 0.1)))
$TS.nics['uid-CONTOSO-LAB01'] = @(@{ macAddress = '00-11-22-1A-B0-01'; ipv4 = '10.7.0.11' }); $TS.nics['uid-CONTOSO-LAB02'] = @(@{ macAddress = '00-11-22-1A-B0-02'; ipv4 = '10.7.0.12' })
$TS.wakeBack = @('CONTOSO-LAB01')
$TS.cwOpen = @(@{ id = 7003; summary = 'Offline devices: 1 not seen for 7+ days'; initialDescription = ''; closedFlag = $false; company = @{ id = 43; name = 'Fabrikam' }; status = @{ name = 'New' } })
$TS.cwNotes['7003'] = @([pscustomobject]@{ id = 4; text = "Offline Device Sweep checked Fabrikam again on 2026-10-01 08:00 UTC: 1 device is newly offline.`nOffline in this check: FABRIKAM-SRV01.`n[offline-device-sweep: 2026-10-01]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ wake = $true; companyMap = '{"Contoso Lab": "Fabrikam"}'; ignoreSites = 'Contoso, Northwind Traders' }
$TN = @(Get-Calls 'POST' "$TCW/service/tickets/7003/notes")
$TT = $(if ($TN.Count) { [string](Read-Body $TN[0]).text } else { '' })
Check 'wake and a newly down site: the woken desktop is dropped, the site-down note is still written' ($f.r.out.counts.wokeUp -eq 1 -and $TN.Count -eq 1 -and $TT -like '*The whole Fabrikam site may be down*' -and $TT -notlike '*CONTOSO-LAB01*') "$($f.r.error) $TT"

# ---- 16. Wake gates ----
# Rerun the same day: the company was already noted today, so nothing is sent twice.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.cwOpen = @(@{ id = 7001; summary = 'Offline devices: 3 not seen recently, including 1 server'; initialDescription = ''; closedFlag = $false; company = @{ id = 42; name = 'Contoso' }; status = @{ name = 'New' } })
$TS.cwNotes['7001'] = @([pscustomobject]@{ id = 1; text = "Offline in this check: CONTOSO-SRV01, CONTOSO-LT06, CONTOSO-PC01.`n[offline-device-sweep: $TToday]"; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false; dateCreated = '2026-10-01T08:00:00Z' })
$f = Invoke-Flow @{ wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'gate: already noted today, so no wake-up and no note' (@(Get-Calls 'PUT' "$TDA/*").Count -eq 0 -and @(Get-WriteCalls).Count -eq 0 -and @($Mock.Sleeps).Count -eq 0) "$($f.r.error) $(Show-Calls)"
# The whole site may be down: nothing there could send a packet.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.devices['s-fab'] = @((TDev 'FABRIKAM-SRV01' 'Server' $false (TMs 6) 'Windows Server 2022'), (TDev 'FABRIKAM-PC01' 'Desktop' $false (TMs 240)), (TDev 'FABRIKAM-PC02' 'Desktop' $false (TMs 240)), (TDev 'FABRIKAM-PC03' 'Desktop' $true (TMs 0.1)))
$f = Invoke-Flow @{ preview = $true; wake = $true; ignoreSites = 'Contoso, Contoso Lab, Northwind Traders' }
Check 'gate: site down, so no wake-up' ($f.r.out.wake.wouldWake -eq 0 -and @($f.r.out.wake.skipped | Where-Object { $_.reason -like '*whole site may be down*' }).Count -eq 2 -and (Get-Row $f.r.out 'Fabrikam').text -like '*No wake-up was sent: the whole site may be down*') "$($f.r.error) $($f.r.out.wake | ConvertTo-Json -Depth 4)"
# No online desktop on the same network (the only peer is on another subnet).
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.nics['uid-CONTOSO-PC03'] = @(@{ macAddress = '00:11:22:aa:bb:03'; ipv4 = '10.0.2.23' })
$f = Invoke-Flow @{ preview = $true; wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'gate: peer on another subnet, so skipped with a reason' ($f.r.out.wake.wouldWake -eq 0 -and @($f.r.out.wake.skipped | Where-Object { $_.hostname -eq 'CONTOSO-PC01' -and $_.reason -eq 'no online Windows desktop or laptop is on its network' }).Count -eq 1) "$($f.r.error) $($f.r.out.wake | ConvertTo-Json -Depth 4)"
# No MAC address in the audit.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.nics.Remove('uid-CONTOSO-PC01')
$f = Invoke-Flow @{ preview = $true; wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'gate: no MAC address, so skipped' (@($f.r.out.wake.skipped | Where-Object { $_.reason -eq 'Datto RMM has no MAC address for it' }).Count -eq 1) "$($f.r.error) $($f.r.out.wake | ConvertTo-Json -Depth 4)"
# A server is never used to send the packet.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.contoso1 = @($TS.contoso1 | Where-Object { $_.hostname -ne 'CONTOSO-PC03' }) + @((TDev 'CONTOSO-SRV09' 'Server' $true (TMs 0.1) 'Windows Server 2022'))
$f = Invoke-Flow @{ preview = $true; wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'gate: only a server online, so no peer' (@($f.r.out.wake.skipped | Where-Object { $_.reason -like 'no Windows desktop or laptop at its site is online*' }).Count -eq 1 -and @(Get-Calls 'GET' "$TDA/api/v2/audit/*").Count -eq 0) "$($f.r.error) $($f.r.out.wake | ConvertTo-Json -Depth 4)"
# wakeMax: the second desktop is left for a later run.
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.contoso1 = @($TS.contoso1) + @((TDev 'CONTOSO-PC07' 'Desktop' $false (TMs 300)))
$TS.nics['uid-CONTOSO-PC07'] = @(@{ macAddress = '00-11-22-AA-BB-07'; ipv4 = '10.0.1.27' })
$f = Invoke-Flow @{ preview = $true; wake = $true; wakeMax = 1; ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'gate: wakeMax 1 tries one desktop and skips the other' ($f.r.out.wake.wouldWake -eq 1 -and @($f.r.out.wake.skipped | Where-Object { $_.reason -like '*wakeMax limit' }).Count -eq 1) "$($f.r.error) $($f.r.out.wake | ConvertTo-Json -Depth 4)"

# ---- 17. Wake failures never stop the tickets ----
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.components = @(@{ uid = 'comp-other'; name = 'Disk Cleanup' })
$f = Invoke-Flow @{ wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
Check 'no wake component: warned, no job, the ticket still opens' ($f.stage -eq 'ticket' -and @(Get-Calls 'PUT' "$TDA/*").Count -eq 0 -and @(Get-Calls 'POST' "$TCW/service/tickets").Count -eq 1 -and @($f.r.out.warnings | Where-Object { $_ -like "*Datto RMM has no component named 'Wake-on-LAN'*datto-component*" }).Count -eq 1) "$($f.r.error) $(@($f.r.out.warnings) -join ' | ')"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$TS.jobFail = 403
$f = Invoke-Flow @{ wake = $true; ignoreSites = 'Contoso Lab, Northwind Traders' }
$TD = [string](Read-Body @(Get-Calls 'POST' "$TCW/service/tickets")[0]).initialDescription
Check 'job refused (403): tried once, no wait, the ticket says why' (@(Get-Calls 'PUT' "$TDA/*").Count -eq 1 -and @($Mock.Sleeps).Count -eq 0 -and $TD -match 'CONTOSO-PC01 [^\n]*No wake-up was sent: the Datto job on CONTOSO-PC03 could not be started \(Datto RMM refused PUT [^\n]*Devices: Manage, Active Jobs: Manage') "$($f.r.error) $TD"
Reset-Mock (Get-TSecrets 'connectwise') $Handler; Reset-Scenario
$f = Invoke-Flow @{ wake = $true; wakeWaitMinutes = 30 }
Check 'bad wakeWaitMinutes: fails closed before any call' ($f.stage -eq 'find' -and $f.r.error -eq "wakeWaitMinutes must be a whole number from 1 to 10, not '30'." -and $Mock.Calls.Count -eq 0) $f.r.error
$t = Invoke-Step 'node-wake' $null
Check 'wake step with no input: plain error' ($t.error -like '*Run the workflow from the start*') $t.error

Complete-Test
