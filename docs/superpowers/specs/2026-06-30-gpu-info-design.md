# System Info — GPU detection + notes (slice B)

- **Date:** 2026-06-30
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/gpu_info` (based on slice A foundation)
- **Part of:** full system-info effort (A=CPU done, **B=GPU**, C=Storage next).

## Goal

Add a Graphics subsystem to the system report: detect all GPUs, classify
integrated vs discrete, report accurate VRAM, and add GPU + cross-subsystem
bottleneck notes. Reuses the slice-A subsystem pattern; no storage yet.

## Decisions (chosen by user)

- **VRAM source:** registry `HardwareInformation.qwMemorySize` for accuracy
  (AdapterRAM is a 32-bit field capped at ~4 GB), with AdapterRAM fallback.
- **GUI:** a GPU **table** (one row per GPU), consistent with the DIMM table.
- **Notes:** inactive-discrete, outdated-driver, and iGPU-limited-by-single-channel.
- Reading `HKLM` for the registry VRAM value is acceptable (read-only, no admin).

## Architecture

- **`Get-GpuInfo`** (collector) — enumerate `Win32_VideoController`; per GPU:
  Name, AdapterCompatibility (vendor), AdapterRAM, DriverVersion, DriverDate,
  CurrentHorizontalResolution/Vertical/RefreshRate, Availability, PNPDeviceID.
  Plus `Get-GpuVramMap` (collector helper) reading
  `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\NNNN`
  for `HardwareInformation.qwMemorySize`, matched to a GPU by `DriverDesc`.
- **`New-GpuReport`** (pure) — `-Gpus <rawList> -Now <datetime>` → the GPU
  section `{ Gpus = @(...) }`. Driver age uses `-Now` so it is deterministic.
- **`Get-GpuInsights`** (pure) — GPU-only notes.
- **`Get-SystemInsights`** — extended with the iGPU x single-channel cross note.
- **`New-SystemReport`** — now `-Cpu -Memory -Gpu`; the GPU section flows into
  the report and the insight engine. `Invoke-SystemInfo` collects GPUs and
  passes `(Get-Date)` as `-Now`.

## Per-GPU fields (`New-GpuReport` output, one object per GPU)

| Field | Source / logic |
|---|---|
| Name | `Win32_VideoController.Name` |
| Vendor | `AdapterCompatibility` (NVIDIA / Intel / AMD) |
| Type | `Get-GpuType` (Integrated / Discrete / Unknown) |
| VramGB | registry `qwMemorySize` -> GB; else AdapterRAM -> GB |
| VramSource | 'registry' or 'adapterRAM' (for honesty) |
| DriverVersion | `DriverVersion` |
| DriverDate | `DriverDate` |
| DriverAgeMonths | months between DriverDate and `-Now` |
| Status | Availability 3 -> 'Active', 8 -> 'Idle', else 'Unknown' |
| IsActive | Availability -eq 3 |
| IsDiscrete | Type -eq 'Discrete' |
| Resolution | `HxV@R` when present (active GPU), else '-' |

### `Get-GpuType` (pure) heuristic

Checked in order: NVIDIA / GeForce / RTX / GTX / Quadro -> Discrete; Intel
`Arc` -> Discrete; Intel / UHD / Iris / HD Graphics -> Integrated; AMD
`Radeon RX` / `Radeon Pro` / FirePro -> Discrete; AMD / Radeon / Vega ->
Integrated; otherwise Unknown.

## Insights

- **`Get-GpuInsights`** (per GPU section):
  - **Inactive discrete:** any GPU `IsDiscrete -and -not IsActive` ->
    *info:* "<name> is present but idle; apps may default to the integrated
    GPU. For demanding work, pick it in Windows Graphics settings or the
    vendor control panel."
  - **Outdated driver:** any GPU `DriverAgeMonths -gt 12` ->
    *info:* "<name> driver is ~N months old; consider updating."
- **`Get-SystemInsights`** cross note: if any GPU `Type -eq 'Integrated'` **and**
  memory is single-channel (`PopulatedSlots -eq 1 -and TotalSlots -ge 2`) ->
  *warn:* "Integrated graphics share system memory; single-channel RAM notably
  limits iGPU performance - dual-channel would help."

## GUI / console

- **GPU tab** (after CPU, before Memory): a `ListView` table, one row per GPU,
  columns: GPU, Vendor, Type, VRAM, Driver, Status. Last column fills width.
- **Overview** gains a *Graphics:* one-liner: the discrete GPU (name + VRAM) if
  present, plus the integrated one - e.g. "NVIDIA RTX 2060 Max-Q (6 GB) + Intel
  UHD Graphics".
- **Console** gains a *Graphics* section: a per-GPU table, then the notes (already
  aggregated by the engine). Tab order: Overview / CPU / GPU / Memory.

## Reference data (dev machine, 2026-06-30)

Intel UHD Graphics (Integrated, Active, drives 1920x1200, driver 2024-08) +
NVIDIA GeForce RTX 2060 Max-Q (Discrete, Idle, registry VRAM 6 GB though
AdapterRAM reports 4, driver 2025-10).

## Testing

- TDD pure units: `Get-GpuType` (NVIDIA/Intel/AMD/Arc/Unknown), `New-GpuReport`
  (registry-vs-AdapterRAM VRAM pick, driver age vs `-Now`, active/status, type),
  `Get-GpuInsights` (inactive-discrete, outdated-driver, neither), the
  `Get-SystemInsights` iGPU cross note (fires only when integrated + single-channel).
- Collector `Get-GpuInfo` + registry read: verified by the `-Console` run on
  real hardware (2 GPUs, RTX 2060 shows 6 GB, correct types/status).
- GPU tab: smoke (tab + ListView with N rows) + off-screen render.

## Out of scope (YAGNI)

- GPU utilization / temperature / live clocks (not in WMI; needs vendor APIs).
- Per-SKU GPU spec database; no GPU "max" lookups.
- Storage subsystem (slice C).
