# System Info — Upgrade Advisor (synthesis) (slice I)

- **Date:** 2026-07-02
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/upgrade_advisor` (off `main`)
- **Part of:** full system-info effort (A=CPU … H=Gaming done, **I=Upgrade Advisor**).

## Goal

An **Upgrade** tab that turns the tool's scattered bottleneck findings into a
single **ranked action plan** — *"do this first, here's why, here's the expected
payoff."* It is a pure **synthesis** of data the tool already collects (like the
Gaming slice): no new collector, no invented numbers.

The Advisor is distinct from the existing **Notes / Bottlenecks** box. Notes is a
flat list of *observations*; the Advisor is a **ranked subset** of the actionable
ones, regrouped and reframed as concrete actions with a coarse impact tag. It
deliberately covers the machine's own upgradeable parts only:
**CPU / Memory / GPU driver / Storage / Battery**.

## The honest core: benefit language

Every recommendation's **Detail** is drawn **only from measured facts** — numbers
the tool already read. No prices, no invented % or FPS, no specific product SKUs,
no purchase links. `Impact` is a **coarse, hand-assigned bucket** (High / Med /
Low), labelled "approximate" — the same philosophy as the gaming tiers, not a
computed metric.

## Recommendation catalog (v1)

Each rule reads a **structured section fact** and, when it fires, emits one
recommendation. All nine map to conditions the tool already detects honestly.

| Group | Action | Fires when | Impact |
|-------|--------|-----------|--------|
| Free | Enable XMP/EXPO in BIOS | RAM running speed `<` what CPU **and** modules support | Med |
| Free | Enable virtualization (VT-x/AMD-V) | `Cpu.VirtualizationEnabled -eq $false` *(caveated — flag can be unreliable)* | Med |
| Free | Switch off the Power saver plan | active plan is Power saver | Med |
| Free | Free up disk space on `X:` | a volume `< 10%` **or** `< 25 GB` free | Med |
| Free | Update the GPU driver | any GPU `DriverAgeMonths > 12` | Low |
| Hardware | Move Windows to an SSD | boot disk `Kind -eq 'HDD'` | **High** |
| Hardware | Add a matched RAM module (dual-channel) | `PopulatedSlots -eq 1 -and TotalSlots -ge 2` | **High** |
| Hardware | Replace the worn battery | `WearPercent -ge 35` | Med |
| Hardware | Consider an NVMe SSD | boot disk `Kind -eq 'SATA SSD'` | Low |

**Detail examples (measured only):** *"Boot drive `<name>` is a mechanical HDD."*
· *"RAM runs at `<run>` MT/s; CPU and modules support up to `<target>`."* ·
*"Only 1 of `<n>` slots populated — a matched module enables dual-channel (up to
~2× bandwidth)."* · *"Holds ~`<health>`% of design capacity (`<wear>`% lost)."* ·
*"`<X>`: has `<freeGB>` GB free (`<pct>`%)."* · *"`<gpu>` driver is ~`<n>` months
old."*

The XMP `<target>` is `min(CpuMaxSpeed, min(RatedSpeeds))`, exactly as
`Get-MemoryInsights` computes it.

## Honesty calls (design decisions)

1. **Single-channel is a *Hardware* fix, not Free.** With one stick populated you
   cannot "reseat" your way to dual-channel — a matched module must be bought. It
   is therefore classed **Hardware** ("add a module"), not a free reseat.
2. **Deliberate exclusions** — these remain as observations in the Notes box but
   are **not** upgrade recommendations, because they are situational, transient,
   or safety rather than durable upgrades:
   - discrete-GPU-idle (per-app choice), GPU thermal-throttling (live alert),
     **failing-drive health** (a back-up-now safety warning, not an upgrade), all
     Wi-Fi / Ethernet notes (environmental / positional), and mixed-module-speeds
     (rare).
3. **Impact is coarse and curated** (High / Med / Low), hand-assigned per rule and
   labelled approximate.
4. **Known limitation (not introduced here):** the power plan is read only as part
   of Battery collection, so a **desktop with no battery** won't surface the
   Power-saver fix. This is an existing property of the codebase; the Advisor
   inherits it rather than adding a new collector.

## Architecture (synthesis, not a new collector)

- **`New-UpgradeReport -Cpu -Memory -Gpu -Storage -Battery`** (pure; all params
  nullable) — applies the catalog to the section objects and returns the section:

  ```
  { Recommendations = @( { Group; Action; Detail; Impact } … )   # pre-ranked
    FreeCount; HardwareCount; HasAny }
  ```

  - `Group` = `'Free'` | `'Hardware'`; `Action` = short imperative; `Detail` =
    measured why; `Impact` = `'High'` | `'Med'` | `'Low'`.
  - **Ranked once at build time:** Free group first, then within each group
    High → Med → Low, with catalog order breaking ties. Renderers only split by
    `Group` and print in order.
  - Each rule **guards its own section** (`if ($Storage) …`, `if ($Battery) …`),
    so a no-battery desktop or a no-GPU box simply skips those rules — the same
    graceful-absence path used elsewhere.
  - `HasAny` is `$false` when nothing fires (a well-configured machine).
- **No `Get-UpgradeInsights`.** The Advisor emits **no notes** and is **not**
  passed to `Get-SystemInsights` — it is pure presentation synthesis. Feeding the
  Notes box would duplicate findings that are already there.
- **`New-SystemReport`** computes `$upgrade = New-UpgradeReport …` right after the
  existing `$gaming = …` line, from the sections it already holds, and adds
  `Upgrade` to the report. **`Invoke-SystemInfo` is unchanged** (no collector).

The catalog's ranking conditions intentionally **mirror a subset of the
`Get-*Insights` conditions**, reframed as ranked actions. The two are kept aligned
by tests (a fixture that triggers a note also asserts the paired recommendation).
This small, deliberate overlap is the accepted cost of the isolated-synthesis
approach (the same choice the Gaming slice made when it re-derived its limiters).

## Presentation

- **Upgrade tab — placed last:** Overview / CPU / GPU / Memory / Storage / Gaming
  / Battery / Live / Network / **Upgrade**. It reads as the closing "what do I do
  about all this," and Overview carries no headline (by choice), so last is its
  natural home.
- **Always present, with a positive empty-state** — like Gaming, every machine can
  be assessed. When `HasAny -eq $false` the tab shows a single line: *"No upgrades
  suggested — your system is well configured for its components."* Tab count is a
  stable **+1**.
- **Layout:** two headed groups — **Free fixes**, then **Hardware upgrades** —
  each a stacked list of `• <Action> — <Detail>  (<Impact>)`. A group renders only
  when it has items. A caption reads: *"Recommendations come only from measured
  facts. Impact is a coarse estimate (High / Med / Low), not a benchmark."*
  (Stacked labels, not a ListView — the Detail text is variable-length and reads
  better unwrapped.)
- **Console:** an `Upgrade Advisor` section before `Notes`, with the same two
  groups (or the empty-state line). Included so `-Console` mode stays complete —
  the "dedicated tab only" choice was about leaving **Overview** untouched, which
  it is; console parity is a separate axis every other subsystem honors.
- **Overview:** unchanged (no new key/value line, by choice).

## Illustrative example (synthetic — for ranking clarity)

An older laptop: HDD boot, 8 GB in 1 of 2 slots, VT-x off in BIOS, GPU driver ~18
months old, Power saver active, `C:` at 6% free, battery 38% worn. The Advisor
renders:

```
Upgrade Advisor
  Free fixes
    • Enable virtualization (VT-x/AMD-V) in BIOS — appears disabled … (Med)
    • Switch off the Power saver plan — active plan caps CPU speed. (Med)
    • Free up disk space on C: — 3.1 GB free (6%). (Med)
    • Update the GPU driver — driver is ~18 months old. (Low)
  Hardware upgrades
    • Move Windows to an SSD — boot drive is a mechanical HDD. (High)
    • Add a matched RAM module (dual-channel) — 1 of 2 slots populated. (High)
    • Replace the worn battery — holds ~62% of design capacity (38% lost). (Med)
```

The real **dev-machine capture** (NVMe boot, 16 GB dual-channel — so no SSD /
dual-channel fix; Free fixes depend on live driver age / power plan, and the tab
may well show the positive empty-state) is recorded here during implementation
verification.

## Testing

- **Pure `New-UpgradeReport`** — one fixture per rule (all nine) asserting the
  right `{ Group; Action; Impact }`: RAM-below-supported → enable-XMP (Free/Med);
  VT-off → enable-virtualization (Free/Med); Power-saver → switch-plan (Free/Med);
  low-space → free-up (Free/Med); 14-month driver → update (Free/Low); HDD-boot →
  SSD (Hardware/High); single-channel → add-module (Hardware/High); 40%-wear →
  replace-battery (Hardware/Med); SATA-boot → NVMe (Hardware/Low).
- **Well-configured fixture** (NVMe boot, dual-channel, VT on, fresh driver,
  Balanced plan, healthy battery, ample space, RAM at supported speed) →
  `HasAny -eq $false`, empty `Recommendations`.
- **Ranking** — a fixture firing several rules asserts Free-before-Hardware and
  High-before-Low within a group.
- **Null-safety** — `-Battery $null -Gpu $null` → no error; those rules skipped.
- **Wiring** — `New-SystemReport` populates `.Upgrade`.
- **Console** — `Upgrade Advisor` section present with recommendations; the
  empty-state line present when nothing fires.
- **GUI (`GuiSmoke.ps1`)** — bump the assertion **9 → 10 tabs**; assert an
  `Upgrade` tab exists with the group headers (or the empty-state) and the
  caption; off-screen PNG render.

## Out of scope (YAGNI / deferred)

- Generic capacity-based "add more RAM" (use-case dependent; the single-channel
  rule already covers most low-RAM machines, and Live pressure is transient).
- Recommendations for the excluded findings above (idle GPU, thermal, failing
  drive, network) — they remain Notes.
- Cost/price bands, %/FPS estimates, specific product recommendations, purchase
  links, snapshot/history/diffing, a Refresh button, and file export — all remain
  out of scope (separate potential slices).
