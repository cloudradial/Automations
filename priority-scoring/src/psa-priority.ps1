# ---------- src/psa-priority.ps1: set a ticket's priority on six PSAs ----------
# Set-PsaPriority takes a level (critical, high, medium or low) and finds the PSA's own priority for it the
# same way _shared/psa.ps1's New-PsaTicket does ($PsaState.PriorityPatterns). A candidate to move into
# _shared/psa.ps1. Uses _shared/psa.ps1 (paste it first).
# Calls marked "Unverified" have not been proven by a live run; check them before the first live write.
# Returns the label that was set.
function Set-PsaPriority {
    param([string]$Id, [ValidateSet('critical', 'high', 'medium', 'low')][string]$Level)
    $c = Get-PsaConn
    $pats = $PsaState.PriorityPatterns[$Level]
    switch ($c.Psa) {
        'connectwise' {
            # The board's own priority by name. A role that can't list priorities still gets the board's priority
            # matrix through impact and urgency (severity), the way New-PsaTicket does it.
            # Unverified: patching priority, impact and severity on an existing ticket.
            $list = $null
            try { $list = @(Invoke-Psa GET '/service/priorities?pageSize=100') } catch { if ([string]$_.Exception.Message -notmatch '\(HTTP 40[13]\)') { throw } }
            $pr = $(if ($null -ne $list) { Select-PsaByLabel $list 'name' $pats } else { $null })
            if ($pr) {
                $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'priority'; value = @{ id = [int](Get-PsaProp $pr 'id') } })
                return [string](Get-PsaProp $pr 'name')
            }
            $iu = $PsaState.CwImpactUrgency[$Level]
            Add-PsaWarning "ConnectWise wouldn't list ticket priorities, so ticket $Id was set to impact $($iu[0]) and urgency $($iu[1]) and the board's priority matrix picked the priority. Give the API member's security role Inquire access to Service Desk priorities to set it by name."
            $null = Invoke-Psa PATCH "/service/tickets/$Id" @([ordered]@{ op = 'replace'; path = 'impact'; value = $iu[0] }, [ordered]@{ op = 'replace'; path = 'severity'; value = $iu[1] })
            return "impact $($iu[0]), urgency $($iu[1])"
        }
        'autotask' {
            $v = Select-PsaAtValue (Get-PsaAtPicklist 'Tickets' 'priority') $pats
            if ($null -eq $v) { throw "Autotask has no ticket priority that looks like '$Level'." }
            $null = Invoke-Psa PATCH '/Tickets' ([ordered]@{ id = [long]$Id; priority = [int]$v })
            $hit = @(Get-PsaAtPicklist 'Tickets' 'priority' | Where-Object { [string](Get-PsaProp $_ 'value') -eq [string]$v }) | Select-Object -First 1
            return [string](Get-PsaProp $hit 'label')
        }
        'halopsa' {
            # Unverified: Halo's out-of-box priority ids 1 to 4 are Critical to Low (as New-PsaTicket assumes).
            $pid1 = @{ critical = 1; high = 2; medium = 3; low = 4 }[$Level]
            $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; priority_id = $pid1 })
            return "priority $pid1"
        }
        'kaseyabms' {
            # Unverified: the priority lookup and patching PriorityId.
            $list = @(Get-PsaBmsList (Invoke-PsaRead '/system/lookup/priorities' 'read priorities' 'read service desk lookups'))
            $pr = Select-PsaByLabel $list 'Name' $pats
            if (-not $pr) { throw "Kaseya BMS has no priority that looks like '$Level'." }
            $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" @([ordered]@{ op = 'replace'; path = '/PriorityId'; value = [int](Get-PsaProp $pr 'Id') })
            return [string](Get-PsaProp $pr 'Name')
        }
        'syncro' {
            # Unverified: Syncro takes the priority as a label (as New-PsaTicket sends it).
            $label = @{ critical = '0 Urgent'; high = '1 High'; medium = '2 Normal'; low = '3 Low' }[$Level]
            $null = Invoke-Psa PUT "/tickets/$Id" @{ priority = $label }
            return $label
        }
        'zendesk' {
            $label = @{ critical = 'urgent'; high = 'high'; medium = 'normal'; low = 'low' }[$Level]
            $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ priority = $label } }
            return $label
        }
    }
}
# ---------- end src/psa-priority.ps1 ----------
