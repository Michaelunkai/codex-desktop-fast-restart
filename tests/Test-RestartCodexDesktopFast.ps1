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
$launcherPath = Join-Path $ProjectRoot 'launcher\Program.cs'
$desktopExeCachePath = Join-Path $ProjectRoot 'config\CodexDesktopExePath.txt'

foreach ($path in @($scriptPath, $readmePath, $gitignorePath, $proofPath, $exePath, $launcherPath, $desktopExeCachePath)) {
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
    $logStart = $scriptText.IndexOf('function Write-RunLog')
    $logEnd = $scriptText.IndexOf('function Add-WindowApi')
    if ($logStart -lt 0 -or $logEnd -lt $logStart) {
        Add-Failure 'Could not locate Write-RunLog for static verification.'
    } else {
        $logText = $scriptText.Substring($logStart, $logEnd - $logStart)
        if ($logText -match 'Start-Sleep' -or $logText -match 'for \(' -or $logText -notmatch 'AppendAllText') {
            Add-Failure 'Write-RunLog can still block on retry/sleep instead of best-effort append.'
        }
    }
    if ($scriptText -notmatch 'function ConvertTo-ProcessArgument' -or $scriptText -notmatch 'function Join-ProcessArguments') {
        Add-Failure 'Process launch argument quoting helpers are missing.'
    }
    if ($scriptText -match 'Start-Process[^\r\n]+-ArgumentList \$args' -or $scriptText -match 'Start-Process[^\r\n]+-ArgumentList @\(\$WorkspacePath\)') {
        Add-Failure 'Start-Process still uses raw argument arrays for worker or workspace paths.'
    }
    if ($scriptText -notmatch 'Join-ProcessArguments \$args' -or $scriptText -notmatch 'Join-ProcessArguments @\(\$WorkspacePath\)') {
        Add-Failure 'Start-Process launches are not consistently using quoted argument strings.'
    }
    if ($scriptText -match "remote-control','stop") {
        Add-Failure 'Foreground remote-control path still stops remote-control before start.'
    }
    if ($scriptText -notmatch 'android-connect-warm' -or $scriptText -notmatch "'connect-warm'") {
        Add-Failure 'Android reconnect path does not use bounded connect-warm worker.'
    }
    if ($scriptText -notmatch 'android-fast-reconnect' -or $scriptText -notmatch 'Invoke-AndroidFastReconnect') {
        Add-Failure 'Android reconnect path does not include the package fast reconnect worker.'
    }
    if ($scriptText -notmatch "start-server" -or $scriptText -notmatch 'Get-SavedAndroidEndpoints' -or $scriptText -notmatch "adb.exe") {
        Add-Failure 'Android fast reconnect worker does not use direct ADB saved-endpoint recovery.'
    }
    if ($scriptText -notmatch 'Test-AdbHasAuthorizedDevice' -or $scriptText -notmatch 'saved-endpoint') {
        Add-Failure 'Android fast reconnect worker does not verify authorized device recovery.'
    }
    if (-not $scriptText.Contains("@('devices','-l')") -or -not $scriptText.Contains('(?m)\sdevice(?:\s|$)')) {
        Add-Failure 'Android authorized-device detection does not handle adb devices -l output.'
    }
    if (-not $scriptText.Contains("'\.(cmd|bat)$'") -or -not $scriptText.Contains('System32\cmd.exe') -or -not $scriptText.Contains('@(''/d'',''/c'',$FilePath)')) {
        Add-Failure 'Command runner does not wrap .cmd/.bat commands for hidden worker execution.'
    }
    $runnerStart = $scriptText.IndexOf('function Invoke-LoggedCommand')
    $runnerEnd = $scriptText.IndexOf('function Start-WorkerCommand')
    if ($runnerStart -lt 0 -or $runnerEnd -lt $runnerStart) {
        Add-Failure 'Could not locate bounded command runner for static verification.'
    } else {
        $runnerText = $scriptText.Substring($runnerStart, $runnerEnd - $runnerStart)
        if ($runnerText -notmatch 'RedirectStandardOutput\s*=\s*\$false' -or $runnerText -notmatch 'RedirectStandardError\s*=\s*\$false' -or $runnerText -match 'ReadToEnd') {
            Add-Failure 'Bounded command runner can still block on redirected stdout/stderr pipes.'
        }
    }
    if (-not $scriptText.Contains('if ($ArgumentList -and $ArgumentList.Count -gt 0)') -or -not $scriptText.Contains('@(''-WorkerArguments'') + @($ArgumentList)')) {
        Add-Failure 'Worker launcher can still emit a dangling -WorkerArguments parameter for empty-argument workers.'
    }
    if ($scriptText -notmatch 'Start-WorkerCommand' -or $scriptText -notmatch 'WorkerTimeoutSeconds') {
        Add-Failure 'Restart helper does not contain bounded hidden worker support.'
    }
    if ($scriptText -notmatch 'Start-AutoContinueWorker' -or $scriptText -notmatch 'AutoContinueOnly') {
        Add-Failure 'Auto-continue scanning is not detached into a hidden worker.'
    }
    if ($scriptText -notmatch 'Start-SetupWorker' -or $scriptText -notmatch 'SetupOnly') {
        Add-Failure 'Startup/config/Android/prewarm setup is not detached into a hidden worker.'
    }
    if ($scriptText -notmatch 'CodexDesktopExePath\.txt' -or $scriptText -notmatch 'Update-CodexDesktopExeCache') {
        Add-Failure 'Codex Desktop executable resolution is not backed by a package-local cache.'
    }
    if ($scriptText -notmatch 'param\(\[switch\]\$AllowSlow\)' -or $scriptText -notmatch 'if \(-not \$AllowSlow\) \{ return \$null \}') {
        Add-Failure 'Slow AppX desktop resolution is not gated behind an explicit switch.'
    }
    $mainResolveIndex = $scriptText.LastIndexOf('$desktopExe = Resolve-CodexDesktopExe')
    if ($mainResolveIndex -lt 0 -or $scriptText.Substring($mainResolveIndex, [Math]::Min(80, $scriptText.Length - $mainResolveIndex)) -match 'AllowSlow') {
        Add-Failure 'Foreground restart path can still perform slow AppX desktop resolution.'
    }
    $mainStart = $scriptText.IndexOf('$codexCmd = Resolve-CodexCommand')
    $mainText = if ($mainStart -ge 0) { $scriptText.Substring($mainStart) } else { '' }
    foreach ($blockingCall in @('Register-StartupSuppressor', 'Ensure-CodexConfigReady', 'Ensure-AndroidAutoConnectPersistence', 'Invoke-Prewarm')) {
        $setupOnlyIndex = $mainText.IndexOf('if ($SetupOnly)')
        $afterSetupOnly = if ($setupOnlyIndex -ge 0) { $mainText.Substring($setupOnlyIndex) } else { $mainText }
        $mainPathIndex = $afterSetupOnly.IndexOf('Start-SetupWorker')
        $tail = if ($mainPathIndex -ge 0) { $afterSetupOnly.Substring($mainPathIndex) } else { $afterSetupOnly }
        if ($tail.Contains($blockingCall)) {
            Add-Failure "Foreground restart path still calls $blockingCall directly."
        }
    }
    if ($scriptText -notmatch 'TimeoutSeconds 8' -or $scriptText -notmatch 'TimeoutSeconds 10') {
        Add-Failure 'Expected bounded remote/Android timeout ceilings were not found.'
    }
    if ($scriptText.Contains('Invoke-LoggedCommand -FilePath $CodexCmd -ArgumentList @(''app'',$WorkspacePath)') -or -not $scriptText.Contains('desktop-app-fallback'' -FilePath $CodexCmd -ArgumentList @(''app'',$WorkspacePath) -TimeoutSeconds 3')) {
        Add-Failure 'Codex app fallback is not detached or capped at three seconds.'
    }
    if ($scriptText -notmatch 'ElapsedMilliseconds -lt 650' -or $scriptText -match 'ElapsedMilliseconds -lt 850') {
        Add-Failure 'Desktop force-stop path does not keep enough margin under the sub-second close budget.'
    }
    if ($scriptText -notmatch 'ShowWindowAsync' -or $scriptText -notmatch 'MinimizeOnly') {
        Add-Failure 'GUI suppressor/minimize path is missing.'
    }
    if ($scriptText -notmatch '\[string\]\$TargetPidFile' -or $scriptText -notmatch 'TargetPids' -or $scriptText -notmatch 'DesktopTargetPids') {
        Add-Failure 'GUI suppressor is not scoped to the package-launched Codex process.'
    }
    if (-not $scriptText.Contains('if ($TargetPidFile)') -or -not $scriptText.Contains('if ($targetPids.Count -eq 0)')) {
        Add-Failure 'Target-PID watcher can still fall back to broad suppression before the launched PID is known.'
    }
    $watcherIndex = $scriptText.IndexOf('Start-HideWatcher -Seconds $HideWatchSeconds -TargetPidFilePath $targetPidPath')
    $launchIndex = $scriptText.IndexOf('Start-Process -FilePath $DesktopExe')
    if ($watcherIndex -lt 0 -or $launchIndex -lt 0 -or $watcherIndex -gt $launchIndex) {
        Add-Failure 'Targeted hide watcher is not started before Codex Desktop launch.'
    }
    if ($scriptText -match '\$StartupSuppressSeconds\s*=\s*300') {
        Add-Failure 'Startup suppressor still uses a long broad suppression window.'
    }
    if ($scriptText -notmatch 'Hide-CodexWindows -MinimizeOnly -TargetPids \$script:DesktopTargetPids') {
        Add-Failure 'Final GUI minimize call is not target-scoped.'
    }
    if ($scriptText -match 'USERPROFILE\\\.codex\\logs' -or $scriptText -match '\$env:USERPROFILE\\\.codex\\logs') {
        Add-Failure 'Script still writes restart or auto-continue logs under the C-drive Codex home.'
    }
    if ($scriptText -notmatch '\[string\]\$LogRoot' -or $scriptText -notmatch 'PackageRoot' -or $scriptText -notmatch "'logs'") {
        Add-Failure 'Script does not default logs to the package-local logs directory.'
    }
}

if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
    $launcherText = Get-Content -LiteralPath $launcherPath -Raw
    if ($launcherText -match 'WaitForExit') {
        Add-Failure 'Executable launcher still waits for the restart PowerShell worker to finish.'
    }
    if ($launcherText -notmatch 'CreateNoWindow = true' -or $launcherText -notmatch '"-WindowStyle"' -or $launcherText -notmatch '"Hidden"') {
        Add-Failure 'Executable launcher does not force hidden PowerShell startup.'
    }
    if ($launcherText -notmatch 'return 0;') {
        Add-Failure 'Executable launcher does not return immediately after spawning the hidden worker.'
    }
}

if (Test-Path -LiteralPath $exePath -PathType Leaf) {
    $exeItem = Get-Item -LiteralPath $exePath
    if ($exeItem.Length -le 0) {
        Add-Failure "Executable has zero size: $exePath"
    }
}

if (Test-Path -LiteralPath $desktopExeCachePath -PathType Leaf) {
    $cachedDesktopExe = (Get-Content -LiteralPath $desktopExeCachePath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $cachedDesktopExe -or $cachedDesktopExe -notmatch '\\app\\Codex\.exe$') {
        Add-Failure "Desktop executable cache is missing or malformed: $desktopExeCachePath"
    }
}

if ($failures.Count -gt 0) {
    'FAIL'
    $failures | ForEach-Object { "- $_" }
    exit 1
}

'PASS'
exit 0
