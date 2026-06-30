# System Info — Battery / power + notes (slice D)

- **Date:** 2026-06-30
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/battery_info` (off `main`)
- **Part of:** full system-info effort (A=CPU, B=GPU, C=Storage done, **D=Battery**).

## Goal

Add a Battery/power subsystem: current charge %, AC/charging status, **battery
health/wear** (the valuable part), and the active power plan — with a Battery
tab, an Overview line, a console section, and bottleneck notes. Reuses the
established per-subsystem pattern. Honest-data ethos: never fabricate; label
derived/best-effort values; degrade cleanly when data is missing.

## Decisions (chosen by user)

- **Wear note — two tiers:** info at **≥20%** wear, warn at **≥35%** wear.
- **No low-charge note** — charge % is shown, but live charge level is transient
  and not treated as a bottleneck (no transient low-battery alert).
- **No-battery (desktop):** the **Overview line is always present** (shows
  `none (AC only)`); the **Battery tab and console section appear only when a
  battery exists**. No empty tab on desktops.

## Why these data sources (grounded in the dev machine, see below)

On the dev laptop, the "obvious" sources are partly empty, which drove the design:

- `Win32_Battery.DesignCapacity` / `.FullChargeCapacity` are **blank**, and
  `root\wmi BatteryStaticData` returns **nothing**. So design-vs-full capacity
  (needed for wear) comes from **`powercfg /batteryreport /xml`**.
- **Cycle count is unreliable** — firmware reports `0` (both the WMI class and
  the battery report). Treat `0` as "not reported"; never display a fake `0`.
- The **modern power-mode slider/overlay** is not reachable here
  (`powercfg /overlaylist` → "Invalid Parameters"; would need undocumented
  P/Invoke). "Active power plan" therefore means the **legacy active scheme**,
  and the Power-saver note keys off the **universal Power-saver GUID**
  (`a1841308-3541-4fab-bc81-f71556f20b4a`), locale-independent.

## Architecture

Two new **pure parsers** (unit-tested against captured fixtures), plus the
standard collector → builder → insights chain:

- **`ConvertFrom-BatteryReportXml`** (pure) — `-Xml <string>` →
  `{ DesignCapacityMWh; FullChargeCapacityMWh; CycleCount; Chemistry;
  Manufacturer; SerialNumber }`. Reads the **`Batteries/Battery`** node
  specifically (a bare `//DesignCapacity` also matches a second, time-suffixed
  node like `95065PT4H33M44S…` — must scope to the battery node). First
  `<Battery>` only. Missing/empty fields → `$null`.
- **`ConvertFrom-ActiveScheme`** (pure) — `-Text <string>` → `{ Guid; Name }`
  from `powercfg /getactivescheme` output (e.g.
  `Power Scheme GUID: 381b4222-…df2e  (Balanced)`). GUID is the robust key.
- **`Get-BatteryInfo`** (collector, I/O; verified via `-Console`) — returns
  `$null` when there is no `Win32_Battery` instance (desktop). Otherwise gathers
  and **normalizes** to raw fields, wrapped in try/catch:
  - `ChargePercent` ← `Win32_Battery.EstimatedChargeRemaining` (fallback:
    `root\wmi BatteryStatus` RemainingCapacity / `BatteryFullChargedCapacity`).
  - `IsOnAC` / `IsCharging` ← `root\wmi BatteryStatus` (PowerOnline / Charging /
    Discharging); fallback to mapping the `Win32_Battery.BatteryStatus` enum.
  - capacities / cycle / chemistry / maker ← `powercfg /batteryreport /xml` to a
    `%TEMP%` file → `ConvertFrom-BatteryReportXml`, then **delete the temp file**.
  - `PowerPlan` / `PowerPlanGuid` ← `powercfg /getactivescheme` →
    `ConvertFrom-ActiveScheme`.
- **`New-BatteryReport`** (pure) — all inputs as params → the Battery section.
- **`Get-BatteryInsights`** (pure) — battery notes.
- Wired into **`Get-SystemInsights`** and **`New-SystemReport`** (now
  `-Battery`), using the assign-sub-result-then-`+=` flattening pattern; a
  `$null` battery is skipped cleanly. **`Invoke-SystemInfo`** collects the raw
  battery and builds the section only when present.

## Battery section fields (`New-BatteryReport` output)

`{ ChargePercent; IsOnAC; Status; DesignCapacityMWh; FullChargeCapacityMWh;
WearPercent; HealthPercent; CycleCount; Chemistry; Manufacturer; PowerPlan;
PowerPlanGuid }`

- **`WearPercent`** = `clamp(round((Design − Full) / Design × 100), 0, 100)`;
  `$null` if design capacity is missing or 0 (no fabricated wear).
- **`HealthPercent`** = `100 − WearPercent` (`$null` when wear is `$null`).
- **`CycleCount`** = `$null` when the raw value is 0 or absent ("not reported").
- **`Status`** derived from `(IsOnAC, IsCharging, ChargePercent)`:
  - not on AC → `On battery (discharging)`
  - on AC and charging → `Charging`
  - on AC, not charging, charge ≥ 99 → `Fully charged (on AC)`
  - on AC, not charging, charge < 99 → `On AC (not charging)`
- **`Chemistry`** maps known report codes to friendly names (e.g. `LiP` →
  `Lithium Polymer`, `Li-I`/`LION` → `Lithium-ion`); unknown codes pass through.

## Insights (`Get-BatteryInsights`)

- **Significant wear:** `WearPercent ≥ 35` → *warn:* "Battery is significantly
  worn — it holds about `<Health>`% of its original design capacity (~`<Wear>`%
  lost). Runtime is much shorter than when new; consider replacement."
- **Noticeable wear:** `20 ≤ WearPercent < 35` → *info:* "Battery shows
  noticeable wear — it holds about `<Health>`% of its design capacity
  (~`<Wear>`% lost)."
- **Power saver plan:** `PowerPlanGuid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a'`
  **or** `PowerPlan -match 'saver'` → *warn:* "Active power plan is 'Power
  saver', which caps CPU speed to save energy. Switch to Balanced or High
  performance for full performance."
- No note when `WearPercent` is `$null` or `< 20`. No low-charge note.

## GUI / console

- **Overview** gains a `Battery:` line (always present). With a battery:
  `100%  -  Fully charged (on AC)  -  45% worn  -  Balanced` (wear segment
  omitted when `WearPercent` is `$null`). Desktop: `none (AC only)`. The
  Overview header panel (`$ovTop`) grows by one row (~20 px).
- **Battery tab** (only when a battery exists; after Storage — tab order
  Overview / CPU / GPU / Memory / Storage / Battery): a KV block with Charge,
  Status, Power source, Health (`55% of design — 45% worn`), Design capacity
  (`95,065 mWh`), Full-charge capacity (`52,166 mWh`), Cycle count
  (`Not reported`), Chemistry (`Lithium Polymer`), Manufacturer, Power plan.
- **Console** gains a `Battery` section (only when a battery exists), before
  `Notes`, in the same key/value style as CPU/Memory.

## Reference data (dev machine, 2026-06-30 — Dell XPS 17 9700)

`Win32_Battery`: charge 100%, `BatteryStatus=2` (on AC, not charging),
DesignCapacity/FullChargeCapacity **blank**. `root\wmi BatteryStatus`:
PowerOnline=True, Charging=False, Discharging=False. `powercfg /batteryreport`:
DesignCapacity **95,065 mWh**, FullChargeCapacity **52,166 mWh**, CycleCount 0,
Chemistry `LiP`, Manufacturer `SMP`, Id `DELL 01RR3YM`. `powercfg
/getactivescheme`: Balanced (only scheme present).

→ Produces: charge 100%, `Fully charged (on AC)`, **Health 55% / Wear 45% →
warn note fires**, cycles `Not reported`, Lithium Polymer, plan Balanced (no
power-saver note). The captured battery-report XML becomes the parser fixture.

## Testing

- **Pure units (TDD):**
  - `ConvertFrom-BatteryReportXml`: real XML fixture → 95065 / 52166 / 0 / `LiP`;
    the double-`DesignCapacity`-node trap (picks the battery node); empty/garbage
    XML → `$null`s.
  - `ConvertFrom-ActiveScheme`: Balanced line → GUID + `Balanced`; Power-saver
    line → its GUID + name.
  - `New-BatteryReport`: wear math (95065/52166 → 45% worn, 55% health); wear
    `$null` when design missing/0; all four `Status` strings; cycle 0 → `$null`.
  - `Get-BatteryInsights`: wear 45 → warn, wear 25 → info, wear 10 → none;
    power-saver GUID → warn, Balanced → none, name-only `Power saver` → warn.
  - `Get-SystemInsights -Battery $null`: no battery notes, no error.
  - `New-SystemReport`: Battery section present and battery notes flow through.
- **Collector `Get-BatteryInfo` + cmdlets:** verified by the `-Console` run on
  real hardware (charge, wear, plan).
- **GUI (`GuiSmoke.ps1`):** add a battery to the fixture; assert **6 tabs** and a
  Battery tab with its KV labels; add a **no-battery** case (`-Battery $null` →
  no Battery tab, Overview reads `none (AC only)`); plus the off-screen PNG
  render check.

## Out of scope (YAGNI)

- Modern power-mode **slider/overlay** (unreachable via `powercfg` here; would
  need undocumented P/Invoke).
- Runtime-remaining estimate (sentinel/garbage on AC), per-cell voltage,
  temperature, charge-history graphs.
- Multi-battery aggregation — use the first battery only.
