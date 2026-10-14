# ---------- src/psa-categories.ps1: a ticket's category fields on six PSAs ----------
# Up to three levels, each PSA in its own words:
#   ConnectWise  type > subtype > item (the ticket's board decides which ones exist)
#   Autotask     issue type > sub-issue type
#   HaloPSA      category (category_1)
#   Kaseya BMS   issue type > sub-issue type
#   Syncro       issue type (problem_type)
#   Zendesk      type (question, incident, problem, task)
# A candidate to move into _shared/psa-tickets.ps1. Uses _shared/psa.ps1 (paste it first).
# Calls marked "Unverified" have not been proven by a live run; check them before the first live write.
$CatState = @{
    Labels   = @{
        connectwise = @('type', 'subtype', 'item'); autotask = @('issue type', 'sub-issue type'); halopsa = @('category')
        kaseyabms = @('issue type', 'sub-issue type'); syncro = @('issue type'); zendesk = @('type')
    }
    MaxNodes = 400
}
# A level counts as blank when it is empty or one of the PSAs' "not set yet" names.
function Test-CatBlank { param($v) $s = ([string]$v).Trim(); return (-not $s -or $s -match '^(?i)(unclassified|uncategori[sz]ed|unknown|none|n/?a|not set|-)$') }
function New-CatNode { param([string]$Name, [string]$Id = '') return [ordered]@{ name = $Name; id = $Id; children = (New-Object System.Collections.ArrayList) } }
function Find-CatChild { param($List, [string]$Name) foreach ($n in @($List)) { if ($null -ne $n -and [string]$n.name -ieq $Name) { return $n } }; return $null }
function Get-CatNodeCount { param($List) $c = 0; foreach ($n in @($List)) { if ($null -eq $n) { continue }; $c += 1 + (Get-CatNodeCount $n.children) }; return $c }
# Drops the deepest level when the tree is too big to hand to the AI step, and says so.
function Limit-CatTree {
    param($Tree, [string[]]$Labels)
    if ((Get-CatNodeCount $Tree) -le $CatState.MaxNodes -or $Labels.Count -lt 3) { return }
    foreach ($a in @($Tree)) { foreach ($b in @($a.children)) { $b.children.Clear() } }
    Add-PsaWarning "This board has too many $($Labels[2]) values to choose from, so only the $($Labels[0]) and $($Labels[1]) were considered."
}

# Returns @{ labels; current (one @{name; id} per level); options (a tree of @{name; id; children}); boardId }.
function Get-PsaCategoryState {
    param([string]$Id, $Raw)
    $c = Get-PsaConn
    $labels = @($CatState.Labels[$c.Psa])
    $current = New-Object System.Collections.ArrayList
    $tree = New-Object System.Collections.ArrayList
    $boardId = ''
    switch ($c.Psa) {
        'connectwise' {
            $boardId = [string](Get-PsaPath $Raw 'board.id')
            if (Test-PsaBlank $boardId) { throw "ConnectWise ticket $Id has no board, so its types can't be read." }
            foreach ($f in @('type', 'subType', 'item')) { $null = $current.Add([ordered]@{ name = [string](Get-PsaPath $Raw "$f.name"); id = [string](Get-PsaPath $Raw "$f.id") }) }
            $need = 'read service board types, subtypes and items'
            # Unverified: the board's allowed type, subtype and item combinations.
            $assoc = @()
            try { $assoc = @(Invoke-PsaRead "/service/boards/$boardId/typeSubTypeItemAssociations?pageSize=1000" 'read the board''s type, subtype and item combinations' $need | Where-Object { $null -ne $_ }) }
            catch { if ([string]$_.Exception.Message -match '\(HTTP 403\)') { throw }; $assoc = @() }
            if ($assoc.Count) {
                foreach ($a in $assoc) {
                    $tn = [string](Get-PsaPath $a 'type.name'); if (-not $tn) { continue }
                    $t = Find-CatChild $tree $tn; if ($null -eq $t) { $t = New-CatNode $tn ([string](Get-PsaPath $a 'type.id')); $null = $tree.Add($t) }
                    $sn = [string](Get-PsaPath $a 'subType.name'); if (-not $sn) { continue }
                    $s = Find-CatChild $t.children $sn; if ($null -eq $s) { $s = New-CatNode $sn ([string](Get-PsaPath $a 'subType.id')); $null = $t.children.Add($s) }
                    $iname = [string](Get-PsaPath $a 'item.name'); if (-not $iname) { continue }
                    if ($null -eq (Find-CatChild $s.children $iname)) { $null = $s.children.Add((New-CatNode $iname ([string](Get-PsaPath $a 'item.id')))) }
                }
            }
            else {
                # The types, subtypes and items lists, as the ConnectWise extension reads them. A subtype's
                # typeAssociationIds says which types it belongs to; without combinations, every item is offered.
                $types = @(Invoke-PsaRead "/service/boards/$boardId/types?pageSize=200" 'read the board''s types' $need | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactiveFlag') -ne $true })
                $subs = @(); $items = @()
                try { $subs = @(Invoke-PsaRead "/service/boards/$boardId/subtypes?pageSize=200" 'read the board''s subtypes' $need | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactiveFlag') -ne $true }) } catch { Add-PsaWarning "ConnectWise wouldn't list the board's subtypes, so only types were considered: $($_.Exception.Message)" }
                # Unverified: the board's items list.
                try { $items = @(Invoke-PsaRead "/service/boards/$boardId/items?pageSize=200" 'read the board''s items' $need | Where-Object { $null -ne $_ -and (Get-PsaProp $_ 'inactiveFlag') -ne $true }) } catch { $items = @() }
                foreach ($ty in $types) {
                    $t = New-CatNode ([string](Get-PsaProp $ty 'name')) ([string](Get-PsaProp $ty 'id')); $null = $tree.Add($t)
                    foreach ($su in $subs) {
                        $assocIds = @(Get-PsaProp $su 'typeAssociationIds' | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
                        if ($assocIds.Count -and $assocIds -notcontains $t.id) { continue }
                        $s = New-CatNode ([string](Get-PsaProp $su 'name')) ([string](Get-PsaProp $su 'id')); $null = $t.children.Add($s)
                        foreach ($it in $items) { $null = $s.children.Add((New-CatNode ([string](Get-PsaProp $it 'name')) ([string](Get-PsaProp $it 'id')))) }
                    }
                }
            }
            Limit-CatTree $tree $labels
        }
        'autotask' {
            # The issue type and sub-issue type picklists, matched on their labels (they differ per tenant).
            $issues = @(Get-PsaAtPicklist 'Tickets' 'issueType')
            $subs = @(Get-PsaAtPicklist 'Tickets' 'subIssueType')
            foreach ($i in $issues) {
                $t = New-CatNode ([string](Get-PsaProp $i 'label')) ([string](Get-PsaProp $i 'value')); $null = $tree.Add($t)
                foreach ($s in $subs) { if ([string](Get-PsaProp $s 'parentValue') -eq $t.id) { $null = $t.children.Add((New-CatNode ([string](Get-PsaProp $s 'label')) ([string](Get-PsaProp $s 'value')))) } }
            }
            foreach ($pair in @(@('issueType', $issues), @('subIssueType', $subs))) {
                $v = [string](Get-PsaProp $Raw $pair[0]); $hit = @($pair[1] | Where-Object { [string](Get-PsaProp $_ 'value') -eq $v }) | Select-Object -First 1
                $null = $current.Add([ordered]@{ name = $(if ($hit) { [string](Get-PsaProp $hit 'label') } else { '' }); id = $v })
            }
        }
        'halopsa' {
            # Unverified: GET /Category?type_id=1 lists the ticket categories; the ticket keeps the chosen value in category_1.
            $rows = @(Invoke-PsaRead '/Category?type_id=1' 'read ticket categories' 'read ticket categories' | Where-Object { $null -ne $_ })
            foreach ($r in $rows) { $v = [string](Get-PsaProp $r 'value'); if ($v -and $null -eq (Find-CatChild $tree $v)) { $null = $tree.Add((New-CatNode $v ([string](Get-PsaProp $r 'id')))) } }
            $null = $current.Add([ordered]@{ name = [string](Get-PsaProp $Raw 'category_1'); id = '' })
        }
        'kaseyabms' {
            # Unverified: the issue type and sub-issue type lookups, and the ticket's IssueTypeId / SubIssueTypeId.
            $issues = @(Get-PsaBmsList (Invoke-PsaRead '/system/lookup/issuetypes' 'read issue types' 'read service desk lookups'))
            foreach ($i in $issues) {
                $t = New-CatNode ([string](Get-PsaProp $i 'Name')) ([string](Get-PsaProp $i 'Id')); $null = $tree.Add($t)
                $subs = @()
                try { $subs = @(Get-PsaBmsList (Invoke-PsaRead "/system/lookup/subissuetypes/$($t.id)" 'read sub-issue types' 'read service desk lookups')) } catch { $subs = @() }
                foreach ($s in $subs) { $null = $t.children.Add((New-CatNode ([string](Get-PsaProp $s 'Name')) ([string](Get-PsaProp $s 'Id')))) }
            }
            foreach ($pair in @(@('IssueTypeId', 'IssueTypeName'), @('SubIssueTypeId', 'SubIssueTypeName'))) {
                $null = $current.Add([ordered]@{ name = [string](Get-PsaProp $Raw $pair[1]); id = [string](Get-PsaProp $Raw $pair[0]) })
            }
            # A name the ticket didn't carry is looked up from the lists.
            if (-not $current[0].name -and $current[0].id) { $hit = @($tree | Where-Object { $_.id -eq $current[0].id }) | Select-Object -First 1; if ($hit) { $current[0].name = $hit.name; if ($current[1].id) { $s = @($hit.children | Where-Object { $_.id -eq $current[1].id }) | Select-Object -First 1; if ($s) { $current[1].name = $s.name } } } }
        }
        'syncro' {
            # Unverified: GET /tickets/settings lists the issue types (problem_types).
            $set = Invoke-PsaRead '/tickets/settings' 'read ticket settings' 'read ticket settings'
            foreach ($p in @(Get-PsaProp $set 'problem_types' | Where-Object { $null -ne $_ })) { $n = [string]$p; if ($n -and $null -eq (Find-CatChild $tree $n)) { $null = $tree.Add((New-CatNode $n)) } }
            $null = $current.Add([ordered]@{ name = [string](Get-PsaProp $Raw 'problem_type'); id = '' })
        }
        'zendesk' {
            foreach ($n in @('question', 'incident', 'problem', 'task')) { $null = $tree.Add((New-CatNode $n)) }
            $null = $current.Add([ordered]@{ name = [string](Get-PsaProp $Raw 'type'); id = '' })
        }
    }
    return [ordered]@{ labels = $labels; current = @($current); options = @($tree); boardId = $boardId }
}

# Sets the chosen levels. $Picks holds one name per level ('' = leave that level alone); every name
# must already be in $State.options under the levels above it. Returns plain sentences for what was set.
function Set-PsaCategory {
    param([string]$Id, $State, [string[]]$Picks)
    $c = Get-PsaConn
    $labels = @($State.labels)
    # The node for each picked level, following the path from the top (current values for fixed levels).
    $nodes = @(); $list = @($State.options)
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $name = $(if ($i -lt $Picks.Count -and $Picks[$i]) { $Picks[$i] } else { [string]$State.current[$i].name })
        if (Test-CatBlank $name) { break }
        $n = Find-CatChild $list $name
        if ($null -eq $n) { throw "'$name' isn't a $($labels[$i]) here, so nothing was set." }
        $nodes += , $n; $list = @($n.children)
    }
    $set = @()
    for ($i = 0; $i -lt $nodes.Count; $i++) { if ($i -lt $Picks.Count -and $Picks[$i]) { $set += , @($i, $nodes[$i]) } }
    if (-not $set.Count) { return @() }
    switch ($c.Psa) {
        'connectwise' {
            $paths = @('type', 'subType', 'item')
            $ops = @($set | ForEach-Object { [ordered]@{ op = 'replace'; path = $paths[$_[0]]; value = @{ id = [int]$_[1].id } } })
            $null = Invoke-Psa PATCH "/service/tickets/$Id" $ops
        }
        'autotask' {
            $b = [ordered]@{ id = [long]$Id }
            foreach ($s in $set) { $b[@('issueType', 'subIssueType')[$s[0]]] = [int]$s[1].id }
            $null = Invoke-Psa PATCH '/Tickets' $b
        }
        'halopsa' { $null = Invoke-Psa POST '/Tickets' @([ordered]@{ id = [long]$Id; category_1 = [string]$set[0][1].name }) }
        'kaseyabms' {
            $ops = @($set | ForEach-Object { [ordered]@{ op = 'replace'; path = @('/IssueTypeId', '/SubIssueTypeId')[$_[0]]; value = [int]$_[1].id } })
            $null = Invoke-Psa PATCH "/servicedesk/tickets/$Id" $ops
        }
        'syncro' { $null = Invoke-Psa PUT "/tickets/$Id" @{ problem_type = [string]$set[0][1].name } }
        'zendesk' { $null = Invoke-Psa PUT "/tickets/$Id" @{ ticket = @{ type = [string]$set[0][1].name } } }
    }
    return @($set | ForEach-Object { "$($labels[$_[0]]) '$($_[1].name)'" })
}
# ---------- end src/psa-categories.ps1 ----------
