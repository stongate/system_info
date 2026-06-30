# Session handoff — Battery/power subsystem (slice D)

- **Date:** 2026-06-30
- **Repo:** `C:\Users\stong\Development\memory_checker` (GitHub: `stongate/system_info`)
- **Next task:** add a **Battery / power** subsystem to the system-info tool, as slice D.

## TL;DR / first action

The system-info tool (CPU + GPU + Memory + Storage) is complete and on `main`.
The next slice adds **battery/power**. Start a new branch `feature/battery_info`
off `main`, then follow the usual flow: **brainstorm → committed spec → build
directly with TDD → verify (console + off-screen render) → commit → push →
fast-forward merge to main.** Don't pre-bake the design here — brainstorm it
fresh (grounded in the real battery data), this doc just sets the starting point.

## Current project state

- Branch `main` @ `2803a23` (README), pushed. Working tree clean.
- Four subsystems done and merged: **CPU, GPU, Memory, Storage**, each with a
  tab + Overview line + console section + bottleneck notes.
- Feature branches already merged and deleted. README + screenshot added. Repo
  renamed to `stongate/system_info` (local folder still `memory_checker`; the
  local `origin` remote is already repointed to the new URL).
- **148 unit tests + GUI smoke pass.** Tool is zero-install, two distributed
  files: `Show-SystemInfo.ps1` + `SystemInfo.cmd`.

## Architecture — how a subsystem is added

Pattern (mirror CPU/GPU/Memory/Storage in `Show-SystemInfo.ps1`):

1. **Collector** (thin, CIM/registry/powercfg, I/O): `Get-BatteryInfo` → raw object(s).
2. **Pure builder**: `New-BatteryReport` → the Battery section object. Pure +
   unit-tested; pass any "now"/non-deterministic input as a parameter.
3. **Pure insights**: `Get-BatteryInsights` → `{ Kind; Text }` notes.
4. **Wire up**: add `-Battery` to `New-SystemReport` and `Get-SystemInsights`
   (the orchestrator calls each `Get-<X>Insights`; remember the array-flattening
   pattern — assign sub-results then `+=`, don't wrap calls in `@()`).
5. **Renderers**: a **Battery tab** in `New-SystemForm`, a Battery line on the
   **Overview** tab, and a Battery section in `Write-SystemConsole`. Wire the
   collector into `Invoke-SystemInfo`.
6. **Graceful absence**: desktops have no battery — handle null/empty cleanly
   (no tab/section, or an "AC only (no battery)" line).

## Battery/power — starting point (brainstorm these, don't assume)

- **Goal:** current charge %, AC/charging status, and **battery health/wear**
  (the valuable part), plus the active power plan.
- **Likely data sources** (verify live first):
  - `Win32_Battery` — `EstimatedChargeRemaining`, `BatteryStatus`.
  - `root\wmi`: `BatteryStaticData`/`MSBatteryClass` (DesignedCapacity) and
    `BatteryFullChargedCapacity` — **wear% = (Design − FullCharge) / Design × 100**.
  - Or parse `powercfg /batteryreport` (HTML) for design vs full-charge capacity.
  - `powercfg /getactivescheme` for the active power plan.
- **Candidate notes:** battery worn beyond ~X% of design; running on "Power
  saver" (caps performance); (maybe) very low charge. Decide thresholds in spec.
- **Reference machine:** Dell XPS 17 9700, i7-10875H (laptop, has a battery).

## Workflow + commands

- Branch: `git switch -c feature/battery_info` (off `main`).
- Unit tests: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
- GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
- Console run: `pwsh -NoProfile -File Show-SystemInfo.ps1 -Console`
- **GUI render check** (since you can't see the live window): build the report,
  call `New-SystemForm`, `$form.StartPosition='Manual'; $form.Location=(-3000,-3000)`,
  `$form.Show()`, `DoEvents`, `DrawToBitmap` to a PNG, then read it. Use
  Windows PowerShell (STA). The launcher/tests use env `SYSTEMINFO_NOMAIN` to
  suppress the GUI on dot-source.
- Honest-data ethos: never fabricate; label derived/best-effort values.
- When done: commit, push `feature/battery_info`, then FF-merge to `main`.

See also memory notes `system-info-project` and `steven-build-workflow`.
