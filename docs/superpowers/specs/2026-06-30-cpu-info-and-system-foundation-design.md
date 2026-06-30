# System Info — CPU detail + subsystem foundation (slice A)

- **Date:** 2026-06-30
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/cpu_info`
- **Part of:** the larger "full system info + bottleneck analyzer" effort
  (slice A of A=CPU, B=GPU, C=Storage — one subsystem per branch).

## Goal

Turn the RAM-shaped tool into a system-info tool with an extensible
subsystem architecture, add a CPU section, and grow the insight engine with
RAM/CPU bottleneck notes — without building GPU/storage yet (YAGNI).

## Decisions (chosen by user)

- **CPU depth:** WMI facts + derived codename. No boost clock / instruction
  sets / TDP (not in WMI; would need fragile per-SKU tables).
- **Naming:** rename to "System Info", including the distributed files.
- **Layout:** tabbed window with an Overview tab.
- **Foundation:** light refactor to a reusable subsystem pattern now.
- **Build order:** one subsystem per branch; GPU and Storage are later slices.

## Architecture (the refactor)

Pure, independently testable units:

- **Subsystem builders** (each returns a section object, no CIM inside):
  - `New-CpuReport` — raw CPU CIM + `Get-CpuSpec` → CPU section.
  - `New-MemoryReport` — today's `New-RamReport` memory logic → Memory section
    (the CPU-speed + insight composition moves up to `New-SystemReport`).
- **`New-SystemReport`** — composer: calls the subsystem builders, runs
  `Get-SystemInsights`, returns `{ Cpu; Memory; Insights }`.
- **Insight engine:**
  - `Get-MemoryInsights` — renamed from `Get-RamInsights` (speed/channel/
    capacity notes; unchanged behavior).
  - `Get-CpuInsights` — new; CPU-only notes (virtualization disabled).
  - `Get-SystemInsights` — orchestrator: aggregates the per-subsystem helpers
    **plus** cross-subsystem notes that need multiple sections (cores-vs-
    bandwidth). This is the unit that grows into "full system bottlenecks".
- **Renderers** consume the system report: `Write-SystemConsole`,
  `New-SystemForm` (tabbed), `Show-SystemWindow`.
- **Entry:** `Invoke-SystemInfo -Console`; test env flag `SYSTEMINFO_NOMAIN`.

### Collectors

Add `Get-CpuInfo` fields (extend the existing thin collector): Name,
NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed, L2CacheSize,
L3CacheSize, SocketDesignation, AddressWidth, VirtualizationFirmwareEnabled.

## CPU section (`New-CpuReport` output)

| Field | Source |
|---|---|
| Name | `Format-CpuName` (cleaned) |
| Vendor | `Get-CpuSpec` |
| Cores / Threads | `NumberOfCores` / `NumberOfLogicalProcessors` |
| BaseClockGHz | `MaxClockSpeed` / 1000 (WMI exposes base, not boost) |
| L2CacheMB / L3CacheMB | `L2CacheSize` / `L3CacheSize` (KB → MB) |
| Socket | `SocketDesignation` (may be generic, e.g. "CPU 1") |
| Arch64 | `AddressWidth` == 64 |
| VirtualizationEnabled | `VirtualizationFirmwareEnabled` (bool / null) |
| Codename + GenerationLabel | derived (see below) |
| MaxMemSpeedLabel | `Get-CpuSpec` (existing) |

Null/blank fields render as "Unknown".

### `Get-CpuSpec` (was `Get-CpuMemorySpec`, extended)

Same parse, now also returns `Codename`, `GenerationLabel`, `Vendor`
(existing `MaxSpeed`/`Label`/`Known` kept). Codename from generation/series:

- **Intel:** 6 Skylake · 7 Kaby Lake · 8/9 Coffee Lake · 10 Comet Lake
  (G-suffix → Ice Lake) · 11 Rocket Lake (G/U-suffix → Tiger Lake) ·
  12 Alder Lake · 13 Raptor Lake · 14 Raptor Lake Refresh ·
  Ultra S1 Meteor Lake · Ultra S2 Arrow Lake. GenerationLabel e.g. "10th Gen".
- **AMD:** 1000 Zen · 2000 Zen+ · 3000/4000 Zen 2 · 5000 Zen 3 · 6000 Zen 3+ ·
  7000/8000 Zen 4 · 9000 Zen 5. GenerationLabel e.g. "Ryzen 5000".
- Unknown CPU → Codename/GenerationLabel null.

## Insight additions

- **`Get-CpuInsights`:** if `VirtualizationEnabled` is explicitly `False` →
  *warn:* "Virtualization (VT-x/AMD-V) appears disabled in BIOS. Enable it for
  Hyper-V, WSL2, Docker, or VM software." (Hedged — the WMI flag can be
  unreliable; only fires on explicit False, not null.)
- **`Get-SystemInsights` cross note:** single-channel **and** cores ≥ 6 →
  *info:* "N cores share single-channel memory bandwidth; dual-channel would
  help multi-core workloads noticeably."
- All existing memory notes (speed binding, channel, mixed, capacity) retained
  via `Get-MemoryInsights`.

## GUI (`New-SystemForm`, tabbed)

`TabControl` with tabs:
- **Overview** — one line per subsystem (CPU summary, RAM summary) + the Notes
  panel (scrollable, all insights).
- **CPU** — two-column key/value of the CPU section fields.
- **Memory** — today's summary block + per-DIMM `ListView` (with the
  fill-last-column behavior).

`Copy` (exports the full multi-section text report) and `Close` sit **below**
the tab control, always visible. Window retitled "System Info".

## Console (`Write-SystemConsole`)

Sections in order: **Processor** (key/value), **Memory** (today's block +
module table), **Notes**. Same plain-text form the Copy button reuses.

## File / symbol renames

- `git mv Show-RamInfo.ps1 Show-SystemInfo.ps1`
- `git mv RamInfo.cmd SystemInfo.cmd` (update its internal `-File` target)
- `git mv tests/RamInfo.Tests.ps1 tests/SystemInfo.Tests.ps1` (update dot-source)
- `tests/GuiSmoke.ps1` keeps its name; update dot-source + tab assertions.
- Symbols: `Invoke-RamInfo`→`Invoke-SystemInfo`, `New-RamForm`→`New-SystemForm`,
  `Show-RamWindow`→`Show-SystemWindow`, `Write-RamConsole`→`Write-SystemConsole`,
  `New-RamReport`→`New-MemoryReport`, `Get-RamInsights`→`Get-MemoryInsights`,
  `Get-CpuMemorySpec`→`Get-CpuSpec`, env `RAMINFO_NOMAIN`→`SYSTEMINFO_NOMAIN`.

## Testing

- TDD the new pure units: `New-CpuReport`, codename derivation in `Get-CpuSpec`,
  `Get-CpuInsights`, `Get-SystemInsights` (aggregation + cross note),
  `New-SystemReport` (composition).
- Renames are a refactor — update call sites, keep the suite green.
- GUI: smoke test asserts a `TabControl` with Overview/CPU/Memory tabs and the
  Notes box; off-screen PNG render reviewed.
- Console + GUI verified on real hardware (`-Console` run, render).
- Zero-dependency test harness retained.

## Out of scope (YAGNI)

- GPU and Storage subsystems (later branches).
- Boost clock, instruction-set flags, TDP.
- Per-SKU CPU database; codename stays generation-level.
- No repo rename (stays `memory_checker`); revisit later if desired.
