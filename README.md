# Codex Desktop Fast Restart

Package for `Restart-CodexDesktopFast.ps1`, a Windows PowerShell 5 compatible restart helper for Codex Desktop.

## What It Does

- Restarts Codex Desktop using the installed Windows app path when available.
- Starts a short hidden window suppressor so Codex does not pop in front of other apps during restart.
- Registers `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CodexDesktopPopupSuppressor` so startup pop-ups are suppressed after logon.
- Restarts `codex remote-control` when enabled.
- Reuses existing host helpers:
  - `Ensure-CodexAndroidRemote.ps1`
  - `CodexSessionLoadPrewarm.ps1`
  - `CodexMobileConnectivityPrewarm.ps1`
  - `Test-CodexAndroidStartupHealth.ps1`
- Repairs Android ADB warm-connect persistence through the existing `aadb persist` path.
- Starts bounded hidden `codex resume <session-id>` continuations for recent sessions that look interrupted.

## Package Layout

The executable starts the packaged script under:

```powershell
.\scripts\Restart-CodexDesktopFast.ps1
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

The test checks parser compatibility, self-test output, dry-run logging, the packaged executable, and expected support files.

Rebuild the executable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\launcher\Build-CodexDesktopFastRestart.ps1"
```

## Notes

The script is intentionally preserve-first. It copies or invokes existing helpers and does not delete sessions, transcripts, plugins, or configuration.
