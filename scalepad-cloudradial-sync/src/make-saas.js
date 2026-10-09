// Generates 2d-saas.ps1 from 2b-assets.ps1: same flexible-asset machinery, SaaS source and fields.
const fs = require('fs'); const d = __dirname + '/';
let s = fs.readFileSync(d + '2b-assets.ps1', 'utf8').replace(/\r\n/g, '\n');
function cut(from, to, repl) { const i = s.indexOf(from); const j = s.indexOf(to, i); if (i < 0 || j < 0) throw new Error('bounds ' + from.slice(0, 40)); s = s.slice(0, i) + repl + s.slice(j); }
function rep(a, b) { if (!s.includes(a)) throw new Error('missing ' + a.slice(0, 60)); s = s.split(a).join(b); }

cut('# =====================================================================\n# Step 3', '$phase = ', `# =====================================================================
# SaaS subscriptions -> CloudRadial flexible asset type "SaaS"
#   CloudRadial's software records (endpointapplication) always belong to a
#   device, and its API has no SaaS or licence route, so ScalePad SaaS assets
#   (Microsoft 365, Google Workspace, ... with seats and terms) become rows of
#   a flexible asset type named "SaaS". Matched on the ScalePad SaaS id, so
#   re-runs update rather than duplicate.
# =====================================================================
`);
rep(`$phase = 'assets'`, `$phase = 'saas'`);
cut('$FieldDefs = @(', 'function ConvertTo-NameKey', `$FieldDefs = @(
    @{ name = 'Name'; kind = 'Text'; order = 1; useForTitle = $true; showInList = $false; required = $true },   # shown as the NAME column already
    @{ name = 'Vendor'; kind = 'Text'; order = 2; showInList = $true },
    @{ name = 'SKU'; kind = 'Text'; order = 3 },
    @{ name = 'Category'; kind = 'Text'; order = 4 },
    @{ name = 'Status'; kind = 'Text'; order = 5; showInList = $true },
    @{ name = 'Licenses'; kind = 'Number'; order = 6; showInList = $true },
    @{ name = 'Assigned'; kind = 'Number'; order = 7; showInList = $true },
    @{ name = 'Renewal Date'; kind = 'Date'; order = 8; showInList = $true },
    @{ name = 'Term Start'; kind = 'Date'; order = 9 },
    @{ name = 'Auto Renew'; kind = 'Text'; order = 10 },
    @{ name = 'Billing'; kind = 'Text'; order = 11 },
    @{ name = 'Provider'; kind = 'Text'; order = 12 },
    @{ name = 'Tenant Domain'; kind = 'Text'; order = 13 },
    @{ name = 'ScalePad ID'; kind = 'Text'; order = 14; hint = 'Used by the ScalePad to CloudRadial Sync to match this row. Do not edit.' }
)
`);
rep(`$counts = [ordered]@{ scalePadAssets = 0; byType = [ordered]@{}; noSerialDevices = 0; typeCreated`, `$counts = [ordered]@{ scalePadAssets = 0; typeCreated`);
cut(`    $typeName = [string](Get-P $settings 'flexibleAssetTypeName' 'ScalePad Assets')`, `    $counts.scalePadAssets = $rows.Count`, `    $typeName = [string](Get-P $settings 'saasTypeName' 'SaaS')
    $saas = @(Get-SpAll '/core/v1/assets/saas' @{ 'filter[client.id]' = "eq:$spClientId" })
    $rows = New-Object System.Collections.ArrayList
    foreach ($a in $saas) {
        $sub = @(Get-P $a 'subscriptions' @()) | Select-Object -First 1
        $auto = Get-P $a 'term.is_auto_renewed' (Get-P $sub 'term.is_auto_renewed')
        $vals = [ordered]@{
            'Name'          = [string](Get-P $a 'product.name' (Get-P $sub 'friendly_name' ''))
            'Vendor'        = [string](Get-P $a 'product.manufacturer.name' '')
            'SKU'           = $(if (([string](Get-P $a 'product.manufacturer_sku.name' '')) -ne ([string](Get-P $a 'product.name' ''))) { [string](Get-P $a 'product.manufacturer_sku.name' '') } else { '' })
            'Category'      = [string](Get-P $a 'product.category' '')
            'Status'        = [string](Get-P $a 'status' '')
            'Licenses'      = [string](Get-P $a 'pool.capacity' (Get-P $sub 'license_count' ''))
            'Assigned'      = [string](Get-P $a 'pool.utilized' '')
            'Renewal Date'  = Format-Day (Get-P $a 'term.ends_at' (Get-P $sub 'term.ends_at'))
            'Term Start'    = Format-Day (Get-P $a 'term.starts_at' (Get-P $sub 'term.starts_at'))
            'Auto Renew'    = $(if ($null -eq $auto) { '' } elseif ($auto -eq $true) { 'Yes' } else { 'No' })
            'Billing'       = [string](Get-P $sub 'billing_cycle_name' '')
            'Provider'      = [string](Get-P $sub 'provider_name' '')
            'Tenant Domain' = [string](Get-P $a 'tenant_domain' '')
            'ScalePad ID'   = [string](Get-P $a 'id')
        }
        if (Test-Blank $vals['Name']) { $vals['Name'] = "SaaS $($vals['ScalePad ID'])" }
        $null = $rows.Add($vals)
    }
`);
rep(`description = 'Hardware from ScalePad Lifecycle Manager that is not an endpoint: network, mobile and imaging devices, and devices without a serial number. Kept current by the ScalePad to CloudRadial Sync.'; icon = 'router'`, `description = 'SaaS subscriptions from ScalePad (product, vendor, seats, term). Kept current by the ScalePad to CloudRadial Sync.'; icon = 'cloud'`);
rep(`$serialKey = $keyOf['Serial Number']`, `$serialKey = 'no-serial-field'`);
const i = s.lastIndexOf('Set-NodeOutput @{');
s = s.slice(0, i) + `Set-NodeOutput @{ status = 'ok'; message = "SaaS: $($c.scalePadAssets) ScalePad SaaS subscriptions, $(if ($apply) { "$($c.created) created, $($c.updated) updated" } else { "$($c.toCreate) to create, $($c.toUpdate) to update" }), $($c.unchanged) unchanged, $($c.errors) errors."; ctx = $ctx }\n`;
if (/noSerialDevices|byType|lifeBySerial/.test(s)) throw new Error('hardware leftovers: ' + (s.match(/noSerialDevices|byType|lifeBySerial/) || [])[0]);
fs.writeFileSync(d + '2d-saas.ps1', s);
console.log('2d-saas.ps1', s.length);
