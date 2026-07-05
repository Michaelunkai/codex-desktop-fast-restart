# Codex Desktop Fast Restart

Package for `Restart-CodexDesktopFast.ps1`, a Windows PowerShell 5 compatible restart helper for Codex Desktop.

## What It Does

- Restarts Codex Desktop using the installed Windows app path when available.
- Starts a short hidden window suppressor so Codex does not pop in front of other apps during restart.
- During restart, the suppressor is pre-armed and targets only the Codex process started by this package, so manually opened Codex windows are not continuously forced back down.
- Registers `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexDesktopPopupSuppressor` so startup pop-ups are suppressed briefly after logon.
- Force-stops the desktop process immediately instead of waiting on a graceful window close.
- The executable detaches a hidden PowerShell worker and returns immediately after the worker starts.
- Starts `codex remote-control` in a hidden bounded worker when enabled.
- Starts Android reconnect through a direct 10-second ADB saved-endpoint loop, with `aadb connect-warm` as a parallel hidden fallback.
- Reuses existing host helpers:
  - `Ensure-CodexAndroidRemote.ps1`
  - `CodexSessionLoadPrewarm.ps1`
  - `CodexMobileConnectivityPrewarm.ps1`
  - `Test-CodexAndroidStartupHealth.ps1`
- Repairs Android ADB warm-connect persistence through the existing `aadb persist` path.
- Starts bounded hidden `codex resume <session-id>` continuations from a detached worker for recent sessions that look interrupted.
- Keeps slow repair and prewarm tasks out of the foreground restart path.
- Writes package runtime logs under `.\logs` by default, not under the C-drive Codex home.

## Package Layout

The executable starts the packaged script under:

```powershell
.\scripts\Restart-CodexDesktopFast.ps1
```

Runtime logs are written under:

```powershell
.\logs
```

## Usage

Run the packaged executable from its new F-drive location:

```powershell
F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\codex-desktop-fast-restart\CodexDesktopFastRestart.exe
```

Run the packaged script directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Restart-CodexDesktopFast.ps1"
```

Self-test without restart:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Restart-CodexDesktopFast.ps1" -SelfTest
```

Non-destructive operational dry run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Restart-CodexDesktopFast.ps1" -NoDesktopRestart -NoRemoteRestart -NoAutoContinue -NoStartupSuppressor -HideWatchSeconds 1
```

## Verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tests\Test-RestartCodexDesktopFast.ps1"
```

The test checks parser compatibility, the packaged executable, expected support files, and static guarantees for sub-second force-stop, hidden bounded workers, minimized GUI suppression, and `connect-warm`. It does not execute the restart executable.

Rebuild the executable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\launcher\Build-CodexDesktopFastRestart.ps1"
```

## Notes

The script is intentionally preserve-first. It copies or invokes existing helpers and does not delete sessions, transcripts, plugins, or configuration.
