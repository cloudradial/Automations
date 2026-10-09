# Course Builder

Create training courses and lessons in CloudRadial from a CSV file.

## What It Does

- Reads a CSV with course and lesson definitions
- Groups rows by CourseName + CompanyId into course containers
- Creates the course first, then creates each lesson under it
- Supports `-WhatIf` to preview without creating anything
- Logs every creation with IDs for easy auditing

## Prerequisites

- PowerShell 5.1 or later
- CloudRadial API keys (Settings > API in your portal)

## CSV Template

Create a CSV file with these columns. Rows sharing the same `CourseName` and `CompanyId` are grouped into a single course:

```csv
CompanyId,CourseName,Category,PassScore,LessonTitle,LessonOrder,LessonText
4,"Phishing Awareness","Security",70,"What is Phishing?",1,"<p>Phishing is a type of social engineering attack...</p>"
4,"Phishing Awareness","Security",70,"Spotting Red Flags",2,"<p>Look for misspelled URLs, urgent language...</p>"
4,"Phishing Awareness","Security",70,"What to Do If You Click",3,"<p>If you suspect you clicked a phishing link...</p>"
4,"Password Best Practices","Security",80,"Why Passwords Matter",1,"<p>Strong passwords are your first line of defense...</p>"
4,"Password Best Practices","Security",80,"Creating Strong Passwords",2,"<p>Use at least 12 characters...</p>"
```

| Column | Required | Description |
|--------|----------|-------------|
| CompanyId | Yes | Numeric company ID in CloudRadial |
| CourseName | Yes | Course container name (uses the `name` field in the API) |
| Category | Yes | Course category |
| PassScore | Yes | Minimum passing score (0-100) |
| LessonTitle | Yes | Individual lesson title (uses the `title` field in the API) |
| LessonOrder | Yes | Display order for the lesson (1, 2, 3...) |
| LessonText | Yes | HTML or plain-text lesson content |

## Usage

```powershell
# Import all courses and lessons
.\Import-Courses.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CsvPath ".\courses.csv"

# Preview only (no API calls)
.\Import-Courses.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CsvPath ".\courses.csv" -WhatIf

# Stop on first error
.\Import-Courses.ps1 -PublicKey "YOUR_PUBLIC" -PrivateKey "YOUR_PRIVATE" `
    -CsvPath ".\courses.csv" -StopOnError
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PublicKey` | *(required)* | API public key |
| `-PrivateKey` | *(required)* | API private key |
| `-BaseUrl` | `https://api.us.cloudradial.com` | API base URL |
| `-CsvPath` | *(required)* | Path to the input CSV file |
| `-StopOnError` | `false` | Stop on first failure instead of continuing |

## Customization Tips

- **Course vs. lesson fields**: The API uses `name` for the course container and `title` for lessons. The script handles this mapping.
- **Quiz questions**: Add quiz content in the LessonText column using HTML. CloudRadial renders it in the course player.
- **AI-generated content**: Use Claude to generate lesson text from a topic, then paste into the CSV. The Course Management skill can also create courses interactively.
- **Find company IDs**: Use the `company` endpoint or Portal Lookup skill to look up IDs by name.
