# Tests the archive upload in 6-archive.ps1 (Send-ArchiveUpload and Send-CrMultipartPdf) against a local HTTP
# listener instead of mocks, so the real multipart request is checked: the route, the field names, the subject and the
# PDF part. Also checks the fallback to the legacy route when the v2 one answers 404, and that other errors throw.
# The functions run in strict mode through & ([scriptblock]::Create(...)), as on the runner. Placeholder data only.
# Usage: pwsh -NoProfile -File test-upload.ps1
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check { param([string]$Name, [bool]$Ok, $Detail = '') if ($Ok) { $script:pass++; "PASS $Name" } else { $script:fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red } }

# The upload functions, cut from the step source exactly as shipped.
$src = Get-Content (Join-Path $PSScriptRoot '6-archive.ps1') -Raw
$m = [regex]::Match($src, '(?s)if \(-not \(Get-Command Send-ArchiveUpload -ErrorAction SilentlyContinue\)\) \{.*?\n\}\r?\n')
if (-not $m.Success) { throw 'Could not find the upload block in 6-archive.ps1' }
$block = $m.Value

# A one-request-at-a-time HTTP server on a free port. Each request gets the next status from $Codes and is
# recorded (method, path, headers, raw body) for the checks.
function Start-Listener {
    param([int[]]$Codes)
    $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $tcp.Start()
    $port = ([System.Net.IPEndPoint]$tcp.LocalEndpoint).Port
    $job = Start-ThreadJob -ArgumentList $tcp, $Codes -ScriptBlock {
        param($tcp, $codes)
        $out = New-Object System.Collections.ArrayList
        foreach ($code in $codes) {
            $c = $tcp.AcceptTcpClient(); $s = $c.GetStream()
            $buf = New-Object System.IO.MemoryStream; $tmp = New-Object byte[] 65536
            $headEnd = -1; $len = 0
            while ($true) {
                $n = $s.Read($tmp, 0, $tmp.Length); if ($n -le 0) { break }; $buf.Write($tmp, 0, $n)
                $all = [Text.Encoding]::Latin1.GetString($buf.ToArray())
                if ($headEnd -lt 0) { $headEnd = $all.IndexOf("`r`n`r`n"); if ($headEnd -ge 0) { $mm = [regex]::Match($all.Substring(0, $headEnd), '(?im)^Content-Length:\s*(\d+)'); if ($mm.Success) { $len = [int]$mm.Groups[1].Value } } }
                if ($headEnd -ge 0 -and $all.Length -ge $headEnd + 4 + $len) { break }
            }
            $all = [Text.Encoding]::Latin1.GetString($buf.ToArray())
            $null = $out.Add(@{ head = $all.Substring(0, $headEnd); body = $all.Substring($headEnd + 4) })
            $reply = if ($code -lt 300) { '{"success":true,"data":{"archiveItemIds":[31]}}' } else { '{"success":false,"message":"refused"}' }
            $bytes = [Text.Encoding]::UTF8.GetBytes("HTTP/1.1 $code X`r`nContent-Type: application/json`r`nContent-Length: $([Text.Encoding]::UTF8.GetByteCount($reply))`r`nConnection: close`r`n`r`n$reply")
            $s.Write($bytes, 0, $bytes.Length); $s.Flush(); $c.Close()
        }
        $tcp.Stop()
        return , $out
    }
    return @{ port = $port; job = $job }
}
function Invoke-Upload {
    param([int]$Port, [string]$Subject)
    $pdf = Join-Path ([IO.Path]::GetTempPath()) ("upl-" + [guid]::NewGuid().ToString('N') + '.pdf')
    [IO.File]::WriteAllBytes($pdf, [byte[]](37, 80, 68, 70, 45, 49, 46, 52))
    $code = "Set-StrictMode -Version Latest`n`$crBase = 'http://127.0.0.1:$Port'`n`$crAuth = 'Basic dGVzdDp0ZXN0'`n`$crArchive = @{ api = 'v2' }`n" + $block +
    "`n`$res = @{ text = ''; err = '' }`ntry { `$res.text = Send-ArchiveUpload -ArchiveId 90 -FilePath '$pdf' -FileName 'ScalePad - Q2 QBR (2026-06-30).pdf' -Subject '$Subject' } catch { `$res.err = `$_.Exception.Message }`n`$res.api = `$crArchive.api`n`$res"
    try { return (& ([scriptblock]::Create($code))) } finally { Remove-Item $pdf -Force -ErrorAction SilentlyContinue }
}
function Get-Requests { param($L) $r = Receive-Job $L.job -Wait -AutoRemoveJob; return @($r) }

# 1. v2 accepts: one request to /v2/archiveitem/upload with archiveId, subject and a PDF part named files.
$L = Start-Listener @(201)
$r = Invoke-Upload $L.port 'ScalePad - Q2 QBR (2026-06-30)'
$req = @(Get-Requests $L)
Check 'v2: one request, no error' ($req.Count -eq 1 -and -not $r.err) "$($req.Count) requests, err=$($r.err)"
Check 'v2: POST /v2/archiveitem/upload with Basic auth' ($req[0].head -match '^POST /v2/archiveitem/upload HTTP' -and $req[0].head -match '(?im)^Authorization: Basic dGVzdDp0ZXN0') ($req[0].head -split "`r`n")[0]
Check 'v2: multipart body' ($req[0].head -match '(?im)^Content-Type: multipart/form-data; boundary=') ''
Check 'v2: archiveId field' ($req[0].body -match 'name=("?)archiveId\1\s*\r\n\r\n90\r\n') ''
Check 'v2: subject field (no .pdf)' ($req[0].body -match 'name=("?)subject\1\s*\r\n\r\nScalePad - Q2 QBR \(2026-06-30\)\r\n') ''
Check 'v2: the PDF goes in a files part with its file name and type' ($req[0].body -match 'name=("?)files\1; filename=("?)ScalePad - Q2 QBR \(2026-06-30\)\.pdf\2' -and $req[0].body -match '(?is)Content-Type: application/pdf\r\n(?:[^\r\n]+\r\n)*\r\n%PDF-1\.4') ''
Check 'v2: stays on v2' ($r.api -eq 'v2') $r.api

# 2. v2 answers 404 (older portal): the same file goes to the legacy route, and the step remembers it.
$L = Start-Listener @(404, 200)
$r = Invoke-Upload $L.port 'ScalePad - Q2 QBR (2026-06-30)'
$req = @(Get-Requests $L)
Check 'legacy: 404 on v2, then POST /api/beta/archive/90/item' ($req.Count -eq 2 -and $req[1].head -match '^POST /api/beta/archive/90/item HTTP' -and -not $r.err) "$($req.Count) requests, err=$($r.err)"
Check 'legacy: the PDF goes in a part named file' ($req.Count -eq 2 -and $req[1].body -match 'name=("?)file\1; filename=' -and $req[1].body -notmatch 'name=("?)archiveId') ''
Check 'legacy: the rest of the step uses the legacy route' ($r.api -eq 'beta') $r.api

# 3. Any other refusal (a 400 for a bad file) is an error, with no fallback.
$L = Start-Listener @(400)
$r = Invoke-Upload $L.port 'ScalePad - Q2 QBR (2026-06-30)'
$req = @(Get-Requests $L)
Check '400: thrown with the status, no second request' ($req.Count -eq 1 -and $r.err -like 'HTTP 400:*' -and $r.api -eq 'v2') "$($req.Count) requests, err=$($r.err)"

"$pass passed, $fail failed"
if ($fail) { exit 1 }
