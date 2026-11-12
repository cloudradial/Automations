# === NODE: Hand off to the portal setup agent ===
# Reads the create step's output and passes the agent only what it needs. Nothing is called here.
$ErrorActionPreference = 'Stop'
function Get-NcoProp { param($o, [string]$n) if ($null -eq $o) { return $null }; if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { return $o[$n] }; return $null }; $p = $o.PSObject.Properties[$n]; if ($p) { return $p.Value }; return $null }
$in = Get-NodeInput
if ($null -ne $in -and $null -eq (Get-NcoProp $in 'status') -and $null -ne (Get-NcoProp $in 'output')) { $in = Get-NcoProp $in 'output' }
$opt = Get-NcoProp $in 'inputs'
$status = [string](Get-NcoProp $in 'status')
$companyId = [int](Get-NcoProp $in 'company_id')
$confirm = [bool](Get-NcoProp $in 'confirm')
$skip = ''
if ($status -ne 'success' -and $status -ne 'pending_confirmation') { $skip = "The create step ended with status '$status', so portal setup was skipped." }
elseif (-not $confirm) { $skip = 'Preview only: nothing was created, so the portal user step was skipped.' }
elseif ($confirm -and $companyId -le 0) { $skip = 'No CloudRadial company id came back from the create step, so portal setup was skipped.' }
$psa = Get-NcoProp $in 'psa'
Set-NodeOutput ([ordered]@{
    skip = $skip
    confirm = $confirm
    companyId = $companyId
    companyName = [string](Get-NcoProp $opt 'company_name')
    primaryDomain = [string](Get-NcoProp $opt 'primary_domain')
    primaryContactName = [string](Get-NcoProp $opt 'primary_contact_name')
    primaryContactEmail = [string](Get-NcoProp $opt 'primary_contact_email')
    products = [string](Get-NcoProp $opt 'products')
    psaCompanyId = [string](Get-NcoProp $psa 'company_id')
    ticketId = [string](Get-NcoProp $in 'ticket_id')
    createMessage = [string](Get-NcoProp $in 'message')
})