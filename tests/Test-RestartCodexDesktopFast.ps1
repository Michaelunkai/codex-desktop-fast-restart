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
$exePath = Join-Path $ProjectRoot 'CodexDesktopFastRestart.exe'

foreach ($path in @($scriptPath, $readmePath, $gitignorePath, $proofPath, $exePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing expected file: $path"
    }
}

if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
    Test-Parser -Path $scriptPath
    $scriptText = Get-Content -LiteralPath $scriptPath -Raw
    if ($scriptText -match 'CloseMainWindow') {
        Add-Failure 'Foreground close path still uses CloseMainWindow instead of immediate forced stop.'
    }
    if ($scriptText -match "remote-control','stop") {
        Add-Failure 'Foreground remote-control path still stops remote-control before start.'
    }
    if ($scriptText -notmatch 'android-connect-warm' -or $scriptText -notmatch "'connect-warm'") {
        Add-Failure 'Android reconnect path does not use bounded connect-warm worker.'
    }
    if ($scriptText -notmatch 'Start-WorkerCommand' -or $scriptText -notmatch 'WorkerTimeoutSeconds') {
        Add-Failure 'Restart helper does not contain bounded hidden worker support.'
    }
    if ($scriptText -notmatch 'Start-AutoContinueWorker' -or $scriptText -notmatch 'AutoContinueOnly') {
        Add-Failure 'Auto-continue scanning is not detached into a hidden worker.'
    }
    if ($scriptText -notmatch 'TimeoutSeconds 8' -or $scriptText -notmatch 'TimeoutSeconds 10') {
        Add-Failure 'Expected bounded remote/Android timeout ceilings were not found.'
    }
    if ($scriptText -notmatch 'ElapsedMilliseconds -lt 850') {
        Add-Failure 'Desktop force-stop path does not enforce the sub-second close budget.'
    }
    if ($scriptText -notmatch 'ShowWindowAsync' -or $scriptText -notmatch 'MinimizeOnly') {
        Add-Failure 'GUI suppressor/minimize path is missing.'
    }
}

if (Test-Path -LiteralPath $exePath -PathType Leaf) {
    $exeItem = Get-Item -LiteralPath $exePath
    if ($exeItem.Length -le 0) {
        Add-Failure "Executable has zero size: $exePath"
    }
}

if ($failures.Count -gt 0) {
    'FAIL'
    $failures | ForEach-Object { "- $_" }
    exit 1
}

'PASS'
exit 0
