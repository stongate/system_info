# System Info — Live / Load (memory pressure) + notes (slice E)

- **Date:** 2026-07-01
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/live_load` (off `main`)
- **Part of:** full system-info effort (A=CPU, B=GPU, C=Storage, D=Battery done,
  **E=Live/Load**).

## Goal

Add a **Live** tab surfacing *current* memory pressure — available RAM, commit
charge, and disk paging — plus pressure notes. This is the tool's first
**dynamic** subsystem: every value is a snapshot that changes between runs, so
all values are labelled **"right now."** Honest-data ethos throughout.

## Decisions (chosen by user)

- **Signals: memory pressure only.** No CPU live-load readout, no per-process
  breakdown, no throttle claims.
- **Presentation: a dedicated "Live" tab** (7th tab) — keeps the static tabs
  purely static ("what you have" vs. "what's happening now").
- **Tab name: "Live."**

## Why these choices (honest-data findings, dev machine 2026-07-01)

The request began as "thermals," but probing showed classic thermals are mostly
unavailable via Windows built-ins on this laptop:

- `MSAcpi_ThermalZoneTemperature` → **"Not supported."**
- `Win32_TemperatureProbe` → readings **blank**; `Win32_Fan` → RPM **blank**.
- The only real sensor source is `nvidia-smi` (vendor exe) — deferred (YAGNI).

Memory pressure, by contrast, is **honestly readable in a single snapshot**:
available bytes and commit % are *levels* (not rates), and paging is a
per-second counter the OS computes. CPU thermal-throttle is **not** reliably
detectable from a snapshot (at idle the CPU downclocks on purpose, so low
frequency ≠ throttle), so we make no throttle claim. That is why this slice is
memory-pressure-only.

## Architecture (mirrors CPU/GPU/Memory/Storage/Battery)

- **`Get-LoadInfo`** (collector, I/O; verified via `-Console`) — reads live
  counters, wrapped in try/catch:
  - `Win32_PerfFormattedData_PerfOS_Memory`: `AvailableBytes`, `CommittedBytes`,
    `CommitLimit`, `PercentCommittedBytesInUse`, `PageReadsPerSec`.
  - `Win32_ComputerSystem.TotalPhysicalMemory` (total RAM denominator).
  - Returns the raw readings, or `$null` only if the whole query fails (→ no tab,
    the same graceful-absence path as a desktop with no battery).
- **`New-LoadReport`** (pure, all inputs as params) → the Load section object.
- **`Get-LoadInsights`** (pure) → memory-pressure notes.
- Wired into **`Get-SystemInsights`** and **`New-SystemReport`** (now `-Load`,
  using the assign-sub-result-then-`+=` flattening pattern; a `$null` load is
  skipped cleanly). **`Invoke-SystemInfo`** collects raw load and builds the
  section only when present.

## Load section fields (`New-LoadReport` output)

`{ TotalPhysicalGB; AvailableGB; AvailablePercent; CommitUsedGB; CommitLimitGB;
CommitPercent; PageReadsPerSec }`

- `AvailablePercent` = `round(AvailableBytes / TotalPhysicalBytes * 100)`.
- `CommitPercent` = the raw `PercentCommittedBytesInUse` when present, else
  `round(CommittedBytes / CommitLimit * 100)`.
- `*GB` = bytes / 1GB, rounded to 1 decimal.
- Any missing input → the corresponding field is `$null` (shown "Unknown"; no
  note fires on nulls — never fabricated).

## Insights (`Get-LoadInsights`)

Levels drive the tiers; paging only *escalates* (a paging spike alone can't
false-positive):

- **warn** when `AvailablePercent -lt 10` **OR** `CommitPercent -ge 90` **OR**
  (`AvailablePercent -lt 20` **AND** `PageReadsPerSec -gt 100`):
  *"Low on memory right now: `<avail>` GB available (`<pct>`%), commit at
  `<commit>`%`<, paging to disk (~<reads>/sec)>`. Close apps or add RAM — the
  system is slowing from memory pressure."* (The paging clause appears only when
  `PageReadsPerSec -gt 100`.)
- **info** (and not warn) when `AvailablePercent -lt 20` **OR**
  `CommitPercent -ge 80`:
  *"Memory is getting tight right now: `<avail>` GB available (`<pct>`%), commit
  at `<commit>`%. Heavy multitasking may start to slow down."*
- else: no note.

Notes are phrased in present-tense "right now" language so they read as
current-state, not durable hardware facts, when they appear in the shared
Notes/Bottlenecks list.

## GUI / console

- **"Live" tab** (7th, after Battery; only when load data exists): a KV block —
  Total RAM, In use / Available (GB + %), Commit charge (used / limit + %),
  Paging (hard page-reads/sec), and a **Status** line (`OK` / `Getting tight` /
  `Under pressure`, matching the note tier). A caption notes the values are as
  of when the window opened. Tab order: Overview / CPU / GPU / Memory / Storage /
  Battery / Live.
- **Console**: a `Live / Load` section before `Notes`, in the CPU/Memory
  key/value style (present whenever load data exists — i.e. any normal machine).
- **Overview**: **no** new key/value line (respecting the dedicated-tab choice).
  Pressure still surfaces on Overview via its existing Notes/Bottlenecks box.

## Reference data (dev machine, 2026-07-01 — Dell XPS 17 9700, 16 GB)

Snapshot during the brainstorm: `AvailableMBytes` ≈ 2,258 MB (~14% of 16 GB),
`PercentCommittedBytesInUse` = 85% (46.4 of 54.5 GB), `PageReadsPerSec` ≈ 2,016.
→ **warn** tier (avail < 20% AND paging > 100). An earlier snapshot read 0.9 GB
free / 94% commit — confirming the values are genuinely transient (which is why
they are labelled "right now").

## Testing

- **Pure `New-LoadReport`:** GB/percent math from raw bytes (the reference
  numbers → 14% available, 85% commit); commit falls back to computed when the
  raw percent is absent; null inputs → null fields.
- **Pure `Get-LoadInsights`:** warn (avail 6%), warn (commit 92%), warn
  (avail 14% + paging 2,000), info (avail 18% / commit 82%), healthy (avail 60%,
  commit 40%, paging 0) → no note; paging clause present/absent by threshold.
- **Wiring:** `New-SystemReport -Load` flows notes into the report;
  `Get-SystemInsights -Load $null` → no note, no error.
- **Console:** `Live / Load` section present with a Load, absent when `$null`.
- **GUI (`GuiSmoke.ps1`):** add a Load fixture; assert **7 tabs** and a Live tab
  with its KV labels; add a no-load case (`-Load $null` → 6 tabs, no Live tab);
  plus the off-screen PNG render.

## Out of scope (YAGNI)

- CPU live-load / thermal-throttle detection (snapshot-ambiguous; would need
  sustained-load sampling), per-process memory breakdown, `nvidia-smi` GPU
  sensors, network link analysis, and any history/graphing over time.
