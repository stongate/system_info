# System Info — GPU sensors / thermals (nvidia-smi) + notes (slice G)

- **Date:** 2026-07-01
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/gpu_thermals` (off `main`)
- **Part of:** full system-info effort (A=CPU … F=Network done, **G=GPU sensors**).

## Goal

Surface **real GPU sensor data** — temperature, utilization, clocks, power,
performance state, and **thermal-throttle** status — for an NVIDIA GPU via
`nvidia-smi`, with an honest thermal-throttle bottleneck note. This closes the
original "thermals" question: `nvidia-smi` is the one real sensor source on this
machine (the CPU/ACPI paths return "Not supported" / blank).

## Decisions

- **Source: `nvidia-smi`** (ships with the NVIDIA driver; already on PATH). This
  is a deliberate, scoped departure from the tool's pure-Windows-built-ins ethos,
  justified because it's the only honest GPU-sensor source and requires no extra
  install for anyone who has an NVIDIA GPU.
- **NVIDIA-only, graceful absence:** no `nvidia-smi` / no NVIDIA GPU / command
  fails → no sensor panel, no section, no notes (like a desktop with no battery).
- **First NVIDIA GPU only** (multi-GPU aggregation is out of scope).
- **Placement:** a live **"GPU sensors" panel on the existing GPU tab** (keeps
  GPU data together), plus a console section and the thermal note. No new tab,
  no new Overview line (GPU is already on Overview; the note flows to its Notes
  box). Values labelled live/"right now".

## Architecture (mirrors the established pattern)

- **`ConvertFrom-NvidiaSmiCsv`** (pure) — `-Line <string>` from
  `nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,clocks.gr,
  clocks.max.gr,power.draw,pstate,clocks_throttle_reasons.sw_thermal_slowdown,
  clocks_throttle_reasons.hw_thermal_slowdown --format=csv,noheader,nounits` →
  `{ Name; TempC; UtilPercent; ClockMHz; MaxClockMHz; PowerW; PState;
  SwThermal; HwThermal }`. Splits on `,`, trims; `[N/A]`/non-numeric → `$null`.
- **`Get-GpuSensorInfo`** (collector, I/O; verified via `-Console`) — returns
  `$null` unless `nvidia-smi` resolves (`Get-Command`) and the query succeeds
  (exit 0, a line back); parses the first GPU line. Self-guarding (never throws).
- **`New-GpuSensorReport`** (pure, all inputs as params) → the GpuSensor section:
  `{ Name; TempC; UtilPercent; ClockMHz; MaxClockMHz; PowerW; PState;
  ThermalThrottle }` where `ThermalThrottle = (SwThermal -eq 'Active' -or
  HwThermal -eq 'Active')`.
- **`Get-GpuSensorInsights`** (pure) → thermal notes.
- Wired into **`Get-SystemInsights`** / **`New-SystemReport`** (`-GpuSensor`,
  assign-then-`+=`); **`Invoke-SystemInfo`** collects + builds it.

## Insights (`Get-GpuSensorInsights`)

- **Thermal throttle (authoritative):** `ThermalThrottle -eq $true` → *warn:*
  "The GPU is thermally throttling right now (`<temp>`°C) — it's hot enough that
  it's reducing clocks. Improve airflow/cooling (clean fans, raise the laptop,
  check thermal paste)."
- **Running hot (heuristic):** not throttling but `TempC -ge 87` → *info:* "GPU
  is running hot (`<temp>`°C), near the throttle point; keep an eye on cooling."
- No note otherwise (idle 50°C → nothing). No note when data missing.

## GUI / console

- **GPU tab:** below the existing GPU ListView, a bottom **"GPU sensors (live,
  via nvidia-smi)"** panel (only when sensor data exists): Temperature,
  Utilization, Core clock (`<cur> / <max> MHz`), Power draw, Performance state,
  and — when throttling — a "Thermal throttling" line. The ListView keeps the
  remaining space (Fill).
- **Console:** a `GPU sensors` section before `Notes` (only when data exists),
  key/value style.
- **Overview:** unchanged (GPU already has a line; the thermal note appears in
  the Notes box).

## Reference data (dev machine, 2026-07-01 — RTX 2060 Max-Q, driver 581.80)

`NVIDIA GeForce RTX 2060 with Max-Q Design, 50, 0, 300, 2100, 8.38, P8,
Not Active, Not Active` → Temp 50°C, 0% util, 300/2100 MHz, 8.4 W, state P8
(idle), **no thermal throttle** → sensor panel shows the data, no notes fire
(honest; the GPU is idle and cool).

## Testing

- **Pure `ConvertFrom-NvidiaSmiCsv`:** the reference line → Name, TempC 50, Util
  0, Clock 300, MaxClock 2100, Power 8.38, PState `P8`, thermals `Not Active`;
  an `[N/A]` power field → `$null`; empty/garbage → nulls.
- **Pure `New-GpuSensorReport`:** field pass-through; `ThermalThrottle` true when
  either thermal flag is `Active`, false otherwise.
- **Pure `Get-GpuSensorInsights`:** throttle → warn; hot (90°C, not throttling)
  → info; idle (50°C, not throttling) → no note.
- **Wiring:** `-GpuSensor` flows notes; `Get-SystemInsights -GpuSensor $null` →
  no note, no error.
- **Console:** `GPU sensors` section present with data, absent when `$null`.
- **GUI (`GuiSmoke.ps1`):** add a GpuSensor fixture; assert the GPU tab shows a
  sensor panel (Temperature label / temp value); no-sensor case unchanged (still
  8 tabs, no panel); off-screen render.

## Out of scope (YAGNI)

- AMD/Intel GPU sensors (no equivalent zero-install source), multi-GPU
  aggregation, VRAM temperature, fan-RPM, historical graphs, a dedicated tab, and
  any control (this is read-only).
