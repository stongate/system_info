# System Info — Tab consolidation (12 → 10 GUI tabs) (slice N)

- **Date:** 2026-07-06
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/tab_consolidation` (off `main`)
- **Part of:** full system-info effort (A=CPU … L=Benchmarks, M=Startup progress
  done, **N=Tab consolidation**). A **GUI-only presentation** slice — no
  collector, no pure-function, no console change.

## Goal

The GUI reached **12 tabs** (slice L added Benchmark), and the tab strip now
**overflows** on a normally-sized window: WinForms shows `◄ ►` scroll arrows and
clips the tail (`Firmware & Security`, `Upgrade`) — verified on the dev machine
at a ~777 px window. Consolidate related subsystems into **10 tabs** that fit
comfortably, improving grouping without losing any information.

Scope is deliberately tight: **only `New-SystemForm` (the WinForms renderer) and
`GuiSmoke.ps1`** change. No collector, builder, insight, or console renderer is
touched — so `-Console` / `-Benchmark` output stays **byte-identical**, and the
honest per-subsystem structure is preserved everywhere except the GUI's tab
grouping.

## Why this scope (grounded, dev machine 2026-07-06)

Root cause is structural, not cosmetic: the `TabControl` is single-row
(`Multiline` defaults to `$false`), so 12 tabs — one of them the 19-character
`Firmware & Security` — cannot fit one row even at ~820 px. Three fixes were
mocked (two-row `Multiline`; shorten-labels-and-widen; consolidate). **Consolidate
was chosen** for the best information architecture: it merges views that are
already logically one subsystem, and 10 tabs fit one clean row with real
breathing room.

The merges are **honest groupings of data the tool already relates:**
- **Gaming is a synthesis of GPU data** (slice H) and the **live GPU sensor
  panel already lives on the GPU tab** — so GPU + Gaming + sensors is one
  "Graphics" story.
- **Battery and Live load are the two "right now" gauges** — power state and
  memory pressure — so they pair as "Power". (Accepted tradeoff: on a desktop
  with no battery, the Power tab shows only the Live-load section. The
  alternative — folding Live into Memory — was considered and set aside in
  favor of grouping the two live gauges.)

## Design

### Tab set & order (10)

`Overview · CPU · Graphics · Memory · Storage · Power · Benchmark · Network ·
Security · Upgrade`

- **Graphics** takes GPU's old slot (right after CPU).
- **Power** sits where Battery/Live were.
- **Security** is the renamed `Firmware & Security`.
- Overview, CPU, Memory, Storage, Benchmark, Network, Upgrade are unchanged in
  content and relative order.

### Graphics tab — always present (every machine has a GPU assessed)

Three stacked sections, top to bottom, in an **`AutoScroll = $true`** page (three
sections is the one place vertical space gets tight on a minimum-size window; the
scroll is the safety net, not the expected state):

1. **GPU adapters** — the existing `Details` ListView (GPU / Vendor / Type /
   VRAM / Status / Driver), with its width-fill behavior on the GPU-name column
   preserved via anchoring.
2. **GPU sensors (live, via nvidia-smi)** — the existing sensor block
   (Temperature / Utilization / Core clock / Power draw / Perf. state, + Thermal
   when throttling), rendered **only when `$Report.GpuSensor` is present** —
   identical guard to today.
3. **Gaming** — the existing verdict block (Overall / Limited by / GPU / VRAM /
   CPU / Memory / Display / Storage) + the two-line "approximate tiering" caption,
   rendered when `$Report.Gaming` is present (always, when a GPU exists). A small
   bold **"Gaming"** sub-header separates it from the sensor section above.

### Power tab — present when `$Report.Battery` **or** `$Report.Load` exists

Two stacked sections, each under a small bold sub-header:

1. **Battery** (when `$Report.Battery`) — the existing block (Charge / Status /
   Power source / Health / Design capacity / Full-charge capacity / Cycle count /
   Chemistry / Manufacturer / Power plan).
2. **Live load** (when `$Report.Load`) — the existing block (Total RAM /
   Available / Commit charge / Paging / Status) + the "(live values…)" caption.

Graceful absence: no battery **and** no load → **no Power tab** (matches today's
"tab only when its data exists"). Desktop (no battery, has load) → Power tab with
only the Live-load section. Laptop → both sections.

### Security tab

Identical content and guards to today's `Firmware & Security` tab (firmware
block + Windows 11 readiness checklist + honesty caption); **only the tab label
changes to `Security`**. Overview already carries a `Security:` row, so the short
label reads consistently.

### Unchanged

- **Overview tab** — its summary rows (Processor / Graphics / Memory / Storage /
  Battery / Network / Gaming / Security) are independent of the drill-down tabs
  and stay exactly as-is.
- **Console (`Write-SystemConsole`)** — no tabs; keeps printing every section
  (GPU, Gaming, Battery, Live/Load, Firmware & Security, …) in the same order.
  `-Console` / `-Benchmark` output is byte-identical to before this slice.
- **All collectors, builders, insights, and the report object** — untouched.
- The Benchmark tab (and its Run-click handler / closure captures from slice L)
  moves position in the strip but its code is otherwise unchanged.

### Layout note (implementation risk, called out)

Mixing the GPU ListView (which today docks to fill width) with the stacked
sensor + Gaming sections on one page is the only non-trivial layout work. The
plan will use explicit vertical stacking (anchored ListView at a fixed height +
absolutely-positioned sections below, or docked panels) with `AutoScroll` so
nothing clips at the 560 px minimum window size. Verified via the off-screen PNG
render during implementation.

## Testing (GuiSmoke only)

The GUI has no unit tests; `GuiSmoke.ps1` is its test. The pure-function unit
suite (457) is **unaffected** — no builder/insight/console code changes.

- **Tab count** — full fixture **12 → 10**; the tab-names assertion becomes
  `Overview / CPU / Graphics / Memory / Storage / Power / Benchmark / Network /
  Security / Upgrade`.
- **Desktop fixture** (no battery, no load, no network) — **9 → 8**
  (`Overview / CPU / Graphics / Memory / Storage / Benchmark / Security /
  Upgrade`); assert **no Power tab** and no Network tab.
- **Graphics tab** — contains the GPU ListView (2 adapter rows in the fixture),
  the **gaming verdict** ("1080p mainstream", "(laptop GPU)", the "one rank
  below" caption), and — in the sensor fixture — the **nvidia-smi** panel.
- **Power tab** — contains the **battery** labels (Cycle count, design capacity,
  "45% worn") **and** the **live-load** labels (Commit charge, "Under pressure").
- **Security tab** — present, labelled `Security`, with the Windows 11 readiness
  checklist and honesty caption; Overview still has its `Security:` row.
- **Run-click regression guard** (from slice L) — still fires the real handler on
  the (repositioned) Benchmark tab and stays green.
- All via the off-screen `DrawToBitmap` render; the merged tabs must show every
  section without clipping at the default window size.

## Out of scope (YAGNI)

- No `Multiline` fallback (10 tabs fit one row; the whole point was to avoid the
  two-row strip).
- No console/Overview restructure; no new data; no icons on tabs; no
  left-side/vertical tab styling.
- No change to which subsystems are collected or how they're judged.
