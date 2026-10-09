<#
.SYNOPSIS
    Pull Microsoft Secure Score from Graph API and generate a CloudRadial Assessment import file.

.DESCRIPTION
    Authenticates to Microsoft Graph using client credentials (app registration),
    retrieves Secure Score control profiles and current scores for a tenant, maps
    them to the CloudRadial Assessment import template format, and exports a
    ready-to-import .xlsx file.

    This is the automated alternative to manually exporting Secure Score data from
    the CloudRadial portal — no browser, no downloads, just run the script.

    Requires an Azure AD app registration with the SecurityEvents.Read.All
    application permission and admin consent granted.

    Requires the ImportExcel PowerShell module. If not installed, the script will
    attempt to install it automatically for the current user.

.PARAMETER TenantId
    Mandatory. The Azure AD tenant ID (GUID) to pull Secure Scores from. For
    multi-tenant scenarios, this is the client tenant ID you have delegated
    access to.

.PARAMETER ClientId
    Mandatory. The Application (client) ID from your Azure AD app registration.

.PARAMETER ClientSecret
    Optional. The client secret for authentication. If not provided, the script
    checks the GRAPH_CLIENT_SECRET environment variable, then prompts interactively.

.PARAMETER OutputFile
    Optional. Path for the generated CloudRadial Assessment import .xlsx file.
    Defaults to "Assessment-SecureScore-<TenantId>-<date>.xlsx" in the current
    directory.

.PARAMETER AssessmentName
    Optional. Name used in the Checklist column to identify this assessment group.
    Defaults to "Microsoft Secure Score".

.PARAMETER WhatIf
    Preview the conversion without writing an output file. Shows what would be
    generated, including category breakdown and compliance summary.

.EXAMPLE
    PS> .\Import-SecureScoreAssessment.ps1 -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-1234-abcd-123456789012"

.EXAMPLE
    PS> .\Import-SecureScoreAssessment.ps1 -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-1234-abcd-123456789012" -WhatIf

.EXAMPLE
    PS> .\Import-SecureScoreAssessment.ps1 -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-1234-abcd-123456789012" `
        -AssessmentName "Contoso Q2 2026 Security Review" `
        -OutputFile "Contoso-Assessment.xlsx"

.NOTES
    Author:  Nick Westgate
    Version: 1.0
    Date:    2026-05-27
    Requires: ImportExcel module (auto-installed if missing)
    Requires: Azure AD app with SecurityEvents.Read.All (Application) permission
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TenantId,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile,

    [Parameter(Mandatory = $false)]
    [string]$AssessmentName = "Microsoft Secure Score",

    [Parameter(Mandatory = $false)]
    [int]$MaxRetries = 3,

    [switch]$WhatIf
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# TLS 1.2+
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13

$graphBaseUri = "https://graph.microsoft.com/v1.0"

$categoryOrder = @{
    'Identity'       = 1
    'Device'         = 2
    'Apps'           = 3
    'Data'           = 4
    'Infrastructure' = 5
}

$templateColumns = @(
    'Partner Notes', 'Monthly Unit Cost', 'Project Unit Cost',
    'Psa Board', 'Psa Item', 'Psa Status', 'Psa Category', 'Psa Sub Type',
    'Psa Type', 'Psa Priority', 'Psa Source', 'Psa Estimated Time',
    'Email List', 'Teams Webhook', 'Slack Webhook', 'Flow Webhook',
    'Json Webhook', 'Script', 'Checklist', 'Category', 'Question', 'Order',
    'Explanation', 'Type', 'Answer', 'Text Answer', 'Responses',
    'Is Flagged', 'Notes', 'Evaluation', 'Remediation Summary', 'Remediation',
    'Reference', 'Monthly Units', 'Monthly Unit Price', 'Project Units',
    'Project Unit Price', 'Control Type', 'Likelihood', 'Risk', 'Risk Cost',
    'Risk Impact', 'Owner', 'Updated by', 'Update Key', 'Content Update Key',
    'Note Compliant', 'Note Partially Compliant', 'Note NA', 'Note Missing',
    'Note Not Compliant'
)

# ============================================================================
# Helper Functions
# ============================================================================

function Confirm-ImportExcelModule {
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Host "ImportExcel module not found. Installing for current user..." -ForegroundColor Yellow
        try {
            Install-Module ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to install ImportExcel. Run 'Install-Module ImportExcel -Scope CurrentUser' manually."
            exit 1
        }
    }
    Import-Module ImportExcel -ErrorAction Stop
}

function Get-ClientSecret {
    if ($script:ClientSecret) { return $script:ClientSecret }

    $envSecret = $env:GRAPH_CLIENT_SECRET
    if ($envSecret) {
        Write-Host "Using client secret from GRAPH_CLIENT_SECRET environment variable." -ForegroundColor Cyan
        return $envSecret
    }

    Write-Host "No client secret provided via parameter or environment variable." -ForegroundColor Yellow
    $secureSecret = Read-Host "Enter the client secret for app $ClientId" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Get-GraphAccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret
    )

    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        Write-Error "Failed to authenticate to Microsoft Graph. Check your TenantId, ClientId, and ClientSecret.`n$($_.Exception.Message)"
        exit 1
    }
}

function Invoke-GraphRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
    )

    $headers = @{ Authorization = "Bearer $AccessToken" }

    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__

            if ($statusCode -eq 429) {
                $retryAfter = 30
                $retryHeader = $_.Exception.Response.Headers | Where-Object { $_.Key -eq "Retry-After" }
                if ($retryHeader) { $retryAfter = [int]$retryHeader.Value[0] }
                Write-Host "Rate limited (429). Waiting $retryAfter seconds... (attempt $attempt/$MaxRetries)" -ForegroundColor Yellow
                Start-Sleep -Seconds $retryAfter
                continue
            }

            if ($statusCode -eq 401) {
                Write-Error "Unauthorized (401). Check that your app has SecurityEvents.Read.All permission and admin consent is granted."
                exit 1
            }

            if ($statusCode -eq 403) {
                Write-Error "Forbidden (403). The app does not have sufficient permissions for this tenant. Ensure SecurityEvents.Read.All is granted."
                exit 1
            }

            if ($attempt -eq $MaxRetries) {
                Write-Error "Graph API request failed after $MaxRetries attempts: $($_.Exception.Message)"
                exit 1
            }

            $backoff = [math]::Pow(2, $attempt)
            Write-Host "Request failed (attempt $attempt/$MaxRetries). Retrying in $backoff seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $backoff
        }
    }
}

function Get-AllGraphPages {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$AccessToken
    )

    $allResults = @()
    $currentUri = $Uri

    while ($currentUri) {
        $response = Invoke-GraphRequest -Uri $currentUri -AccessToken $AccessToken -MaxRetries $script:MaxRetries
        if ($response.value) {
            $allResults += $response.value
        }
        $currentUri = $response.'@odata.nextLink'
    }

    return $allResults
}

function ConvertTo-AssessmentRow {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Control,

        [Parameter(Mandatory = $true)]
        [int]$Order,

        [Parameter(Mandatory = $true)]
        [double]$CurrentScore,

        [Parameter(Mandatory = $true)]
        [double]$MaxScore,

        [Parameter(Mandatory = $true)]
        [double]$TotalMaxScore
    )

    $isCompliant = ($CurrentScore -ge $MaxScore) -and ($MaxScore -gt 0)
    $answer      = if ($isCompliant) { 2 } else { -2 }
    $textAnswer  = if ($isCompliant) { "Compliant" } else { "Not compliant" }
    $isFlagged   = if ($isCompliant) { "No" } else { "Yes" }

    $scorePercent = if ($TotalMaxScore -gt 0) { [math]::Round(($MaxScore / $TotalMaxScore) * 100, 2) } else { 0 }

    # Risk matrix values (numeric scales per CloudRadial import spec)
    if (-not $isCompliant -and $scorePercent -ge 0.5) {
        $risk = 4; $likelihood = 4; $riskCost = 4; $riskImpact = 20
    }
    elseif (-not $isCompliant) {
        $risk = 3; $likelihood = 3; $riskCost = 3; $riskImpact = 15
    }
    else {
        $risk = 1; $likelihood = 1; $riskCost = 1; $riskImpact = 5
    }

    # Map Graph controlCategory to CloudRadial category
    $category = switch ($Control.controlCategory) {
        'Account'        { 'Identity' }
        'Identity'       { 'Identity' }
        'Data'           { 'Data' }
        'Device'         { 'Device' }
        'Apps'           { 'Apps' }
        'Infrastructure' { 'Infrastructure' }
        default          { $Control.controlCategory }
    }

    $row = [ordered]@{}
    foreach ($col in $script:templateColumns) { $row[$col] = $null }

    $row['Category']                = $category
    $row['Question']                = $Control.title
    $row['Order']                   = $Order
    $row['Explanation']             = "Service: $($Control.service) | Score Impact: $scorePercent% | Points Achieved: $CurrentScore / $MaxScore"
    $row['Type']                    = "List"
    $row['Answer']                  = $answer
    $row['Text Answer']             = $textAnswer
    $row['Responses']               = "Compliant,Partially Compliant+,N/A=,Missing*,Not Compliant-"
    $row['Is Flagged']              = $isFlagged
    $row['Evaluation']              = "Review this control in the Microsoft 365 Defender portal under Secure Score."
    $row['Remediation Summary']     = if ($Control.remediation) { ($Control.remediation -replace '<[^>]+>','').Substring(0, [math]::Min(200, ($Control.remediation -replace '<[^>]+>','').Length)) } else { $null }
    $row['Remediation']             = if ($Control.remediation) { $Control.remediation -replace '<[^>]+>','' } else { $null }
    $row['Reference']               = "Microsoft Secure Score - $($Control.service)"
    $row['Control Type']            = 10
    $row['Likelihood']              = $likelihood
    $row['Risk']                    = $risk
    $row['Risk Cost']               = $riskCost
    $row['Risk Impact']             = $riskImpact
    $row['Update Key']              = ""
    $row['Content Update Key']      = ""
    $row['Note Compliant']          = "This control is currently enabled and meeting Microsoft's recommendation."
    $row['Note Not Compliant']      = "This control is not yet enabled. Enabling it would improve your Secure Score by approximately $scorePercent%."
    $row['Note Partially Compliant'] = "This control is partially configured. Review the Microsoft 365 Defender portal for details."
    $row['Note NA']                 = "This control does not apply to your current environment."
    $row['Note Missing']            = "Unable to determine the status of this control. Manual review recommended."

    [PSCustomObject]$row
}

function Show-Summary {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Rows,

        [Parameter(Mandatory = $false)]
        [double]$TenantScore = 0,

        [Parameter(Mandatory = $false)]
        [double]$TenantMaxScore = 0
    )

    $compliant = ($Rows | Where-Object { $_.Answer -eq 2 }).Count
    $notCompliant = ($Rows | Where-Object { $_.Answer -eq -2 }).Count
    $scorePercent = if ($TenantMaxScore -gt 0) { [math]::Round(($TenantScore / $TenantMaxScore) * 100, 1) } else { 0 }

    Write-Host ""
    Write-Host "Conversion summary:" -ForegroundColor Cyan
    Write-Host "  Assessment name:   $AssessmentName" -ForegroundColor White
    Write-Host "  Tenant score:      $TenantScore / $TenantMaxScore ($scorePercent%)" -ForegroundColor White
    Write-Host "  Total controls:    $($Rows.Count)" -ForegroundColor White
    Write-Host "  Compliant:         $compliant" -ForegroundColor Green
    Write-Host "  Not Compliant:     $notCompliant" -ForegroundColor Red
    Write-Host ""
    Write-Host "Breakdown by category:" -ForegroundColor Cyan

    $Rows | Group-Object -Property Category | ForEach-Object {
        $catCompliant = ($_.Group | Where-Object { $_.Answer -eq 2 }).Count
        Write-Host "  $($_.Name): $catCompliant/$($_.Count) compliant" -ForegroundColor White
    }
}

# ============================================================================
# Main
# ============================================================================

Confirm-ImportExcelModule

# Resolve output file path
if (-not $OutputFile) {
    $dateStamp = Get-Date -Format "yyyyMMdd"
    $safeTenantId = $TenantId -replace '[^a-zA-Z0-9\-\.]', '_'
    $OutputFile = Join-Path (Get-Location) "Assessment-SecureScore-$safeTenantId-$dateStamp.xlsx"
}

# Authenticate
Write-Host "Authenticating to Microsoft Graph for tenant: $TenantId" -ForegroundColor Cyan
$secret = Get-ClientSecret
$accessToken = Get-GraphAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $secret

# Fetch latest Secure Score snapshot (includes per-control scores)
Write-Host "Fetching latest Secure Score snapshot..." -ForegroundColor Cyan
$scoreResponse = Invoke-GraphRequest -Uri "$graphBaseUri/security/secureScores?`$top=1" -AccessToken $accessToken -MaxRetries $MaxRetries
$latestScore = $scoreResponse.value[0]

if (-not $latestScore) {
    Write-Error "No Secure Score data found for this tenant. Ensure Microsoft Secure Score is enabled."
    exit 1
}

$tenantCurrentScore = $latestScore.currentScore
$tenantMaxScore = $latestScore.maxScore

Write-Host "Tenant score: $tenantCurrentScore / $tenantMaxScore" -ForegroundColor Cyan

# Build lookup of per-control current scores
$controlScoreLookup = @{}
foreach ($cs in $latestScore.controlScores) {
    $controlScoreLookup[$cs.controlName] = $cs.score
}

# Fetch all control profiles (full details: title, service, rank, maxScore, remediation)
Write-Host "Fetching Secure Score control profiles..." -ForegroundColor Cyan
$controlProfiles = Get-AllGraphPages -Uri "$graphBaseUri/security/secureScoreControlProfiles" -AccessToken $accessToken

if (-not $controlProfiles -or $controlProfiles.Count -eq 0) {
    Write-Error "No control profiles returned from the API."
    exit 1
}

# Filter out deprecated controls
$activeControls = $controlProfiles | Where-Object { -not $_.deprecated }
Write-Host "Found $($activeControls.Count) active control profiles ($($controlProfiles.Count) total, $($controlProfiles.Count - $activeControls.Count) deprecated)." -ForegroundColor Cyan

# Sort by category priority, then by rank
$sorted = $activeControls | Sort-Object @(
    @{ Expression = { if ($categoryOrder.ContainsKey($_.controlCategory)) { $categoryOrder[$_.controlCategory] } else { 99 } } },
    @{ Expression = { $_.rank } }
)

# Build assessment rows
$orderCounter = 0
$assessmentRows = foreach ($control in $sorted) {
    $orderCounter += 10

    $currentScore = if ($controlScoreLookup.ContainsKey($control.id)) {
        $controlScoreLookup[$control.id]
    } else { 0 }

    $maxScore = if ($control.maxScore) { [double]$control.maxScore } else { 0 }

    ConvertTo-AssessmentRow -Control $control -Order $orderCounter `
        -CurrentScore $currentScore -MaxScore $maxScore -TotalMaxScore $tenantMaxScore
}

# WhatIf: preview only
if ($WhatIf) {
    Write-Host ""
    Write-Host "What if: Would create $($assessmentRows.Count) assessment questions in $OutputFile" -ForegroundColor Yellow
    Show-Summary -Rows $assessmentRows -TenantScore $tenantCurrentScore -TenantMaxScore $tenantMaxScore
    Write-Host ""
    Write-Host "Run without -WhatIf to generate the file." -ForegroundColor Yellow
    exit 0
}

# Export
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
}

$assessmentRows | Export-Excel -Path $OutputFile -WorksheetName "Assessment" -AutoSize -FreezeTopRow -BoldTopRow

Write-Host ""
Write-Host "Assessment import file created: $OutputFile" -ForegroundColor Green
Show-Summary -Rows $assessmentRows -TenantScore $tenantCurrentScore -TenantMaxScore $tenantMaxScore
Write-Host ""
Write-Host "Import this file into CloudRadial via: Content > Assessments > Import" -ForegroundColor Yellow
