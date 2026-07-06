# System Info — startup loading indicator (slice M)

- **Date:** 2026-07-06
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/startup_progress` (off `main`)
- **Part of:** full system-info effort (A=CPU … K=Gaming accuracy, L=Benchmarks
  done, **M=startup progress**). A small UX-polish slice, not a subsystem.

## Goal

When the app is launched by double-clicking `SystemInfo.cmd`, a PowerShell
console window appears and then **sits blank for several seconds** while the
collectors run, before the GUI window opens. Fill that dead air with a
**per-collector progress readout** in the console, so the user sees the app is
working (and, if a collector ever hangs or throws, *which* one).

Deliberately tight: console progress text only. No spinner/animation (the
collectors block the main thread, so real animation would need a background
runspace — the exact closure/runspace complexity slice L spent five review
rounds fighting), and no splash window (heavier, and the console appears first
via the `.cmd` regardless).

## Why the gap exists (grounded in the current startup path)

`SystemInfo.cmd` runs `powershell.exe -NoProfile -ExecutionPolicy Bypass -File
Show-SystemInfo.ps1` — a **visible** console. `Invoke-SystemInfo` (in
`Show-SystemInfo.ps1`, ~line 2679) then runs **11 collectors sequentially**
before building the form:

```
Get-RamModules, Get-RamArrayInfo, Get-MotherboardInfo, Get-CpuInfo, Get-GpuInfo,
Get-StorageInfo, Get-BatteryInfo, Get-LoadInfo, Get-NetworkInfo,
Get-GpuSensorInfo, Get-FirmwareInfo
```

The slow ones spawn processes — `Get-BatteryInfo` runs `powercfg
/batteryreport` (writes an XML report, ~1–3 s), `Get-NetworkInfo` runs `netsh
wlan show interfaces`, `Get-GpuSensorInfo` runs `nvidia-smi` — which is where
the visible-but-blank delay comes from. The console stays visible behind the
GUI after it opens; that is existing behaviour and out of scope here.

## The honest core

- The progress lines reflect **real work actually happening** — each line is
  printed immediately before its collector runs and completed (`done`) only
  after it returns. Nothing is faked or time-estimated; the only editorial
  touch is the parenthetical "(a few seconds)" on the Battery step, which is a
  true, measured characteristic of `powercfg /batteryreport`.
- **A step that hangs or throws is self-revealing:** its `  <label>... ` line
  is printed with no trailing `done`, so the last line on screen names the
  culprit. The steps stay inside the existing collection `try`, so a throw
  still flows to the existing catch (error text in console mode, MessageBox in
  GUI mode) — error handling is unchanged.

## Design

### `Invoke-LoadStep` (new helper)

```
Invoke-LoadStep -Label <string> -Action <scriptblock> [-Show <bool>]
```

- When `-Show` is `$true`: writes `  <Label>... ` (no newline) to the host,
  runs `& $Action`, writes `done` (newline). Returns the action's output
  unchanged.
- When `-Show` is `$false`: pure passthrough — runs `& $Action` and returns its
  output, **prints nothing**. (`-Show` defaults to `$true`; the wiring always
  passes it explicitly.)
- Uses `Write-Host` (host/information stream, like the benchmark progress
  lines), so it never appears in a redirected/ piped stdout capture.
- Same-thread, synchronous `& $Action` — no closures-over-handlers, no
  runspaces (the slice-L failure modes do not apply).

### Wiring in `Invoke-SystemInfo`

- Compute once at the top of the collection block:
  `$show = -not ($Console -or $Benchmark)`.
- When `$show`, print a banner line `Reading system information...` before the
  steps.
- Wrap the 11 collector calls in **9 labelled steps** (subsystem granularity,
  matching the tab vocabulary; the three memory/board reads group into one
  "Memory" step). Labels, in execution order:

  | Step label | Collector(s) |
  |------------|--------------|
  | `Memory` | `Get-RamModules` + `Get-RamArrayInfo` + `Get-MotherboardInfo` |
  | `Processor` | `Get-CpuInfo` |
  | `Graphics` | `Get-GpuInfo` |
  | `Storage` | `Get-StorageInfo` |
  | `Battery (a few seconds)` | `Get-BatteryInfo` |
  | `Live load` | `Get-LoadInfo` |
  | `Network` | `Get-NetworkInfo` |
  | `GPU sensors` | `Get-GpuSensorInfo` |
  | `Firmware & security` | `Get-FirmwareInfo` |

  Call sites keep their existing `@(...)` wrapping where present
  (`@(Invoke-LoadStep 'Graphics' { Get-GpuInfo } -Show $show)`), so array
  semantics are preserved. The `Memory` step returns a small bundle object
  (`{ Modules; Array; Board }`) consumed by the existing
  `New-MemoryReport`/`New-CpuReport` calls.
- After collection, when `$show`, print `Opening window...` immediately before
  `Show-SystemWindow $report`.

### Modes (gating)

- **GUI launch** (`$show = $true`): full readout as above.
- **`-Console`** and **`-Benchmark`** (`$show = $false`): `Invoke-LoadStep` is a
  transparent passthrough — **their output is byte-identical to today.** This
  protects the stable console rendering and the `bench console absent` test,
  and keeps `-Console > report.txt` clean. (Benchmarks already print their own
  progress after collection; the collection phase stays quiet there.)

## Sample output (GUI launch)

```
Reading system information...
  Memory... done
  Processor... done
  Graphics... done
  Storage... done
  Battery (a few seconds)... done
  Live load... done
  Network... done
  GPU sensors... done
  Firmware & security... done
Opening window...
```

## Testing

- **Pure `Invoke-LoadStep`** (unit-tested — it is a deterministic wrapper):
  - `-Show:$true` returns the action's output unchanged
    (`Invoke-LoadStep -Label 'X' -Action { 42 } -Show:$true` → `42`).
  - `-Show:$false` returns the action's output and prints nothing (assert the
    return value; the no-print behaviour is covered by capturing the success
    stream — Write-Host output does not land there).
  - An action returning an array round-trips as an array
    (`{ 1,2,3 }` → 3 elements).
  - Deterministic; no "now"/random dependency.
- **`Invoke-SystemInfo` console side-effects** are main-flow I/O and are **not**
  unit-tested (same posture as the collectors and the `-Benchmark` wiring).
  Verified manually: launch the app and watch the readout appear during
  collection then `Opening window...` before the GUI.
- **Regression guard for the gating:** confirm `-Console` output is unchanged —
  the existing `bench console absent` and other console assertions stay green,
  and a spot check that a plain `-Console` render contains no
  `Reading system information` / `Opening window` text.
- **GUI smoke unaffected** — `GuiSmoke.ps1` sets `SYSTEMINFO_NOMAIN` and calls
  `New-SystemForm` directly, bypassing `Invoke-SystemInfo`; no change expected,
  tab count stays 12.

## Out of scope (YAGNI)

- Animated spinner / progress bar (needs a background runspace to animate during
  blocking collectors — disproportionate risk for cosmetic gain).
- WinForms splash window (heavier; console still appears first via the `.cmd`).
- Hiding the console window entirely, or a per-collector timing readout.
- Progress in `-Console`/`-Benchmark` modes (kept byte-identical by design).
- Parallelising the collectors (a real change to the collection model; separate
  slice if ever wanted).
