[CmdletBinding()]
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
$failures = New-Object System.Collections.Generic.List[string]

if (-not $ProjectRoot) {
    $ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Test-Parser {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        Add-Failure "Parser errors in $Path`: $($errors[0].Message)"
    }
}

$scriptPath = Join-Path $ProjectRoot 'scripts\Restart-CodexDesktopFast.ps1'
$readmePath = Join-Path $ProjectRoot 'README.md'
$gitignorePath = Join-Path $ProjectRoot '.gitignore'
$proofPath = Join-Path $ProjectRoot 'proof\restart-codex-desktop-fast.latest.jsonl'
$livePath = "$env:USERPROFILE\.codex\scripts\Restart-CodexDesktopFast.ps1"

foreach ($path in @($scriptPath, $readmePath, $gitignorePath, $proofPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing expected file: $path"
    }
}

if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
    Test-Parser -Path $scriptPath
}

if ((Test-Path -LiteralPath $scriptPath -PathType Leaf) -and (Test-Path -LiteralPath $livePath -PathType Leaf)) {
    $packagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $scriptPath).Hash
    $liveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $livePath).Hash
    if ($packagedHash -ne $liveHash) {
        Add-Failure "Packaged script hash does not match live script."
    }
}

$selfTestOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -SelfTest 2>&1
if ($LASTEXITCODE -ne 0) {
    Add-Failure "SelfTest failed: $($selfTestOutput -join ' | ')"
}
if (($selfTestOutput -join "`n") -notmatch 'remote_control_configured=True') {
    Add-Failure "SelfTest did not prove remote_control_configured=True."
}
if (($selfTestOutput -join "`n") -notmatch 'desktop_exe_exists=True') {
    Add-Failure "SelfTest did not prove desktop_exe_exists=True."
}

$dryOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -NoDesktopRestart -NoRemoteRestart -NoAutoContinue -NoStartupSuppressor -HideWatchSeconds 1 2>&1
if ($LASTEXITCODE -ne 0) {
    Add-Failure "Dry run failed: $($dryOutput -join ' | ')"
}
if (($dryOutput -join "`n") -notmatch 'restart-codex-desktop-fast\.jsonl') {
    Add-Failure "Dry run did not report the restart log path."
}

if ($failures.Count -gt 0) {
    'FAIL'
    $failures | ForEach-Object { "- $_" }
    exit 1
}

'PASS'
exit 0
