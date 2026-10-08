# ---------- outage-broadcast/src/psa-extra.ps1: PSA calls _shared/psa.ps1 doesn't have yet ----------
# Candidate to move into automationai/_shared/psa.ps1. Needs _shared/psa.ps1 pasted above it (Connect-Psa, Invoke-Psa).
# Edit this file, then run: node src/build.js
# None of these calls is in reference/build-kit/PSA.md yet. Each PSA branch says "Unverified" until a live run proves it.

# The company's primary contact as @{ name; email }, or $null when the PSA has none or can't say.
#   -CompanyId  the PSA's own company id (CloudRadial keeps it as the company's psaKey)
function Get-PsaPrimaryContact {
    param([string]$CompanyId)
    $c = Get-PsaConn
    if (Test-PsaBlank $CompanyId) { return $null }
    $name = ''; $email = ''
    switch ($c.Psa) {
        'connectwise' {
            # Unverified: the company's defaultContact, then the contact's default Email communication item.
            $co = Invoke-Psa GET "/company/companies/$CompanyId"
            $cid = Get-PsaPath $co 'defaultContact.id'
            if (Test-PsaBlank $cid) { return $null }
            $ct = Invoke-Psa GET "/company/contacts/$cid"
            $name = (@([string](Get-PsaProp $ct 'firstName'), [string](Get-PsaProp $ct 'lastName')) -join ' ').Trim()
            $items = @(Get-PsaProp $ct 'communicationItems' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'communicationType') -eq 'Email' })
            $pick = @($items | Where-Object { (Get-PsaProp $_ 'defaultFlag') -eq $true }) + $items | Select-Object -First 1
            if ($pick) { $email = [string](Get-PsaProp $pick 'value') }
        }
        'autotask' {
            # Unverified: Contacts query on companyID with primaryContact = true and isActive = 1.
            $s = @{ filter = @([ordered]@{ op = 'eq'; field = 'companyID'; value = [long]$CompanyId }, [ordered]@{ op = 'eq'; field = 'primaryContact'; value = $true }, [ordered]@{ op = 'eq'; field = 'isActive'; value = 1 }); MaxRecords = 5 }
            $hit = @(Get-PsaProp (Invoke-Psa GET "/Contacts/query?search=$(ConvertTo-PsaQuery ($s | ConvertTo-Json -Depth 6 -Compress))") 'items' | Where-Object { $null -ne $_ }) | Select-Object -First 1
            if (-not $hit) { return $null }
            $name = (@([string](Get-PsaProp $hit 'firstName'), [string](Get-PsaProp $hit 'lastName')) -join ' ').Trim()
            $email = [string](Get-PsaProp $hit 'emailAddress')
        }
        'halopsa' {
            # Unverified: GET /api/Users?client_id= and the user flagged as the primary contact.
            $r = Invoke-Psa GET "/Users?client_id=$CompanyId&count=100"
            $rows = @(Get-PsaProp $r 'users'); if (-not @($rows | Where-Object { $null -ne $_ }).Count -and $r -is [array]) { $rows = @($r) }
            $hit = @($rows | Where-Object { $null -ne $_ -and ((Get-PsaProp $_ 'isprimarycontact') -eq $true -or (Get-PsaProp $_ 'is_primary_contact') -eq $true) }) | Select-Object -First 1
            if (-not $hit) { return $null }
            $name = [string](Get-PsaProp $hit 'name')
            $email = [string](Get-PsaProp $hit 'emailaddress')
        }
        'kaseyabms' {
            # Unverified: the contact list filter name and the IsPrimary flag.
            $r = Invoke-Psa GET "/crm/contacts?Filter.AccountId=$CompanyId"
            $hit = @(Get-PsaProp $r 'Result' | Where-Object { $null -ne $_ -and [string](Get-PsaProp $_ 'AccountId') -eq [string]$CompanyId -and (Get-PsaProp $_ 'IsPrimary') -eq $true }) | Select-Object -First 1
            if (-not $hit) { return $null }
            $name = (@([string](Get-PsaProp $hit 'FirstName'), [string](Get-PsaProp $hit 'LastName')) -join ' ').Trim()
            $email = [string](Get-PsaProp $hit 'EmailAddress')
        }
        'syncro' {
            # Unverified: a Syncro customer carries its own main email and name.
            $cu = Get-PsaProp (Invoke-Psa GET "/customers/$CompanyId") 'customer'
            if ($null -eq $cu) { return $null }
            $name = (@([string](Get-PsaProp $cu 'firstname'), [string](Get-PsaProp $cu 'lastname')) -join ' ').Trim()
            $email = [string](Get-PsaProp $cu 'email')
        }
        'zendesk' {
            # Zendesk organizations have no primary contact, so there is no one to email.
            return $null
        }
    }
    if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $null }
    return @{ name = $name; email = $email.Trim() }
}
# ---------- end outage-broadcast/src/psa-extra.ps1 ----------
