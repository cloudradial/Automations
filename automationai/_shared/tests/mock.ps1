# Shared test harness for the _shared libraries: a mocked runner Key Vault, Invoke-RestMethod and Start-Sleep,
# and Invoke-WithLib, which runs library code plus a test body the way the runner does: pasted into one
# script, run with & ([scriptblock]::Create(...)) under Set-StrictMode -Version Latest (never dot-sourced).
# Test data is placeholder only (Contoso, Example MSP).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$env:RUNNER_KV_NAME = 'kv-test'
$Shared = Split-Path $PSScriptRoot -Parent
$TestTally = @{ pass = 0; fail = 0 }
$Mock = @{ Secrets = @{}; Calls = (New-Object System.Collections.ArrayList); Sleeps = (New-Object System.Collections.ArrayList); Handler = $null; Count = @{} }

function Get-AzKeyVaultSecret {
    [CmdletBinding()] param($VaultName, $Name, [switch]$AsPlainText)
    if ($Mock.Secrets.Contains($Name)) { return $Mock.Secrets[$Name] }
    return $null
}
function Start-Sleep { [CmdletBinding()] param([double]$Seconds = 0, [int]$Milliseconds = 0) $null = $Mock.Sleeps.Add($Seconds) }
function Invoke-RestMethod {
    [CmdletBinding()] param($Method = 'GET', $Uri, $Headers, $Body, $ContentType, $Form)
    $call = [pscustomobject]@{ Method = ([string]$Method).ToUpperInvariant(); Uri = [string]$Uri; Headers = $Headers; Body = $(if ($Body -is [string]) { $Body } else { '' }); BodyObj = $Body; ContentType = [string]$ContentType; Form = $Form }
    $null = $Mock.Calls.Add($call)
    $key = "$($call.Method) $($call.Uri)"; $Mock.Count[$key] = 1 + $(if ($Mock.Count.Contains($key)) { $Mock.Count[$key] } else { 0 })
    if ($null -ne $Mock.Handler) { return (& $Mock.Handler $call $Mock.Count[$key]) }
    return [pscustomobject]@{ id = 1 }
}
# Throws what Invoke-RestMethod throws for an HTTP error: an HttpResponseException carrying the response.
function New-HttpError {
    param([int]$Code, [string]$Body = '', [string]$RetryAfter = '')
    $r = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Code)
    if ($RetryAfter) { $null = $r.Headers.TryAddWithoutValidation('Retry-After', $RetryAfter) }
    $ex = [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Code.", $r)
    $er = [System.Management.Automation.ErrorRecord]::new($ex, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    if ($Body) { $er.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
    throw $er
}
function Reset-Mock {
    param([hashtable]$Secrets = @{}, [scriptblock]$Handler = $null)
    $Mock.Secrets = $Secrets; $Mock.Calls.Clear(); $Mock.Sleeps.Clear(); $Mock.Handler = $Handler; $Mock.Count = @{}
}
function Check {
    param([string]$Name, [bool]$Ok, $Detail = '')
    if ($Ok) { $TestTally.pass++; Write-Host "PASS $Name" } else { $TestTally.fail++; Write-Host "FAIL $Name :: $Detail" -ForegroundColor Red }
}
function Get-LastCall { return @($Mock.Calls)[-1] }
function Get-Calls { param([string]$Method, [string]$Like) return @($Mock.Calls | Where-Object { $_.Method -eq $Method -and $_.Uri -like $Like }) }
function Show-Calls { return (@($Mock.Calls | ForEach-Object { "$($_.Method) $($_.Uri)" }) -join ' ; ') }
function Read-Body { param($Call) if ($null -eq $Call -or -not $Call.Body) { return $null }; return ($Call.Body | ConvertFrom-Json -NoEnumerate) }
# Runs the named _shared files followed by the test body, as one runner step would.
function Invoke-WithLib {
    param([string[]]$Libs, [scriptblock]$Body)
    $code = "Set-StrictMode -Version Latest`n" + (@($Libs | ForEach-Object { Get-Content -Raw (Join-Path $Shared $_) }) -join "`n") + "`n" + $Body.ToString()
    & ([scriptblock]::Create($code))
}
# Runs a body that is expected to throw; returns the message ('' when it didn't throw).
function Get-ThrowMessage { param([scriptblock]$Body) try { & $Body; return '' } catch { return [string]$_.Exception.Message } }
function Complete-Test { Write-Host "$($TestTally.pass) passed, $($TestTally.fail) failed"; if ($TestTally.fail) { exit 1 }; exit 0 }
