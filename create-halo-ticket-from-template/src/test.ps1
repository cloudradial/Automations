# Strict-mode harness for Create a Halo Ticket from a Template.
# Runs the PowerShell step exactly as it is in create-halo-ticket-from-template.yml (shared psa.ps1 included),
# through & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest, with the runner Key Vault,
# Invoke-RestMethod, Get-NodeInput and Set-NodeOutput mocked. HaloPSA replies use the shapes read from a real
# instance on 2026-10-16/19. Placeholder data only (Contoso, Example MSP).
# Test variables start with T (a step variable of the same name would hide them; PowerShell names ignore case).
# Usage: pwsh -NoProfile -File create-halo-ticket-from-template/src/test.ps1
. (Join-Path $PSScriptRoot '..\..\_shared\tests\mock.ps1')

$node = (Get-Command node -ErrorAction Stop).Source
& $node (Join-Path $PSScriptRoot 'build.js') --check
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL the .yml is out of date: run node src/build.js' -ForegroundColor Red; exit 1 }
$yml = Join-Path $PSScriptRoot '..\create-halo-ticket-from-template.yml'
$js = "const y=(()=>{try{return require('js-yaml')}catch{return require(process.env.JS_YAML_PATH)}})();const d=y.load(require('fs').readFileSync(process.argv[1],'utf8'));const o={};for(const a of d.definition.activities){if(a.properties&&a.properties.script)o[a.id]=a.properties.script}o.webhook=String(d.definition.activities[0].properties.webhookEnabled);console.log(JSON.stringify(o))"
$Steps = (& $node -e $js $yml) | ConvertFrom-Json -AsHashtable
Check 'one step, shared psa.ps1 pasted, webhook ships disabled' ($Steps.Contains('create') -and $Steps['create'] -like '*function Connect-Psa*' -and $Steps['webhook'] -eq 'false')

$global:NodeIn = $null; $global:NodeOut = $null
function Get-NodeInput { param([string]$Name) return $global:NodeIn }
function Set-NodeOutput { param($o) $global:NodeOut = $o }
function Invoke-TRun {
    param($Body)
    $global:NodeIn = ($Body | ConvertTo-Json -Depth 8 | ConvertFrom-Json); $global:NodeOut = $null
    $err = ''; try { & ([scriptblock]::Create("Set-StrictMode -Version Latest`n" + $Steps['create'])) } catch { $err = [string]$_.Exception.Message }
    $o = $null; if ($null -ne $global:NodeOut) { $o = ($global:NodeOut | ConvertTo-Json -Depth 12 | ConvertFrom-Json) }
    return @{ out = $o; error = $err }
}

# ---- placeholder HaloPSA ----
$THalo = 'https://halo.example.com'
$TSecrets = @{ 'Halo-ApiUrl' = $THalo; 'Halo-ClientId' = 'cid'; 'Halo-ClientSecret' = 'csecret' }
$TH = @{ posts = (New-Object System.Collections.ArrayList); postFail = $false }
$TRouter = {
    param($c, $n)
    $u = [uri]::UnescapeDataString($c.Uri)
    if ($c.Method -eq 'POST' -and $u -eq "$THalo/auth/token") { return [pscustomobject]@{ access_token = 'tok' } }
    if ($c.Method -eq 'GET' -and $u -match '/api/Template\?') { return [pscustomobject]@{ page_no = 1; page_size = 50; record_count = 2; stdrequests = @([pscustomobject]@{ id = 1; name = 'New Starter Request' }, [pscustomobject]@{ id = 2; name = 'New Starter' }) } }
    if ($c.Method -eq 'GET' -and $u -match '/api/Template/1\?') { return [pscustomobject]@{ id = 1; name = 'New Starter Request'; tickettype_id = 30; priority_id = 3; status_id = 1; team = '1st Line Support'; category_1 = ''; details_html = '<p>New starter.</p>' } }
    if ($c.Method -eq 'GET' -and $u -match '/api/TicketType/30\?') { return [pscustomobject]@{ id = 30; name = 'New Starter Request'; fields = @([pscustomobject]@{ id = 1; fieldid = 0; groupid = 14; endusernew = 1; technew = 1 }, [pscustomobject]@{ id = 2; fieldid = 0; groupid = 15; endusernew = 1; technew = 1 }) } }
    if ($c.Method -eq 'GET' -and $u -match '/api/FieldGroup/14\?') { return [pscustomobject]@{ id = 14; fields = @([pscustomobject]@{ id = 71; fieldid = 101; endusernew = 3; technew = 3 }, [pscustomobject]@{ id = 72; fieldid = 102; endusernew = 1; technew = 1 }, [pscustomobject]@{ id = 73; fieldid = 103; endusernew = 1; technew = 1 }, [pscustomobject]@{ id = 74; fieldid = 104; endusernew = 1; technew = 1 }) } }
    if ($c.Method -eq 'GET' -and $u -match '/api/FieldGroup/15\?') { return [pscustomobject]@{ id = 15; fields = @([pscustomobject]@{ id = 75; fieldid = 150; endusernew = 3; technew = 3 }, [pscustomobject]@{ id = 76; fieldid = 105; endusernew = 3; technew = 3 }) } }
    if ($c.Method -eq 'GET' -and $u -match '/api/FieldInfo/(\d+)\?') {
        $TDefs = @{
            '101' = @{ id = 101; name = 'CFfirstName'; label = 'First Name'; type = 0 }
            '102' = @{ id = 102; name = 'CFhardwareRequired'; label = 'Hardware?'; type = 6 }
            '103' = @{ id = 103; name = 'CFperipherals'; label = 'Peripherals'; type = 3; values = @(@{ id = 11; name = 'Monitor' }, @{ id = 12; name = 'Webcam' }, @{ id = 13; name = 'Docking Station' }) }
            '104' = @{ id = 104; name = 'CFstartingDate'; label = 'Starting Date'; type = 4 }
            '105' = @{ id = 105; name = 'CFcostCentre'; label = 'Cost Centre'; type = 2; values = @(@{ id = 21; name = 'COSTCENTRE1' }, @{ id = 23; name = 'COSTCENTRE3' }) }
            '150' = @{ id = 150; name = 'deliveryaddress'; label = 'Delivery Address'; type = 0 }
        }
        if ($TDefs.Contains($Matches[1])) { return ($TDefs[$Matches[1]] | ConvertTo-Json -Depth 5 | ConvertFrom-Json) }
        New-HttpError 404 '{"message":"Not found"}'
    }
    if ($c.Method -eq 'GET' -and $u -eq "$THalo/api/Team") { return , @([pscustomobject]@{ id = 4; name = 'Service Desk' }, [pscustomobject]@{ id = 5; name = '1st Line Support' }) }
    if ($c.Method -eq 'GET' -and $u -match '/api/Users\?client_id=42&search=(.*)$') { $e = $Matches[1]; $rows = @(@([pscustomobject]@{ id = 9; name = 'Pat Example'; emailaddress = 'pat.example@contoso.com' }) | Where-Object { $_.emailaddress -eq $e }); return [pscustomobject]@{ record_count = $rows.Count; users = $rows } }
    if ($c.Method -eq 'POST' -and $u -eq "$THalo/api/Tickets") {
        if ($TH.postFail) { New-HttpError 400 '"First Name is mandatory\n"' }
        $null = $TH.posts.Add(@(Read-Body $c)[0]); return , @([pscustomobject]@{ id = 5001 })
    }
    return $null
}
function Reset-T { $TH.posts.Clear(); $TH.postFail = $false; Reset-Mock $TSecrets $TRouter }
function New-TForm {
    param([hashtable]$Answers, [string]$Subject = 'New Starter Request', $CompanyPsaId = 42, $UserPsaId = 7)
    $qs = @($Answers.Keys | ForEach-Object { @{ Id = $_; Label = $_; Value = $Answers[$_] } })
    return @{ User = @{ UserEmail = 'pat.example@contoso.com'; UserPsaId = $UserPsaId }; Company = @{ CompanyName = 'Contoso'; CompanyPsaId = $CompanyPsaId }; Ticket = @{ TicketId = 0; TicketSubject = $Subject; TicketDescription = 'First name: Pat'; Questions = $qs } }
}
$TFull = @{ haloTemplateId = '1'; CFfirstName = 'Pat'; CFhardwareRequired = 'true'; CFperipherals = '"Monitor", "Webcam"'; CFstartingDate = '2026-10-21'; CFcostCentre = 'COSTCENTRE3' }

# 1. A form submission creates the ticket with the template's values and every answer.
Reset-T
$r = Invoke-TRun (New-TForm $TFull)
$b = if ($TH.posts.Count) { $TH.posts[0] } else { $null }
Check 'form submission: success, ticket 5001' ($r.out.status -eq 'success' -and $r.out.ticket_id -eq '5001' -and $TH.posts.Count -eq 1) "$($r.error) $($r.out.message)"
Check 'template values on the ticket, team as team_id' ($b.tickettype_id -eq 30 -and $b.priority_id -eq 3 -and $b.status_id -eq 1 -and $b.team -eq '1st Line Support' -and $b.team_id -eq 5 -and $b.client_id -eq 42 -and $b.user_id -eq 7 -and -not $b.PSObject.Properties['category_1']) ($b | ConvertTo-Json -Depth 4 -Compress)
$TCf = @{}; foreach ($cf in @($b.customfields)) { $TCf[$cf.name] = $cf }
Check 'custom fields: text, checkbox, multi-select ids, single-select id, date' ($TCf['CFfirstName'].value -eq 'Pat' -and $TCf['CFfirstName'].id -eq 101 -and $TCf['CFhardwareRequired'].value -eq $true -and $TCf['CFperipherals'].value -eq '11,12' -and $TCf['CFcostCentre'].value -eq '23' -and $TCf['CFstartingDate'].value -eq '2026-10-21') (@($b.customfields) | ConvertTo-Json -Depth 3 -Compress)
Check 'a mandatory built-in field is a warning' ([bool](@($r.out.warnings) -match "built-in field 'Delivery Address'")) (@($r.out.warnings) -join ' | ')

# 2. A manual run (flat body) previews unless confirm is true.
Reset-T
$r = Invoke-TRun (@{ templateId = '1'; companyPsaId = '42'; userEmail = 'pat.example@contoso.com'; subject = 'New Starter Request'; fields = @{ CFfirstName = 'Pat'; CFcostCentre = 'COSTCENTRE1' } })
Check 'manual run: preview, nothing posted, user found by email' ($r.out.status -eq 'pending_confirmation' -and -not $TH.posts.Count -and $r.out.ticket.client_id -eq 42 -and $r.out.ticket.user_id -eq 9 -and -not $r.out.ticket.PSObject.Properties['reportedby']) "$($r.error) $($r.out.message)"
Reset-T
$r = Invoke-TRun (@{ templateId = '1'; companyPsaId = '42'; confirm = 'true'; fields = @{ CFfirstName = 'Pat'; CFcostCentre = 'COSTCENTRE1' } })
Check 'manual run with confirm: created, summary from the template' ($r.out.status -eq 'success' -and $TH.posts[0].summary -eq 'New Starter Request' -and $TH.posts[0].details -like '*New starter*') "$($r.error) $($r.out.message)"

Reset-T
$r = Invoke-TRun (@{ templateId = '1'; companyPsaId = '42'; userEmail = 'nobody@contoso.com'; fields = @{ CFfirstName = 'Pat'; CFcostCentre = 'COSTCENTRE1' } })
Check 'unknown email: reported by the email, with a warning' ($r.out.ticket.reportedby -eq 'nobody@contoso.com' -and -not $r.out.ticket.PSObject.Properties['user_id'] -and [bool](@($r.out.warnings) -match 'No single Halo user')) "$(@($r.out.warnings) -join ' | ')"

# 3. Unfilled tokens and missing mandatory answers stop before anything is created.
Reset-T
$r = Invoke-TRun (New-TForm @{ haloTemplateId = '1'; CFfirstName = '@CFfirstName'; CFcostCentre = 'COSTCENTRE3' })
Check 'unfilled token counts as missing: not sent, a warning names First Name, Halo decides' (-not @($TH.posts[0].customfields | Where-Object { $_.name -eq 'CFfirstName' }).Count -and [bool](@($r.out.warnings) -match 'First Name') -and $r.out.status -eq 'success') "$($r.out.status) $(@($r.out.warnings) -join ' | ')"
Reset-T
$r = Invoke-TRun (New-TForm @{ haloTemplateId = '1'; CFfirstName = 'Pat'; CFcostCentre = 'COSTCENTRE9' })
Check 'a list answer Halo does not have: warned and left out' (-not @($TH.posts[0].customfields | Where-Object { $_.name -eq 'CFcostCentre' }).Count -and [bool](@($r.out.warnings) -match 'COSTCENTRE9') -and [bool](@($r.out.warnings) -match 'Cost Centre')) "$($r.out.message) | $(@($r.out.warnings) -join ' | ')"

# 4. No template id: the form's subject finds the template, longest name first.
Reset-T
$r = Invoke-TRun (New-TForm @{ CFfirstName = 'Pat'; CFcostCentre = 'COSTCENTRE1' } -Subject 'New Starter Request - Pat Example')
Check 'template matched by name' ($r.out.status -eq 'success' -and [bool](@($r.out.actions) -match "Matched the form.*template 1 ")) "$($r.out.message) | $(@($r.out.actions) -join ' | ')"
Reset-T
$r = Invoke-TRun (New-TForm @{ CFfirstName = 'Pat' } -Subject 'Printer jammed')
Check 'no matching template: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -like "*No Halo template matches*") "$($r.out.message)"

# 5. Input checks.
$TBad = @{}; foreach ($k in $TFull.Keys) { $TBad[$k] = $TFull[$k] }; $TBad.haloTemplateId = 'abc'
Reset-T
$r = Invoke-TRun (New-TForm $TFull -CompanyPsaId 0)
Check 'no Halo client: incomplete, Halo not called' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*Halo client is missing*' -and -not @($Mock.Calls).Count) "$($r.out.message)"
Reset-T
$r = Invoke-TRun (New-TForm $TBad)
Check 'a non-number template id: incomplete' ($r.out.status -eq 'incomplete' -and $r.out.message -like '*haloTemplateId must be*') "$($r.out.message)"

# 6. Halo refuses the ticket: error with Halo's reason.
Reset-T
$TH.postFail = $true
$r = Invoke-TRun (New-TForm $TFull)
Check 'halo 400: error with the reason' ($r.out.status -eq 'error' -and $r.out.message -like '*mandatory*') "$($r.out.message)"

# 7. Missing secrets stop cleanly.
Reset-Mock @{} $TRouter
$r = Invoke-TRun (New-TForm $TFull)
Check 'no Halo secrets: error naming them' ($r.out.status -eq 'error' -and $r.out.message -like '*Halo-ApiUrl*') "$($r.out.message)"

Complete-Test
