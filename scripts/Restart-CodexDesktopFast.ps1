[CmdletBinding()]
param(
    [string]$CodexHome = "$env:USERPROFILE\.codex",
    [string]$WorkspacePath = (Get-Location).Path,
    [int]$HideWatchSeconds = 35,
    [int]$StartupSuppressSeconds = 300,
    [int]$RecentSessionMinutes = 180,
    [int]$MaxAutoContinueSessions = 8,
    [switch]$NoDesktopRestart,
    [switch]$NoRemoteRestart,
    [switch]$NoAutoContinue,
    [switch]$NoStartupSuppressor,
    [switch]$SuppressOnly,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Continue'
$script:LogPath = Join-Path $CodexHome 'logs\restart-codex-desktop-fast.jsonl'
$script:RunId = [guid]::NewGuid().ToString()

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        $null = New-Item -ItemType Directory -Force -Path $Path -ErrorAction SilentlyContinue
    }
}

function Write-RunLog {
    param([hashtable]$Fields)
    Ensure-Dir -Path (Split-Path -Parent $script:LogPath)
    $Fields['timestamp'] = (Get-Date).ToString('o')
    $Fields['run_id'] = $script:RunId
    $line = ($Fields | ConvertTo-Json -Compress -Depth 10)
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $line | Add-Content -LiteralPath $script:LogPath -Encoding UTF8 -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds (50 + ($i * 25))
        }
    }
}

function Add-WindowApi {
    if ('CodexWindowTools.WindowApi' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace CodexWindowTools {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    public static class WindowApi {
        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll", CharSet=CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    }
}
'@
}

function Hide-CodexWindows {
    param([switch]$MinimizeOnly)
    Add-WindowApi
    $hidden = New-Object System.Collections.Generic.List[object]
    $callback = [CodexWindowTools.EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)
        try {
            if (-not [CodexWindowTools.WindowApi]::IsWindowVisible($hWnd)) { return $true }
            $pid = 0
            $null = [CodexWindowTools.WindowApi]::GetWindowThreadProcessId($hWnd, [ref]$pid)
            if ($pid -le 0) { return $true }
            $p = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if (-not $p -or $p.ProcessName -ne 'Codex') { return $true }
            $titleBuffer = New-Object System.Text.StringBuilder 512
            $null = [CodexWindowTools.WindowApi]::GetWindowText($hWnd, $titleBuffer, $titleBuffer.Capacity)
            $show = if ($MinimizeOnly) { 6 } else { 0 }
            $null = [CodexWindowTools.WindowApi]::ShowWindowAsync($hWnd, $show)
            $hidden.Add([pscustomobject]@{ pid = $pid; handle = $hWnd.ToInt64(); title = $titleBuffer.ToString(); action = $(if ($MinimizeOnly) { 'minimize' } else { 'hide' }) }) | Out-Null
        } catch {}
        return $true
    }
    $null = [CodexWindowTools.WindowApi]::EnumWindows($callback, [IntPtr]::Zero)
    return @($hidden.ToArray())
}

function Start-HideWatcher {
    param([int]$Seconds)
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', $PSCommandPath,
        '-SuppressOnly',
        '-CodexHome', $CodexHome,
        '-HideWatchSeconds', ([string]$Seconds)
    )
    $p = Start-Process -FilePath $ps -ArgumentList $args -WindowStyle Hidden -PassThru
    Write-RunLog @{ type = 'hide-watcher-start'; pid = $p.Id; seconds = $Seconds }
}

function Invoke-HideLoop {
    param([int]$Seconds)
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $Seconds))
    do {
        $hidden = Hide-CodexWindows
        if ($hidden.Count -gt 0) {
            Write-RunLog @{ type = 'window-suppressed'; count = $hidden.Count; windows = @($hidden) }
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
}

function Resolve-CodexCommand {
    $candidates = @(
        (Join-Path $env:APPDATA 'npm\codex.cmd'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\codex.exe')
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Resolve-CodexDesktopExe {
    $running = Get-Process -Name Codex -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -match '\\app\\Codex\.exe$' } |
        Select-Object -First 1
    if ($running) { return $running.Path }

    $pkg = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) {
        $exe = Join-Path $pkg.InstallLocation 'app\Codex.exe'
        if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    }
    return $null
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [int]$TimeoutSeconds = 25,
        [switch]$Hidden
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = ($ArgumentList | ForEach-Object {
            $arg = [string]$_
            if ($arg -match '[\s"]') {
                '"' + ($arg -replace '"', '\"') + '"'
            } else {
                $arg
            }
        }) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = [bool]$Hidden
        $p = [Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            $sw.Stop()
            Write-RunLog @{ type = 'command-timeout'; file = $FilePath; args = $ArgumentList; elapsed_ms = $sw.ElapsedMilliseconds }
            return @{ ok = $false; exit = $null; timed_out = $true }
        }
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $sw.Stop()
        Write-RunLog @{ type = 'command'; file = $FilePath; args = $ArgumentList; exit = $p.ExitCode; elapsed_ms = $sw.ElapsedMilliseconds; stdout_tail = ($stdout -split "`r?`n" | Select-Object -Last 8); stderr_tail = ($stderr -split "`r?`n" | Select-Object -Last 8) }
        return @{ ok = ($p.ExitCode -eq 0); exit = $p.ExitCode; timed_out = $false }
    } catch {
        $sw.Stop()
        Write-RunLog @{ type = 'command-error'; file = $FilePath; args = $ArgumentList; elapsed_ms = $sw.ElapsedMilliseconds; error = $_.Exception.Message }
        return @{ ok = $false; exit = $null; timed_out = $false; error = $_.Exception.Message }
    }
}

function Ensure-CodexConfigReady {
    $guard = Join-Path $CodexHome 'tools\codex-android-remote\Ensure-CodexAndroidRemote.ps1'
    if (Test-Path -LiteralPath $guard -PathType Leaf) {
        $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $null = Invoke-LoggedCommand -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$guard) -TimeoutSeconds 25 -Hidden
        return
    }

    $configPath = Join-Path $CodexHome 'config.toml'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-RunLog @{ type = 'config'; ok = $false; error = 'missing config.toml' }
        return
    }
    $text = Get-Content -LiteralPath $configPath -Raw
    $ok = ($text -match '(?m)^remote_connections\s*=\s*true\s*$') -and
        ($text -match '(?m)^remote_control\s*=\s*true\s*$') -and
        ($text -match '(?m)^keepRemoteControlAwakeWhilePluggedIn\s*=\s*true\s*$')
    Write-RunLog @{ type = 'config'; ok = [bool]$ok; guard = $false }
}

function Ensure-AndroidAutoConnectPersistence {
    $bridge = 'F:\study\Shells\powershell\scripts\android\adb\aadb\Invoke-AndroidAdbBridge.ps1'
    if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) {
        Write-RunLog @{ type = 'android-auto-connect'; ok = $false; error = 'missing aadb bridge'; path = $bridge }
        return
    }
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $null = Invoke-LoggedCommand -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$bridge,'persist') -TimeoutSeconds 35 -Hidden
}

function Register-StartupSuppressor {
    if ($NoStartupSuppressor) { return }
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $runValue = '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -SuppressOnly -CodexHome "{2}" -HideWatchSeconds {3}' -f $ps, $PSCommandPath, $CodexHome, $StartupSuppressSeconds
    try {
        New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Force | Out-Null
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'CodexDesktopPopupSuppressor' -Value $runValue
        Write-RunLog @{ type = 'startup-suppressor'; ok = $true; registry = 'HKCU Run\CodexDesktopPopupSuppressor'; seconds = $StartupSuppressSeconds }
    } catch {
        Write-RunLog @{ type = 'startup-suppressor'; ok = $false; error = $_.Exception.Message }
    }
}

function Restart-RemoteControl {
    param([string]$CodexCmd)
    if ($NoRemoteRestart -or -not $CodexCmd) { return }
    $null = Invoke-LoggedCommand -FilePath $CodexCmd -ArgumentList @('remote-control','stop','--json') -TimeoutSeconds 20 -Hidden
    $start = Invoke-LoggedCommand -FilePath $CodexCmd -ArgumentList @('remote-control','start','--json') -TimeoutSeconds 30 -Hidden
    Write-RunLog @{ type = 'remote-control-restart'; ok = [bool]$start.ok }
}

function Stop-CodexDesktop {
    if ($NoDesktopRestart) { return }
    $processes = @(Get-Process -Name Codex -ErrorAction SilentlyContinue)
    foreach ($p in $processes) {
        try {
            if ($p.MainWindowHandle -and $p.MainWindowHandle -ne 0) {
                $null = $p.CloseMainWindow()
            }
        } catch {}
    }
    Start-Sleep -Milliseconds 900
    $remaining = @(Get-Process -Name Codex -ErrorAction SilentlyContinue)
    foreach ($p in $remaining) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-RunLog @{ type = 'process-killed'; process = $p.ProcessName; pid = $p.Id; path = $p.Path }
        } catch {
            Write-RunLog @{ type = 'process-kill-failed'; process = $p.ProcessName; pid = $p.Id; error = $_.Exception.Message }
        }
    }
}

function Start-CodexDesktopHidden {
    param(
        [string]$CodexCmd,
        [string]$DesktopExe
    )
    if ($NoDesktopRestart) { return }
    Start-HideWatcher -Seconds $HideWatchSeconds
    if ($DesktopExe -and (Test-Path -LiteralPath $DesktopExe -PathType Leaf)) {
        try {
            $p = Start-Process -FilePath $DesktopExe -ArgumentList @($WorkspacePath) -WindowStyle Minimized -PassThru
            Write-RunLog @{ type = 'desktop-start'; method = 'exe'; pid = $p.Id; path = $DesktopExe; workspace = $WorkspacePath }
            return
        } catch {
            Write-RunLog @{ type = 'desktop-start-failed'; method = 'exe'; path = $DesktopExe; error = $_.Exception.Message }
        }
    }
    if ($CodexCmd) {
        $null = Invoke-LoggedCommand -FilePath $CodexCmd -ArgumentList @('app',$WorkspacePath) -TimeoutSeconds 8 -Hidden
    }
}

function Invoke-Prewarm {
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $scripts = @(
        (Join-Path $CodexHome 'scripts\CodexSessionLoadPrewarm.ps1'),
        (Join-Path $CodexHome 'scripts\CodexMobileConnectivityPrewarm.ps1'),
        (Join-Path $CodexHome 'scripts\Test-CodexAndroidStartupHealth.ps1')
    )
    foreach ($script in $scripts) {
        if (Test-Path -LiteralPath $script -PathType Leaf) {
            $null = Invoke-LoggedCommand -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script) -TimeoutSeconds 60 -Hidden
        } else {
            Write-RunLog @{ type = 'prewarm-missing'; path = $script }
        }
    }
}

function Get-SessionTranscriptMap {
    $map = @{}
    $root = Join-Path $CodexHome 'sessions'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $map }
    Get-ChildItem -LiteralPath $root -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            $map[$Matches[1]] = $_.FullName
        }
    }
    return $map
}

function Test-SessionLooksInterrupted {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $true }
    $tail = @(Get-Content -LiteralPath $Path -Tail 80 -ErrorAction SilentlyContinue)
    $joined = ($tail -join "`n")
    if ($joined -match '"type":"event_msg".*"agent_message".*"done skill: complete"') { return $false }
    if ($joined -match '"type":"response_item".*"role":"assistant".*"final"') { return $false }
    if ($joined -match '"type":"event_msg".*"turn_context"') { return $true }
    if ($joined -match '"type":"response_item".*"function_call"(?!_output)') { return $true }
    if ($joined -match '"type":"response_item".*"reasoning"') { return $true }
    return $true
}

function Start-AutoContinueSessions {
    param([string]$CodexCmd)
    if ($NoAutoContinue -or -not $CodexCmd) { return }
    $indexPath = Join-Path $CodexHome 'session_index.jsonl'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        Write-RunLog @{ type = 'auto-continue'; ok = $false; error = 'missing session_index.jsonl' }
        return
    }
    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-1 * [Math]::Abs($RecentSessionMinutes))
    $transcripts = Get-SessionTranscriptMap
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $indexPath -ErrorAction SilentlyContinue) {
        try {
            $entry = $line | ConvertFrom-Json
            if (-not $entry.id -or -not $entry.updated_at) { continue }
            $updated = [datetime]$entry.updated_at
            if ($updated.ToUniversalTime() -lt $cutoff) { continue }
            $id = [string]$entry.id
            $path = if ($transcripts.ContainsKey($id)) { $transcripts[$id] } else { $null }
            if (Test-SessionLooksInterrupted -Path $path) {
                $entries.Add([pscustomobject]@{ id = $id; thread_name = [string]$entry.thread_name; updated_at = $updated.ToString('o'); path = $path }) | Out-Null
            }
        } catch {}
    }
    $selected = @($entries | Sort-Object updated_at -Descending | Select-Object -First $MaxAutoContinueSessions)
    $prompt = 'Continue automatically from exactly where we left off before the restart or interruption. Do not restart from scratch; inspect current state first, preserve user changes, and proceed until the active request is genuinely handled or a user-owned gate remains.'
    foreach ($session in $selected) {
        try {
            $args = @(
                '-NoProfile',
                '-ExecutionPolicy','Bypass',
                '-WindowStyle','Hidden',
                '-Command',
                '& "$env:APPDATA\npm\codex.cmd" resume "' + $session.id + '" "' + ($prompt -replace '"','\"') + '" --no-alt-screen *> "$env:USERPROFILE\.codex\logs\auto-continue-' + $session.id + '.log"'
            )
            $p = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $args -WindowStyle Hidden -PassThru
            Write-RunLog @{ type = 'auto-continue-start'; ok = $true; pid = $p.Id; session_id = $session.id; thread_name = $session.thread_name; transcript = $session.path }
        } catch {
            Write-RunLog @{ type = 'auto-continue-start'; ok = $false; session_id = $session.id; error = $_.Exception.Message }
        }
    }
    Write-RunLog @{ type = 'auto-continue-summary'; candidates = $entries.Count; started = $selected.Count; window_minutes = $RecentSessionMinutes; max = $MaxAutoContinueSessions }
}

function Invoke-SelfTest {
    $codexCmd = Resolve-CodexCommand
    $desktopExe = Resolve-CodexDesktopExe
    $configPath = Join-Path $CodexHome 'config.toml'
    $checks = [ordered]@{
        script_path = $PSCommandPath
        codex_home = $CodexHome
        codex_cmd = $codexCmd
        codex_cmd_exists = [bool]($codexCmd -and (Test-Path -LiteralPath $codexCmd -PathType Leaf))
        desktop_exe = $desktopExe
        desktop_exe_exists = [bool]($desktopExe -and (Test-Path -LiteralPath $desktopExe -PathType Leaf))
        config_exists = [bool](Test-Path -LiteralPath $configPath -PathType Leaf)
        remote_control_configured = $false
        helper_session_prewarm = [bool](Test-Path -LiteralPath (Join-Path $CodexHome 'scripts\CodexSessionLoadPrewarm.ps1') -PathType Leaf)
        helper_mobile_prewarm = [bool](Test-Path -LiteralPath (Join-Path $CodexHome 'scripts\CodexMobileConnectivityPrewarm.ps1') -PathType Leaf)
        helper_android_health = [bool](Test-Path -LiteralPath (Join-Path $CodexHome 'scripts\Test-CodexAndroidStartupHealth.ps1') -PathType Leaf)
        log_path = $script:LogPath
    }
    if ($checks.config_exists) {
        $text = Get-Content -LiteralPath $configPath -Raw
        $checks.remote_control_configured = [bool](($text -match '(?m)^remote_connections\s*=\s*true\s*$') -and ($text -match '(?m)^remote_control\s*=\s*true\s*$'))
    }
    Write-RunLog @{ type = 'self-test'; checks = $checks }
    $checks.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }
    if (-not $checks.codex_cmd_exists -or -not $checks.config_exists -or -not $checks.remote_control_configured) { exit 1 }
    exit 0
}

if ($SuppressOnly) {
    Invoke-HideLoop -Seconds $HideWatchSeconds
    exit 0
}

if ($SelfTest) {
    Invoke-SelfTest
}

$codexCmd = Resolve-CodexCommand
$desktopExe = Resolve-CodexDesktopExe
Write-RunLog @{ type = 'start'; script = $PSCommandPath; codex_cmd = $codexCmd; desktop_exe = $desktopExe; workspace = $WorkspacePath }

Register-StartupSuppressor
Ensure-CodexConfigReady
Ensure-AndroidAutoConnectPersistence
Start-HideWatcher -Seconds $HideWatchSeconds
Restart-RemoteControl -CodexCmd $codexCmd
Stop-CodexDesktop
Start-CodexDesktopHidden -CodexCmd $codexCmd -DesktopExe $desktopExe
Invoke-Prewarm
Start-AutoContinueSessions -CodexCmd $codexCmd
Start-Sleep -Milliseconds 750
$hidden = Hide-CodexWindows
Write-RunLog @{ type = 'finish'; hidden_now = $hidden.Count; codex_processes = @((Get-Process -Name Codex -ErrorAction SilentlyContinue | Select-Object Id,Path,MainWindowHandle,MainWindowTitle)) }

"script=$PSCommandPath"
"log=$script:LogPath"
