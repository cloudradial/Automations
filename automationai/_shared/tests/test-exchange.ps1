# Strict-mode tests for _shared/exchange.ps1: REST sign-in and InvokeCommand, REST sign-in failure falling back to
# the ExchangeOnlineManagement module, neither available, cmdlet error messages, and -Confirm:$false in module mode.
. (Join-Path $PSScriptRoot 'mock.ps1')

$Login = 'https://login.microsoftonline.com/*'
$ExoCmd = 'https://outlook.office365.com/adminapi/beta/contoso-tenant-id/InvokeCommand'
$RestSec = @{ 'MicrosoftExchange-TenantId' = 'contoso-tenant-id'; 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-ClientSecret' = 'not-a-real-secret' }
$CertSec = @{ 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-CertificateThumbprint' = 'ABCDEF0123456789'; 'MicrosoftExchange-Organization' = 'contoso.onmicrosoft.com' }
$BothSec = @{}; foreach ($k in $RestSec.Keys) { $BothSec[$k] = $RestSec[$k] }; foreach ($k in $CertSec.Keys) { $BothSec[$k] = $CertSec[$k] }

# Module-mode mocks. $Exo.HasModule switches whether ExchangeOnlineManagement looks installed.
$Exo = @{ HasModule = $true; Connected = ''; Imported = $false; Cmdlets = (New-Object System.Collections.ArrayList) }
function Reset-Exo { param([bool]$HasModule = $true) $Exo.HasModule = $HasModule; $Exo.Connected = ''; $Exo.Imported = $false; $Exo.Cmdlets.Clear() }
function Get-Module { [CmdletBinding()] param([switch]$ListAvailable, [string[]]$Name) if ($Exo.HasModule) { return [pscustomobject]@{ Name = 'ExchangeOnlineManagement' } }; return $null }
function Import-Module { [CmdletBinding()] param([string]$Name) $Exo.Imported = $true }
function Connect-ExchangeOnline { [CmdletBinding()] param($AppId, $Organization, $CertificateThumbprint, $Certificate, [bool]$ShowBanner) $Exo.Connected = "$AppId|$Organization|$CertificateThumbprint" }
function Set-Mailbox { [CmdletBinding(SupportsShouldProcess = $true)] param($Identity, $Type, $HiddenFromAddressListsEnabled) $null = $Exo.Cmdlets.Add([pscustomobject]@{ Name = 'Set-Mailbox'; Identity = $Identity; Confirm = $(if ($PSBoundParameters.ContainsKey('Confirm')) { [bool]$PSBoundParameters['Confirm'] } else { $null }) }) }
function Get-Mailbox { [CmdletBinding()] param($Identity) $null = $Exo.Cmdlets.Add([pscustomobject]@{ Name = 'Get-Mailbox'; Identity = $Identity; Confirm = $null }); if ($Identity -like 'ghost*') { throw "The operation couldn't be performed because object '$Identity' couldn't be found on 'EXAMPLE01.PROD.OUTLOOK.COM'." }; return [pscustomobject]@{ PrimarySmtpAddress = $Identity; RecipientTypeDetails = 'UserMailbox' } }
function New-DistributionGroup { [CmdletBinding(SupportsShouldProcess = $true)] param($Name) throw "The proxy address ""SMTP:$Name@contoso.com"" is already being used by the proxy addresses or LegacyExchangeDN. Please choose another proxy address." }

$Token = { param($c, $n) if ($c.Uri -like $Login) { return [pscustomobject]@{ access_token = "exotok$n"; expires_in = 3599 } }; return $null }

# --- REST success ---
Reset-Exo
Reset-Mock $RestSec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    $b = $c.Body | ConvertFrom-Json
    switch ($b.CmdletInput.CmdletName) {
        'Get-Recipient' { if ($b.CmdletInput.Parameters.Identity -like 'ghost*') { New-HttpError 404 '{"error":{"code":"NotFound","message":"The operation couldn''t be performed because object ''ghost@contoso.com'' couldn''t be found."}}' }; return [pscustomobject]@{ value = @([pscustomobject]@{ PrimarySmtpAddress = 'sales@contoso.com'; RecipientTypeDetails = 'SharedMailbox' }) } }
        'Get-MailboxStatistics' { return [pscustomobject]@{ value = @([pscustomobject]@{ TotalItemSize = '1.5 GB (1,610,612,736 bytes)' }) } }
        'Get-Mailbox' { return [pscustomobject]@{ value = @([pscustomobject]@{ PrimarySmtpAddress = 'sam.doe@contoso.com' }) } }
        default { return [pscustomobject]@{ value = @() } }
    }
}
Invoke-WithLib @('exchange.ps1') {
    $ok = Connect-OfExchange
    $c = @(Get-Calls 'POST' $Login)[0]
    Check 'REST: signs in with the MicrosoftExchange-* secrets for the outlook.office365.com scope' ($ok -and $OfExo.Mode -eq 'rest' -and $OfExo.Connected -and $c.Uri -eq 'https://login.microsoftonline.com/contoso-tenant-id/oauth2/v2.0/token' -and $c.BodyObj.client_id -eq 'exo-app' -and $c.BodyObj.scope -eq 'https://outlook.office365.com/.default') (Show-Calls)
    Check 'REST: the module is not touched' (-not $Exo.Imported -and -not $Exo.Connected) ''
    $null = Connect-OfExchange
    Check 'REST: a second Connect-OfExchange signs in no more' (@(Get-Calls 'POST' $Login).Count -eq 1) (Show-Calls)
    $null = Invoke-OfExo 'Set-Mailbox' @{ Identity = 'sam.doe@contoso.com'; Type = 'Shared' }
    $c = Get-LastCall; $b = Read-Body $c
    Check 'REST: InvokeCommand body carries the cmdlet and parameters with the bearer token' ($c.Uri -eq $ExoCmd -and $b.CmdletInput.CmdletName -eq 'Set-Mailbox' -and $b.CmdletInput.Parameters.Type -eq 'Shared' -and $c.Headers.Authorization -eq 'Bearer exotok1') $c.Body
    Check 'REST: no Confirm parameter is sent' (-not ($c.Body -match 'Confirm')) $c.Body
    $r = Get-OfRecipient 'sales@contoso.com'
    Check 'Get-OfRecipient: returns the one recipient' ($r.RecipientTypeDetails -eq 'SharedMailbox') "$r"
    Check 'Get-OfRecipient: not found returns $null' ($null -eq (Get-OfRecipient 'ghost@contoso.com')) (Show-Calls)
    Check 'Get-OfMailbox: returns the mailbox' ((Get-OfMailbox 'sam.doe@contoso.com').PrimarySmtpAddress -eq 'sam.doe@contoso.com') ''
    $bytes = Get-OfMailboxBytes 'sam.doe@contoso.com'
    Check 'Get-OfMailboxBytes: reads the byte count out of TotalItemSize' ($bytes -eq 1610612736) "$bytes"
}

# --- REST retry and permission errors ---
Reset-Exo
Reset-Mock $RestSec.Clone() {
    param($c, $n)
    $t = & $Token $c $n; if ($t) { return $t }
    $b = $c.Body | ConvertFrom-Json
    $idp = $b.CmdletInput.Parameters.PSObject.Properties['Identity']; $id = $(if ($idp) { [string]$idp.Value } else { '' })
    if ($id -eq 'busy@contoso.com' -and $n -eq 1) { New-HttpError 429 }
    if ($b.CmdletInput.CmdletName -eq 'New-DistributionGroup') { New-HttpError 400 '{"error":{"code":"BadRequest","message":"The proxy address \"SMTP:sales@contoso.com\" is already being used."}}' }
    if ($b.CmdletInput.CmdletName -eq 'Set-Mailbox' -or $id -eq 'denied@contoso.com') { New-HttpError 403 '{"error":{"code":"Forbidden","message":"The user is not authorized to run Set-Mailbox."}}' }
    return [pscustomobject]@{ value = @([pscustomobject]@{ Name = 'ok' }) }
}
Invoke-WithLib @('exchange.ps1') {
    $null = Connect-OfExchange
    $r = @(Invoke-OfExo 'Get-Recipient' @{ Identity = 'busy@contoso.com' })
    Check 'REST: 429 backs off and retries' ($r.Count -eq 1 -and @($Mock.Sleeps).Count -eq 1 -and @(Get-Calls 'POST' $ExoCmd).Count -eq 2) "$(Show-Calls) sleeps=$(@($Mock.Sleeps) -join ',')"
    $m = Get-ThrowMessage { Invoke-OfExo 'New-DistributionGroup' @{ Name = 'Sales' } }
    Check 'REST: a cmdlet error is a plain sentence with the cmdlet, status and Exchange message' ($m -eq 'Exchange Online New-DistributionGroup failed (HTTP 400): The proxy address "SMTP:sales@contoso.com" is already being used.') $m
    $m = Get-ThrowMessage { Invoke-OfExo 'Set-Mailbox' @{ Identity = 'sam.doe@contoso.com' } }
    Check 'REST: 403 names Exchange.ManageAsApp and the Exchange Administrator role' ($m -match 'HTTP 403' -and $m -match 'Exchange\.ManageAsApp' -and $m -match 'Exchange Administrator role' -and $m -match 'not authorized to run Set-Mailbox') $m
    $m = Get-ThrowMessage { Get-OfRecipient 'denied@contoso.com' }
    Check 'REST: Get-OfRecipient rethrows an error that is not "not found"' ($m -match 'HTTP 403' -and $m -match 'Get-Recipient') $m
}

# --- REST sign-in fails, module fallback, -Confirm:$false ---
Reset-Exo
Reset-Mock $BothSec.Clone() { param($c, $n) if ($c.Uri -like $Login) { New-HttpError 401 '{"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided."}' }; return $null }
Invoke-WithLib @('exchange.ps1') {
    $ok = Connect-OfExchange
    Check 'fallback: REST sign-in failure falls back to the module with the certificate' ($ok -and $OfExo.Mode -eq 'module' -and $Exo.Imported -and $Exo.Connected -eq 'exo-app|contoso.onmicrosoft.com|ABCDEF0123456789' -and @(Get-Calls 'POST' $Login).Count -eq 1) "$($OfExo.Mode) $($Exo.Connected) $($OfExo.Reason)"
    Check 'fallback: Reason is cleared once connected' ($OfExo.Reason -eq '') $OfExo.Reason
    $null = Invoke-OfExo 'Set-Mailbox' @{ Identity = 'sam.doe@contoso.com'; Type = 'Shared' }
    $null = Invoke-OfExo 'Get-Mailbox' @{ Identity = 'sam.doe@contoso.com' }
    $set = @($Exo.Cmdlets | Where-Object { $_.Name -eq 'Set-Mailbox' })[0]
    $get = @($Exo.Cmdlets | Where-Object { $_.Name -eq 'Get-Mailbox' })[0]
    Check 'module: a changing cmdlet runs with -Confirm:$false' ($set.Identity -eq 'sam.doe@contoso.com' -and $set.Confirm -eq $false) "$($set.Confirm)"
    Check 'module: a Get-* cmdlet gets no -Confirm' ($null -eq $get.Confirm) "$($get.Confirm)"
    Check 'module: no InvokeCommand calls' (@(Get-Calls 'POST' 'https://outlook.office365.com/*').Count -eq 0) (Show-Calls)
    Check 'module: Get-OfMailbox not found returns $null' ($null -eq (Get-OfMailbox 'ghost@contoso.com')) ''
    $m = Get-ThrowMessage { Invoke-OfExo 'New-DistributionGroup' @{ Name = 'sales' } }
    Check 'module: a cmdlet error is a plain sentence with the cmdlet and Exchange message' ($m -like 'Exchange Online New-DistributionGroup failed: The proxy address "SMTP:sales@contoso.com" is already being used*') $m
}

# --- certificate only: the module, no REST attempt ---
Reset-Exo
Reset-Mock $CertSec.Clone()
Invoke-WithLib @('exchange.ps1') {
    $ok = Connect-OfExchange
    Check 'certificate only: connects through the module without a REST sign-in' ($ok -and $OfExo.Mode -eq 'module' -and $Mock.Calls.Count -eq 0) "$($OfExo.Mode) $(Show-Calls)"
}
Reset-Exo
Reset-Mock @{ 'MicrosoftExchange-ClientId' = 'exo-app'; 'MicrosoftExchange-CertificateThumbprint' = 'ABCDEF0123456789' }
Invoke-WithLib @('exchange.ps1') {
    $ok = Connect-OfExchange -Organization 'contoso.onmicrosoft.com'
    Check 'certificate only: -Organization stands in for the MicrosoftExchange-Organization secret' ($ok -and $Exo.Connected -eq 'exo-app|contoso.onmicrosoft.com|ABCDEF0123456789') $Exo.Connected
}

# --- neither available ---
Reset-Exo
Reset-Mock @{ 'MicrosoftExchange-TenantId' = 'contoso-tenant-id' }
Invoke-WithLib @('exchange.ps1') {
    $ok = Connect-OfExchange
    Check 'neither: no secrets returns $false and names the missing ones' (-not $ok -and -not $OfExo.Connected -and $OfExo.Reason -match 'MicrosoftExchange-ClientId' -and $OfExo.Reason -match 'MicrosoftExchange-ClientSecret' -and $OfExo.Reason -notmatch 'MicrosoftExchange-TenantId') $OfExo.Reason
    Check 'neither: a second Connect-OfExchange does not retry' (-not (Connect-OfExchange) -and $Mock.Calls.Count -eq 0) ''
    $m = Get-ThrowMessage { Invoke-OfExo 'Get-Mailbox' @{ Identity = 'sam.doe@contoso.com' } }
    Check 'neither: Invoke-OfExo says Exchange is not connected and why' ($m -match "isn't connected" -and $m -match 'MicrosoftExchange-ClientSecret') $m
}
Reset-Exo -HasModule $false
Reset-Mock $BothSec.Clone() { param($c, $n) if ($c.Uri -like $Login) { New-HttpError 400 '{"error":"unauthorized_client","error_description":"AADSTS700016: Application with identifier ''exo-app'' was not found in the directory."}' }; return $null }
Invoke-WithLib @('exchange.ps1') {
    $ok = Connect-OfExchange
    Check 'neither: REST failure and no module gives both reasons, sign-in error readable' (-not $ok -and $OfExo.Mode -eq '' -and $OfExo.Reason -match 'AADSTS700016: Application with identifier' -and $OfExo.Reason -notmatch 'unauthorized_client' -and $OfExo.Reason -match 'ExchangeOnlineManagement PowerShell module is not installed') $OfExo.Reason
}

Complete-Test
