$ErrorActionPreference = 'Stop'
Set-StrictMode -Off
# === NODE: Install the requested software ===
# Runs from the "Request Software" portal form (Action question). Maps the app picked in the dropdown to a
# Datto RMM component, runs it as a quick job on the target device, waits for the result, then writes an
# internal note on the request ticket and sends the requester a Signal.
# Form Field IDs: softwareApp (dropdown) and deviceName (dropdown filled from the company's @endpoints token).
# Optional input: defaultDevice (used when the form has no computer), cloudradial_company (use that portal's
# CloudRadial-*-<suffix> secrets), waitMinutes (default 6). A run with "confirm": false previews only.
function P { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
function J { param($x) if ($x -is [string]) { try { return ($x | ConvertFrom-Json) } catch { return $null } }; return $x }
function Sec { param([string]$n) [string](Get-AzKeyVaultSecret -VaultName $env:RUNNER_KV_NAME -Name $n -AsPlainText -ErrorAction SilentlyContinue) }

$in = Get-NodeInput; $trig = J (P $in 'trigger'); if ($null -eq $trig) { $trig = $in }
function Ans { param([string]$key, [string]$label) $v = P $trig $key; if ($null -eq $v -or [string]$v -eq '') { $qs = @(P (P $trig 'Ticket') 'Questions'); foreach ($q in $qs) { if ([string](P $q 'Id') -eq $key -or [string](P $q 'Label') -eq $label) { $v = P $q 'Value' } } }; $s = ([string]$v).Trim(); if ($s -match '^@') { $s = '' }; return $s }

# ---- Catalog: dropdown label -> Datto RMM component and its variables ----
$catalog = [ordered]@{
    'Google Chrome' = @{ component = 'Google Chrome [WIN]';  vars = @{ usrAction = 'Install/Update existing installation' } }
    'Zoom'          = @{ component = 'Zoom Workplace [WIN]'; vars = @{ usrAction = 'Install/Upgrade Zoom' } }
    '7-Zip'         = @{ component = '7-Zip [WIN]';          vars = @{ usrAction = 'Install & update whatever is present'; usr7zFileAssoc = 'true' } }
    'Notepad++'     = @{ component = 'Notepad++ [WIN]';      vars = @{ usrPreferx64 = 'true' } }
}
$defaultDevice = [string](P $trig 'defaultDevice')

$app = Ans 'softwareApp' 'Software'
$device = Ans 'deviceName' 'Computer name'; if (-not $device) { $device = [string](P $trig 'deviceName') }; if (-not $device) { $device = $defaultDevice }
$confirmTxt = [string](P $trig 'confirm'); $confirm = -not ($confirmTxt -match '^(?i)(false|0|no)$')
$waitMinutes = 6; $w = [string](P $trig 'waitMinutes'); if ($w -match '^\d+$') { $waitMinutes = [int]$w }
$ticketId = [string](P (P $trig 'ticket') 'id'); if (-not $ticketId) { $ticketId = [string](P (P $trig 'Ticket') 'TicketId') }; if (-not $ticketId) { $ticketId = [string](P $trig 'ticketId') }
$company = P $trig 'company'; $companyId = [int](P $company 'id'); $companyName = [string](P $company 'name')
$user = P $trig 'user'; $userId = [string](P $user 'id'); $userName = [string](P $user 'name'); $userEmail = [string](P $user 'email')
$crSuffix = [string](P $trig 'cloudradial_company')
$crSuffix = ($crSuffix.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')

$steps = New-Object System.Collections.Generic.List[string]; $warnings = New-Object System.Collections.Generic.List[string]
$status = 'error'; $msg = ''; $jobUid = $null; $result = $null
$deviceUser = ''; $forSomeoneElse = $false; $ownerNote = ''
# Whose computer is it? Compares the Datto RMM device's last signed-in user with the requester's name and email.
function Norm { param([string]$s) return ($s.ToLower() -replace '[^a-z0-9]', '') }
function Test-SameUser { param([string]$DeviceUser, [string]$Name, [string]$Email)
    $du = ($DeviceUser -split '\\')[-1]; if ($du -match '@') { $du = $du.Split('@')[0] }; $du = Norm $du
    if (-not $du) { return $null }
    $local = if ($Email -match '@') { $Email.Split('@')[0] } else { '' }
    $parts = @($Name -split '\s+' | Where-Object { $_ })
    $cands = @((Norm $Name), (Norm $local)); if ($parts.Count -ge 2) { $cands += @((Norm "$($parts[0][0])$($parts[-1])"), (Norm "$($parts[0])$($parts[-1][0])"), (Norm "$($parts[0]).$($parts[-1])")) }
    foreach ($c in @($cands | Where-Object { $_.Length -ge 3 })) { if ($du -eq $c -or $du.StartsWith($c) -or $c.StartsWith($du)) { return $true } }
    return $false
}

# Match the app (exact, then contains)
$key = $null; foreach ($k in $catalog.Keys) { if ($k -ieq $app) { $key = $k } }
if (-not $key -and $app) { foreach ($k in $catalog.Keys) { if ($app -like "*$k*" -or $k -like "*$app*") { $key = $k } } }

if (-not $key) { $msg = "No software was installed. '$app' isn't in the software catalog. Options: $(@($catalog.Keys) -join ', ')." }
elseif (-not $device) { $msg = "No software was installed. Pick the computer to install $key on." }
else {
    $item = $catalog[$key]
    # ---- Datto RMM sign-in ----
    $base = (Sec 'Datto-ApiUrl').Trim().TrimEnd('/'); if ($base.EndsWith('/api')) { $base = $base.Substring(0, $base.Length - 4) }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('public-client:public'))
    $form = "grant_type=password&username=$([uri]::EscapeDataString((Sec 'Datto-ApiKey').Trim()))&password=$([uri]::EscapeDataString((Sec 'Datto-ApiSecret').Trim()))"
    try {
        $tok = Invoke-RestMethod -Method POST -Uri "$base/auth/oauth/token" -Headers @{ Authorization = "Basic $basic"; Accept = 'application/json' } -Body $form -ContentType 'application/x-www-form-urlencoded'
        $dh = @{ Authorization = "Bearer $($tok.access_token)"; Accept = 'application/json' }
        function DGet { param([string]$Path) Invoke-RestMethod -Method GET -Uri "$base$Path" -Headers $dh }

        # Component
        $comps = @((DGet '/api/v2/account/components?max=250').components)
        $comp = $comps | Where-Object { $_.name -eq $item.component } | Select-Object -First 1
        if (-not $comp) { throw "The Datto RMM component '$($item.component)' isn't in the component library. Add it from the ComStore." }
        $steps.Add("Component: $($comp.name)")

        # Device (by hostname)
        $dev = $null; $page = 0
        $hits = @(); do { $resp = DGet "/api/v2/account/devices?max=250&page=$page"; $hits += @(@($resp.devices) | Where-Object { $_.hostname -ieq $device }); $page++ } while ($resp.pageDetails.nextPageUrl -and $page -lt 20)
        $dev = @($hits | Sort-Object @{ Expression = { [bool]$_.online }; Descending = $true }, @{ Expression = { [int64]$_.lastSeen }; Descending = $true }) | Select-Object -First 1
        if (-not $dev) { throw "There is no Datto RMM device named '$device'." }
        $steps.Add("Device: $($dev.hostname) at site $($dev.siteName), $(if ($dev.online) { 'online' } else { 'offline' })")
        $deviceUser = [string]$dev.lastLoggedInUser
        $same = Test-SameUser $deviceUser $userName $userEmail
        if ($same -eq $false) { $forSomeoneElse = $true; $ownerNote = "Requested for someone else's computer: $($dev.hostname) was last signed in to by $deviceUser, not by the requester ($userName). Check that this request was expected." }
        elseif ($null -eq $same -and $userName) { $ownerNote = "Datto RMM doesn't show who last signed in to $($dev.hostname), so it couldn't be checked against the requester." }
        if ($ownerNote) { $steps.Add($ownerNote) }

        if (-not $dev.online) {
            $status = 'offline'
            $msg = "$key was not installed on $($dev.hostname) because the computer is offline in Datto RMM. Turn it on and resubmit the request."
        }
        elseif (-not $confirm) {
            $status = 'preview'
            $msg = "Preview: would install $key on $($dev.hostname) ($($dev.siteName)) with the Datto RMM component '$($comp.name)'."
        }
        else {
            $vars = @(); foreach ($vn in $item.vars.Keys) { $vars += @{ name = $vn; value = [string]$item.vars[$vn] } }
            $body = @{ jobName = "Software request: $key$(if ($ticketId) { " (ticket $ticketId)" })"; jobComponent = @{ componentUid = $comp.uid; variables = $vars } } | ConvertTo-Json -Depth 6
            $job = Invoke-RestMethod -Method PUT -Uri "$base/api/v2/device/$($dev.uid)/quickjob" -Headers $dh -ContentType 'application/json' -Body $body
            $jobUid = [string](P (P $job 'job') 'uid'); if (-not $jobUid) { $jobUid = [string](P $job 'uid') }
            $steps.Add("Quick job started: $jobUid")

            # Wait for the result
            $deadline = (Get-Date).AddMinutes($waitMinutes); $done = $false
            while ((Get-Date) -lt $deadline -and -not $done) {
                Start-Sleep -Seconds 15
                try { $result = DGet "/api/v2/job/$jobUid/results/$($dev.uid)" } catch { $result = $null }
                $cr = @(P $result 'componentResults') | Select-Object -First 1
                $cs = [string](P $cr 'componentStatus')
                if ($cs -and $cs -notmatch '(?i)running|pending|scheduled|queued') { $done = $true }
            }
            $cr = @(P $result 'componentResults') | Select-Object -First 1; $cs = [string](P $cr 'componentStatus')
            if ($done -and $cs -match '(?i)success') { $status = 'success'; $msg = "$key was installed on $($dev.hostname) by Datto RMM." }
            elseif ($done) {
                $out = ''; try { $so = DGet "/api/v2/job/$jobUid/results/$($dev.uid)/stdout"; $out = [string](@($so) | ForEach-Object { $_.stdData }) } catch { }
                if ($out -match '(?is)currently installed copies of[^:]*:\s*\[1\]' -or $out -match '(?i)already installed|is already present') { $status = 'success'; $msg = "$key is already installed on $($dev.hostname), so there was nothing to do." }
                else { $status = 'failed'; $msg = "Datto RMM ran the $key install on $($dev.hostname), but it reported '$cs'. A technician will take a look." }
            }
            else { $status = 'running'; $msg = "The $key install on $($dev.hostname) has started in Datto RMM and is still running. Check the job in Datto RMM for the result." }
        }
    }
    catch { $status = 'error'; $msg = "No software was installed. $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })".Trim() }
}

# ---- Internal note on the request ticket (ConnectWise) ----
$noted = $false
if ($ticketId -match '^\d+$' -and [int64]$ticketId -gt 0 -and $status -ne 'preview') {
    try {
        $cwApiUrl = (Sec 'CW-ApiUrl').Trim().TrimEnd('/'); $pair = "{0}+{1}:{2}" -f (Sec 'CW-CompanyID').Trim(), (Sec 'CW-PublicKey').Trim(), (Sec 'CW-PrivateKey').Trim()
        $cwH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair)); clientId = (Sec 'CW-ClientId').Trim(); Accept = 'application/json' }
        try { $rawB = Invoke-WebRequest -Method Get -Uri "$cwApiUrl/service/boards?pageSize=1" -Headers $cwH; $mB = [regex]::Match([string]$rawB.Content, 'https://[^/"]+/[^/"]+/apis/3\.0'); if ($mB.Success) { $cwApiUrl = $mB.Value } } catch { }
        $note = "Software request (AutomationAI)`nRequested by: $userName$(if ($userEmail) { " ($userEmail)" })$(if ($forSomeoneElse) { "`n*** FOR SOMEONE ELSE'S COMPUTER ***" })`nSoftware: $(if ($key) { $key } else { $app })`nComputer: $device$(if ($deviceUser) { " (last signed in: $deviceUser)" })`nResult: $msg$(if ($ownerNote) { "`nOwner check: $ownerNote" })$(if ($jobUid) { "`nDatto RMM job: $jobUid" })"
        $nb = @{ text = $note; internalAnalysisFlag = $true; detailDescriptionFlag = $false; resolutionFlag = $false } | ConvertTo-Json
        try { $null = Invoke-WebRequest -Method Post -Uri "$cwApiUrl/service/tickets/$ticketId/notes" -Headers $cwH -ContentType 'application/json' -Body $nb -MaximumRedirection 0 -SkipHttpErrorCheck; $noted = $true } catch { if ($_.Exception.Message -match '(?i)redirect|current state of the object') { $noted = $true } else { throw } }
    } catch { $warnings.Add("Ticket note not added: $($_.Exception.Message)") }
}

# ---- Signal to the requester ----
$signaled = $false
if ($status -ne 'preview' -and $companyId -gt 0 -and $userId) {
    try {
        $crB = ''; if ($crSuffix) { $crB = (Sec "CloudRadial-BaseUrl-$crSuffix").Trim().TrimEnd('/'); $crPu = (Sec "CloudRadial-PublicKey-$crSuffix").Trim(); $crPr = (Sec "CloudRadial-PrivateKey-$crSuffix").Trim() }
        if (-not $crB) { $crB = (Sec 'CloudRadial-BaseUrl').Trim().TrimEnd('/'); $crPu = (Sec 'CloudRadial-PublicKey').Trim(); $crPr = (Sec 'CloudRadial-PrivateKey').Trim() }
        $crH = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($crPu):$($crPr)")); Accept = 'application/json' }
        $title = switch ($status) { 'success' { "$key is installed" } 'running' { "$key is installing" } 'offline' { "$key install is waiting" } default { "Your $(if ($key) { $key } else { 'software' }) request needs a technician" } }
        $sb = @{ companyIds = @($companyId); users = @($userId); priority = $(if ($status -eq 'success' -or $status -eq 'running') { 0 } else { 1 }); title = $title; body = $msg; expiresAt = (Get-Date).ToUniversalTime().AddDays(1).ToString('o'); dedupeKey = "swreq-$ticketId-$status" } | ConvertTo-Json -Depth 5
        $null = Invoke-RestMethod -Method Post -Uri "$crB/v2/signalmessage" -Headers $crH -ContentType 'application/json' -Body $sb; $signaled = $true
    } catch { $warnings.Add("Signal not sent: $($_.Exception.Message) $(if ($_.ErrorDetails) { $_.ErrorDetails.Message })") }
}

Set-NodeOutput ([ordered]@{
    status = $status; message = $msg; software = $key; device = $device; jobUid = $jobUid
    componentStatus = [string](P (@(P $result 'componentResults') | Select-Object -First 1) 'componentStatus')
    deviceLastUser = $deviceUser; forSomeoneElse = $forSomeoneElse; ownerCheck = $ownerNote
    ticketId = $ticketId; ticketNoted = $noted; signalSent = $signaled; steps = @($steps); warnings = @($warnings)
    catalog = @($catalog.Keys)
    internal_note = "Software request for $(if ($key) { $key } else { $app }) on $device by $userName ($companyName): $msg"
})
