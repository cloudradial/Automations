<#
.SYNOPSIS
    Bulk-creates training courses and lessons in CloudRadial from a CSV file.

.DESCRIPTION
    Reads a CSV file with course and lesson definitions, groups rows by CourseName,
    creates the course container first, then creates each lesson under it.

    The CSV must have columns:
      CompanyId, CourseName, Category, PassScore, LessonTitle, LessonOrder, LessonText

    Rows sharing the same CourseName+CompanyId are grouped into one course.
    The course container is created first (POST /v2/odata/course), then each lesson
    is created individually (POST /v2/odata/course_lesson).

    Use -WhatIf to preview what would be created without making any API calls.

.PARAMETER PublicKey
    CloudRadial API public key.

.PARAMETER PrivateKey
    CloudRadial API private key.

.PARAMETER BaseUrl
    Base URL for the CloudRadial API. Defaults to https://api.us.cloudradial.com.

.PARAMETER CsvPath
    Path to the input CSV file. Required.

.PARAMETER StopOnError
    If set, stop processing on the first API error.

.EXAMPLE
    .\Import-Courses.ps1 -PublicKey "abc" -PrivateKey "xyz" -CsvPath ".\courses.csv"
    Creates all courses and lessons defined in the CSV.

.EXAMPLE
    .\Import-Courses.ps1 -PublicKey "abc" -PrivateKey "xyz" -CsvPath ".\courses.csv" -WhatIf
    Shows what would be created without making any API calls.

.EXAMPLE
    .\Import-Courses.ps1 -PublicKey "abc" -PrivateKey "xyz" -CsvPath ".\courses.csv" -StopOnError
    Creates courses but stops on the first failure.

.NOTES
    Requires PowerShell 5.1+.
    API endpoints: POST /v2/odata/course, POST /v2/odata/course_lesson
    Course creation is two-step: container first, then lessons. See the Course Management
    skill README for details on field naming (course uses "name", lesson uses "title").
    API docs: https://api.us.cloudradial.com/v2/odata/$metadata
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PublicKey,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PrivateKey,

    [string]$BaseUrl = "https://api.us.cloudradial.com",

    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path $_)) { throw "CSV file not found: $_" }
        $true
    })]
    [string]$CsvPath,

    [switch]$StopOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Build auth header ---
$authBytes = [Text.Encoding]::ASCII.GetBytes("$($PublicKey):$($PrivateKey)")
$authHeader = @{ Authorization = "Basic " + [Convert]::ToBase64String($authBytes) }

# --- Read and validate CSV ---
Write-Host "Reading CSV from $CsvPath..." -ForegroundColor Cyan
$rows = Import-Csv -Path $CsvPath -Encoding UTF8

if ($rows.Count -eq 0) {
    throw "CSV file is empty."
}

$requiredColumns = @("CompanyId", "CourseName", "Category", "PassScore", "LessonTitle", "LessonOrder", "LessonText")
$csvColumns = $rows[0].PSObject.Properties.Name
$missing = $requiredColumns | Where-Object { $_ -notin $csvColumns }
if ($missing) {
    throw "CSV is missing required columns: $($missing -join ', '). Expected: $($requiredColumns -join ', ')"
}

# --- Group rows by course ---
$courseGroups = $rows | Group-Object { "$($_.CompanyId)|$($_.CourseName)" }
Write-Host "  Found $($courseGroups.Count) course(s) with $($rows.Count) total lesson(s)." -ForegroundColor Green

# --- Process each course group ---
$courseUri = "$BaseUrl/v2/odata/course"
$lessonUri = "$BaseUrl/v2/odata/course_lesson"
$coursesCreated = 0
$lessonsCreated = 0
$errorCount = 0

foreach ($group in $courseGroups) {
    $firstRow = $group.Group[0]
    $companyId = [int]$firstRow.CompanyId
    $courseName = $firstRow.CourseName
    $category = $firstRow.Category
    $passScore = 70  # default

    if ($firstRow.PassScore -and $firstRow.PassScore -match "^\d+$") {
        $passScore = [int]$firstRow.PassScore
    }

    $lessonRows = $group.Group | Sort-Object { [int]$_.LessonOrder }
    $displayName = "'$courseName' (Company $companyId, $($lessonRows.Count) lessons)"

    # --- Create course container ---
    $courseBody = @{
        companyId  = $companyId
        name       = $courseName
        category   = $category
        passScore  = $passScore
        isRequired = $false
    } | ConvertTo-Json -Depth 5

    $courseId = $null

    if ($PSCmdlet.ShouldProcess($displayName, "Create course via POST $courseUri")) {
        try {
            Write-Verbose "POST $courseUri"
            $courseResult = Invoke-RestMethod -Uri $courseUri -Headers $authHeader -Method Post `
                -Body $courseBody -ContentType "application/json"
            $courseId = $courseResult.courseId
            Write-Host "  Course created: $courseName (courseId: $courseId)" -ForegroundColor Green
            $coursesCreated++
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Warning "  Failed to create course $displayName - $errorMsg"
            $errorCount++
            if ($StopOnError) {
                throw "Stopping on error: $errorMsg"
            }
            continue  # Skip lessons if course creation failed
        }
    }
    else {
        # WhatIf mode - show lesson preview too
        foreach ($lesson in $lessonRows) {
            $lessonDisplay = "  Lesson $($lesson.LessonOrder): '$($lesson.LessonTitle)'"
            Write-Host "    [WhatIf] Would create: $lessonDisplay" -ForegroundColor DarkGray
        }
        continue
    }

    # --- Create lessons for this course ---
    foreach ($lesson in $lessonRows) {
        $lessonOrder = if ($lesson.LessonOrder -match "^\d+$") { [int]$lesson.LessonOrder } else { 1 }
        $lessonDisplay = "Lesson $lessonOrder: '$($lesson.LessonTitle)' in course $courseId"

        $lessonBody = @{
            courseId   = $courseId
            companyId  = $companyId
            courseName = $courseName
            title      = $lesson.LessonTitle
            text       = $lesson.LessonText
            order      = $lessonOrder
            overview   = ""
            category   = ""
        } | ConvertTo-Json -Depth 5

        if ($PSCmdlet.ShouldProcess($lessonDisplay, "Create lesson via POST $lessonUri")) {
            try {
                Write-Verbose "POST $lessonUri"
                $lessonResult = Invoke-RestMethod -Uri $lessonUri -Headers $authHeader -Method Post `
                    -Body $lessonBody -ContentType "application/json"
                $newLessonId = if ($lessonResult.courseLessonId) { $lessonResult.courseLessonId } else { "unknown" }
                Write-Host "    Lesson created: $($lesson.LessonTitle) (lessonId: $newLessonId)" -ForegroundColor DarkGreen
                $lessonsCreated++
            }
            catch {
                $errorMsg = $_.Exception.Message
                Write-Warning "    Failed: $lessonDisplay - $errorMsg"
                $errorCount++
                if ($StopOnError) {
                    throw "Stopping on error: $errorMsg"
                }
            }
        }
    }
}

# --- Summary ---
Write-Host "`nImport Complete:" -ForegroundColor Cyan
Write-Host "  Courses created: $coursesCreated" -ForegroundColor Green
Write-Host "  Lessons created: $lessonsCreated" -ForegroundColor Green
if ($errorCount -gt 0) {
    Write-Host "  Errors:          $errorCount" -ForegroundColor Red
}
Write-Host "  Total rows:      $($rows.Count)" -ForegroundColor Cyan
