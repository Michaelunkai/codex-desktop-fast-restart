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

## Live Install Path

The live script remains here:

```powershell
C:\Users\micha\.codex\scripts\Restart-CodexDesktopFast.ps1
```

This repository keeps a packaged copy under:

```powershell
.\scripts\Restart-CodexDesktopFast.ps1
```

## Usage

Run the live script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\micha\.codex\scripts\Restart-CodexDesktopFast.ps1"
```

Run the packaged copy:

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

The test checks parser compatibility, self-test output, dry-run logging, copied live script parity, and expected support files.

## Notes

The script is intentionally preserve-first. It copies or invokes existing helpers and does not delete sessions, transcripts, plugins, or configuration. The live script is copied into this project rather than moved so global Codex behavior keeps working.
