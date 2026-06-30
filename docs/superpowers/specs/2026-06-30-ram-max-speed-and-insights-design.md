# Show-RamInfo — Max Memory Speed + Insights (extension)

- **Date:** 2026-06-30
- **Status:** Approved (design), pre-implementation
- **Extends:** [2026-06-30-ram-info-design.md](2026-06-30-ram-info-design.md)

## Goal

Replace the "max supported speed isn't in firmware — look it up" note with an
actual number, and add a short **Notes** section calling out speed/capacity
**bottlenecks** when they exist.

## Decisions (chosen by user)

- **Which number:** the *real achievable cap* = the CPU/platform's rated max
  memory speed (JEDEC). This is what RAM will actually run at without
  overclocking. (On the dev machine: i7-10875H → DDR4-2933, which matches the
  observed running speed.)
- **Data source:** a **bundled offline table** mapping CPU generation → max DDR
  speed. No internet, no API key. Values are **generation-level** (clearly
  labeled), not a per-SKU database. Unknown CPUs fall back to the honest note —
  the tool **never invents a number**.

## New data read

- `Win32_Processor.Name` — the CPU, e.g. `Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz`.
  The CPU is the lookup key (the board code `0CXCCY` is an OEM part number, not
  usable). The report also displays the CPU name so the number is self-explanatory.

## Component: `Get-CpuMemorySpec` (pure)

`Get-CpuMemorySpec -Name <cpuString> -MemoryType <DDR4|DDR5|...>` →
`{ MaxSpeed:int; Label:string; Source:string; Known:bool }`.

When a generation supports both DDR4 and DDR5, the figure matching the installed
`MemoryType` is returned. Unknown / unparseable → `Known=$false`, `MaxSpeed=$null`.

### Parsing heuristics

**Intel Core** (`i[3579]-<model><suffix>`, or `Core Ultra <n>`):
- 5-digit model → generation = first **2** digits (`10875H`→10, `12700K`→12).
- 4-digit model → if it starts with `1`, generation = first **2** digits
  (covers 10/11/12-series low-power: `1065G7`→10, `1255U`→12); otherwise
  generation = first **1** digit (`4790K`→4, `8550U`→8, `9700K`→9).
- `Core Ultra` → series from the 3-digit number: `1xx`→Series 1 (Meteor Lake),
  `2xx`→Series 2 (Arrow/Lunar Lake).
- 3-digit / unrecognized → Unknown.

**AMD Ryzen** (`Ryzen <n> <model><suffix>`):
- Series = first digit of the 4-digit model (`5800X`→5000, `7600`→7000).
- Caveat (documented): AMD mobile rebrands can mislead (e.g. `7730U` is Zen3/DDR4
  but parses as 7000-series). Accepted as a generation-level approximation.

Non-Core / non-Ryzen (Xeon, EPYC, Threadripper, Pentium, Celeron, Atom) → Unknown.

### Bundled table (generation → JEDEC max, MT/s)

| Intel gen | DDR4 | DDR5 | Notes |
|---|---|---|---|
| 6 (Skylake) | 2133 | — | |
| 7 (Kaby Lake) | 2400 | — | |
| 8 (Coffee Lake) | 2666 | — | |
| 9 (Coffee Lake R) | 2666 | — | |
| 10 (Comet/Ice) | 2933 (H or i7/i9) else 2666 | — | dev machine = 2933 |
| 11 (Rocket/Tiger) | 3200 | — | |
| 12 (Alder Lake) | 3200 | 4800 | pick by installed type |
| 13 (Raptor Lake) | 3200 | 5600 | |
| 14 (Raptor R) | 3200 | 5600 | |
| Ultra S1 (Meteor) | — | 5600 | |
| Ultra S2 (Arrow) | — | 6400 | |

| AMD series | DDR4 | DDR5 |
|---|---|---|
| 1000 (Zen) | 2667 | — |
| 2000 (Zen+) | 2933 | — |
| 3000 (Zen2) | 3200 | — |
| 4000 (Zen2 APU) | 3200 | — |
| 5000 (Zen3) | 3200 | — |
| 6000 (Zen3+) | — | 4800 |
| 7000 (Zen4) | — | 5200 |
| 8000 (Zen4 APU) | — | 5200 |
| 9000 (Zen5) | — | 5600 |

`Source` string e.g. `"Intel Core i7-10875H rated max (JEDEC, generation-level)"`.

## Component: `Get-RamInsights` (pure)

Returns an ordered array of `{ Kind: ok|warn|info; Text:string }`, emitting only
applicable notes. Inputs: running speed, module rated speeds (array),
CPU max speed (int|null), CPU name, populated/total slots, installed GB, max
capacity GB.

Let `run` = configured/running speed, `rated` = **min** rated across populated
modules (the effective speed), `cap` = CPU max.

1. **Channel** — `populated == 1 && totalSlots >= 2` →
   *warn:* "Single-channel: only 1 of N slots populated. Adding a matched module
   would enable dual-channel (up to ~2× memory bandwidth)." (Silent otherwise.)
2. **Mixed modules** — more than one distinct rated speed →
   *warn:* "Mixed module speeds (… MT/s) — all run at the slowest (min)."
3. **Speed binding** (if `run` known):
   - `cap` known:
     - `run >= cap && rated > cap` → *ok:* running = CPU max; modules rated
       higher, CPU is the limiter (normal; faster RAM wouldn't help).
     - `run < cap && run < rated` → *warn:* both CPU (cap) and modules (rated)
       support faster; enable XMP/EXPO **if BIOS allows** to reach min(cap,rated).
     - `rated < cap && run >= rated` → *info:* running at module rated max; CPU
       supports up to `cap`, so faster modules would run faster.
     - else → *ok:* running at the max this CPU and these modules support.
   - `cap` unknown:
     - `run < rated` → *warn:* below module rating; enable XMP/EXPO if BIOS allows.
     - else → *ok:* running at module rated speed.
4. **Capacity** (if max capacity known):
   - `freeSlots > 0` → *info:* "N free slot(s) — can add up to `maxcap` GB total."
   - `installed < maxcap` → *info:* "All slots full at `installed` GB; max is
     `maxcap` GB — adding more means replacing modules with larger ones."
   - else → *ok:* "At maximum capacity (`maxcap` GB)."

## Report object additions (`New-RamReport`)

New params `-CpuName [string]`, `-CpuMaxSpeed [object=$null]` (resolved int or
null, computed by the caller via `Get-CpuMemorySpec`). New fields:
`CpuName`, `MaxSpeedLabel` (e.g. `DDR4-2933` or `$null`), `MaxSpeedSource`,
`MaxSpeedKnown`, `Insights` (from `Get-RamInsights`).

`Invoke-RamInfo` wires it: collect CPU name via new thin `Get-CpuInfo`, resolve
`Get-CpuMemorySpec`, pass name + number into `New-RamReport`.

## UI / console changes

- **Summary** gains two rows: `Processor: <name>` and
  `Max speed (CPU): DDR4-2933` (or `Unknown — see board spec` when not known).
- **Notes** section:
  - Console: a `Notes:` block, one bullet per insight.
  - GUI: a read-only, scrollable multiline TextBox above the buttons; window
    height grows to fit. Each line prefixed with `• `.
- The old orange "not in firmware" footnote is removed (replaced by the real
  number, or the fallback wording inside the Max-speed row when unknown).

## Honesty / accuracy

- Always labeled as the CPU's platform/JEDEC max (generation-level).
- Never shows a number for an unrecognized CPU — falls back to the spec note.
- XMP/EXPO advice is hedged ("if your BIOS allows"), since OEM systems often lock it.

## Testing

- `Get-CpuMemorySpec`: TDD across Intel gens 6–14 + Ultra S1/S2, the tricky
  4-digit cases (`1065G7`, `1255U` vs `4790K`, `9700K`), AMD series 1000–9000,
  DDR4-vs-DDR5 selection, and Unknown (Xeon/Pentium/garbage).
- `Get-RamInsights`: TDD every branch (CPU-capped, config-limited, module-limited,
  balanced, single-channel, mixed-speed, free-vs-full capacity, CPU-unknown).
- `New-RamReport`: existing tests still pass; add checks for the new fields.
- CIM collector `Get-CpuInfo`: thin, verified by the `-Console` run on real HW.
- GUI: smoke test (Notes TextBox present) + off-screen PNG render reviewed.

## Out of scope (YAGNI)

- No online/AI lookup, no scraping, no per-SKU database.
- No board-advertised "OC" speeds.
- No DDR generation upgrade advice beyond the capacity note.
