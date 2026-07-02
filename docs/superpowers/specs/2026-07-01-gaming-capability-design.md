# System Info — Gaming capability (synthesis) + memory-clock polish (slice H)

- **Date:** 2026-07-01
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/gaming_capability` (off `main`)
- **Part of:** full system-info effort (A=CPU … G=GPU sensors done, **H=Gaming**).

## Goal

A **Gaming** tab/section that grades each component through a gaming lens and
gives an **honest, coarse verdict plus named limiters** — synthesizing the
CPU/GPU/Memory/Storage/display data the tool already collects. Explicitly **no**
invented FPS numbers and **no** 0–100 score: tiers and limiters only. Bundles a
small **memory MT/s (≈MHz)** clarity footnote.

## The honest core: GPU gaming-tier lookup

`Get-GpuGamingTier -Name <string>` (pure) → `{ Rank; Label }`, a **coarse,
generation-level, best-effort** map (like the CPU `Get-CpuSpec` table), matched
by ordered regex on the GPU name (highest tier first; integrated catch; else
Unknown). Refreshed from current sources (July 2026):

| Rank | Label | NVIDIA | AMD | Intel |
|------|-------|--------|-----|-------|
| 5 | 4K ultra / max settings | RTX 5090/5080, 4090/4080 | RX 9070 XT, 7900 XTX | — |
| 4 | 1440p ultra / entry 4K | RTX 5070 Ti/5070, 4070 Ti/S/4070, 3080/3090 | RX 9070, 7900 XT/GRE, 7800 XT, 6800 XT/6900 | — |
| 3 | 1080p high / 1440p mainstream | RTX 5060 Ti/5060, 4060 Ti/4060, 3070/3060 Ti, 2060–2080 | RX 9060 XT, 7700 XT/7600, 6600 XT–6750 XT | Arc B580, A770/A750 |
| 2 | 1080p mainstream / esports | RTX 5050, 3050, GTX 1660/16xx, GTX 10xx | RX 6600, 5700/5600, 580/590 | Arc B570, A580/A380 |
| 1 | esports / light 1080p (integrated-class) | GTX 1650/1050, MX | RX 570/560, Vega, iGPU | Iris Xe, UHD |
| (null) | Unrecognized | — | — | — |

The tier is a **rough bucket, labelled "approximate"**; the precise, honest value
is the *limiters*. Sources: Tom's Hardware GPU hierarchy / best-GPUs 2026,
RankedGPU tier list 2026, PC Gamer best graphics cards.

## Architecture (synthesis, not a new collector)

- Add `ResWidth`, `ResHeight`, `RefreshHz` (nullable ints) to **`New-GpuReport`**
  output — surfacing the raw `ResH/ResV/ResRefresh` it already ingests (kept the
  existing `Resolution` string too).
- **`Get-GpuGamingTier`** (pure) — the lookup above.
- **`New-GamingReport -Gpu -Cpu -Memory -Storage`** (pure) — picks the gaming GPU
  (first discrete, else first integrated) and the display (the first GPU whose
  `RefreshHz`/resolution is populated), then emits the Gaming section:
  `{ GpuName; Rank; TierLabel; VramGB; IsDiscrete; Cores; RamGB; DualChannel;
  DisplayW; DisplayH; RefreshHz; BootKind; Verdict; Limiters=@() }`.
  `Verdict` = the tier label (or "Unrecognized GPU" when Rank is null);
  `Limiters` = the named precise bottlenecks (below).
- **`Get-GamingInsights -Gaming`** (pure) — gaming notes.
- **`New-SystemReport`** computes `$gaming = New-GamingReport …` from the sections
  it already receives, adds `Gaming` to the report, and passes it to
  `Get-SystemInsights -Gaming`. No `Invoke-SystemInfo` / collector change.

## Limiters (on the tab) and notes (`Get-GamingInsights`)

`Limiters` (listed on the Gaming tab, drawn from precise facts):
- discrete GPU VRAM `< 8` GB; single-channel RAM; RAM `< 16` GB; refresh `<= 60`
  Hz; boot drive is `HDD`; no discrete GPU.

Notes (gaming-specific only — single-channel / HDD-boot / XMP already have
notes elsewhere and are **not** duplicated):
- **Low VRAM:** discrete gaming GPU with `VramGB -lt 8` → *info:* "`<n>` GB of
  VRAM limits texture quality in modern AAA games at high settings (8 GB+ is the
  comfortable minimum today)."
- **60 Hz cap:** `RefreshHz -le 60` **and** `Rank -ge 3` → *info:* "Your GPU can
  likely push past 60 fps, but the `<hz>` Hz display caps what you see — a
  high-refresh panel would show more."
- **No discrete GPU:** `IsDiscrete -eq $false` (integrated only) → *warn:* "No
  discrete GPU — gaming is limited to esports and older titles at low settings."
- No note when the relevant data is missing.

## Presentation

- **Gaming tab** (inserted after Storage; always present — every machine can be
  assessed): a KV block — `Overall`, `Limited by`, then per-component gaming
  lines (`GPU`, `VRAM`, `CPU`, `Memory`, `Display`, `Storage`), and an
  "approximate; generation-level tiering" caption. Tab order: Overview / CPU /
  GPU / Memory / Storage / Gaming / Battery / Live / Network.
- **Overview** gains a `Gaming:` line, e.g.
  `1080p High / 1440p Mainstream (limited by 6 GB VRAM, 60 Hz)` (header panel
  grows one row).
- **Console:** a `Gaming` section before `Notes`.
- **Memory-clock polish:** a footnote on the Memory tab + the console Memory
  section: *"Speeds are MT/s (data rate); the DRAM bus clock is half — e.g.
  2933 MT/s ≈ 1467 MHz (CPU-Z's 'DRAM Frequency'; Task Manager labels MT/s as
  'MHz')."* (Presentation-only; no data change.)

## Reference data (dev machine, 2026-07-01)

RTX 2060 Max-Q (6 GB, discrete) + i7-10875H (8C/16T) + 16 GB dual-channel +
1920×1200 @ 60 Hz + NVMe SSD → Verdict **"1080p High / 1440p Mainstream"**,
Limited by **6 GB VRAM, 60 Hz**; low-VRAM + 60 Hz notes fire; CPU/RAM/SSD are not
limiters. Memory footnote reconciles the 2933 MT/s ≈ 1467 MHz confusion.

## Testing

- **Pure `Get-GpuGamingTier`:** RTX 2060 → 3; RTX 5090 → 5; RTX 5070 Ti → 4;
  GTX 1650 → 2; RX 9060 XT → 3; Arc B580 → 3; Intel Iris Xe → 1;
  "Frobozz 9000" → null (Unrecognized). (Ordering: a 5090 must not match a
  broad "50xx" low rule.)
- **Pure `New-GpuReport`:** `RefreshHz`/`ResWidth`/`ResHeight` parsed from raw
  `ResH/ResV/ResRefresh`; `-` case → nulls.
- **Pure `New-GamingReport`:** picks discrete over integrated; the dev-machine
  synthesis (verdict + 6 GB/60 Hz limiters); a high-end case (RTX 5080, 16 GB,
  144 Hz, dual-channel, NVMe) → no limiters; an integrated-only case → the
  no-discrete limiter + low rank.
- **Pure `Get-GamingInsights`:** low-VRAM info, 60 Hz info, integrated-only warn;
  a 16 GB-VRAM + 144 Hz + discrete case → no notes.
- **Wiring:** Gaming is composed into the report and its notes flow;
  `Get-SystemInsights -Gaming $null` → no note, no error.
- **Console:** `Gaming` section present; memory footnote present.
- **GUI (`GuiSmoke.ps1`):** Gaming tab present (**9 tabs** with the dev
  fixtures), Overview `Gaming:` line, memory footnote label; off-screen render.

## Out of scope (YAGNI / deferred)

HAGS & Game Mode detection, PCIe-link display (idle-ambiguous), Resizable BAR,
DirectX feature level, any numeric score / FPS estimate, per-game data, and
non-gaming display analysis (native-vs-current resolution).
