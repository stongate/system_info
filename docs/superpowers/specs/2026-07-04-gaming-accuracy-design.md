# System Info — Gaming accuracy (laptop tiers + CPU limiter) (slice K)

- **Date:** 2026-07-04
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/gaming_accuracy` (off `main`)
- **Part of:** full system-info effort (A=CPU … I=Upgrade Advisor, J=Firmware &
  Security done, **K=Gaming accuracy**). First *revision* slice — it sharpens the
  existing Gaming synthesis (slice H) rather than adding a subsystem.

## Goal

Make the Gaming verdict honest for **laptop GPUs**, add the missing **CPU
dimension** to the limiters, fix a **spec-vs-code drift** (the promised Storage
line was never rendered), patch **tier-table gaps**, and polish the **refresh
wording**. Pure-function changes only — no new collector, no wiring changes, no
new tab.

## Why this scope (honest-data findings, dev machine 2026-07-04)

**The reference machine changed.** This slice was grounded on a **Dell XPS 17
9700** — i7-10875H (8C/16T), **RTX 2060 with Max-Q Design** (6 GB) + Intel UHD,
16 GB DDR4-2933 dual-channel, 1920×1200 @ 59 Hz (EDID preferred mode
192500/3211 ≈ 59.95 Hz), NVMe boot, Windows 11 Pro build 26200, non-admin —
*not* the XPS 15 9500 used for slice J. Findings:

| Finding | Evidence on this machine |
|---------|--------------------------|
| Laptop GPU variants tier as their desktop namesakes | `"RTX 2060 with Max-Q Design"` matches the rank-3 rule identically to a desktop 2060; Max-Q performs ≈ desktop GTX 1660 Ti (rank 2). Compounds up the stack: an `RTX 4090 Laptop GPU` would read rank 5 "4K ultra" while performing like a desktop 4070 Ti (rank 4). |
| No CPU limiter exists | `Cores` is collected and displayed but never judged — a 2-core box with an RTX 4070 reads *"Limited by: none - well balanced."* |
| Renderer drift | Slice-H spec promises per-component lines "GPU, CPU, Memory, Display, **Storage**"; `BootKind` is in the report object but neither the console section nor the tab renders it. |
| "59 Hz display" wording | The panel's preferred mode is 59.95 Hz; Windows rounds to 59. The limiter parrots the artifact. |
| Tier-table gap | `RTX 4050` (laptop-only, very common) matches no rule → "Unrecognized". |

## The honest core

- **The −1 laptop adjustment is derived-but-declared.** The GPU's own name
  declares the variant (`Max-Q`, `Laptop GPU`, AMD's `M` suffix); the one-rank
  penalty is real and generation-level — the same coarseness as the table
  itself. It is labelled: the verdict carries **"(laptop GPU)"** and the caption
  states the rule. Nothing is guessed from chassis type; only name-declared
  variants are adjusted.
- **CPU threshold is conservative** (≤ 4 cores) — 6-core machines stay clean, so
  the limiter only fires where the 2026 AAA constraint is real (no cry-wolf).
- **"60 Hz-class" is more honest than "59 Hz"** — 59 is a Windows rounding of
  the panel's 59.94/59.95 Hz mode, not a slower panel.
- **Thermals stay out of the verdict.** GPU sensors are an idle-moment snapshot;
  judging *sustained* gaming performance from idle telemetry would fabricate.
  The live thermal-throttle note already covers the real signal.

## Design

### `Get-GpuGamingTier` (pure)

- **Detect** name-declared mobile variants: `Max-?Q`, `\bLaptop\b`,
  `\bMobile\b`, or AMD `RX \d{3,4}M\b`. (Word-bounded — `Mobility` does not
  match; professional/Quadro parts are not in the table and stay Unrecognized.)
- **Normalize** before lookup: strip `with Max-Q Design` / `Laptop GPU` /
  `Laptop` / `Mobile`, and rewrite `RX <n>M` → `RX <n>`, so the base SKU hits
  its table row.
- **Adjust:** matched mobile variants drop one rank, floor 1 — unless the
  matched rule is flagged **mobile-exempt** (rules that already describe
  laptop-native or bottom-tier parts: the new `RTX 4050` row, the `MX` row, the
  iGPU row). No double penalty.
- **Output gains `MobileVariant`** (`$true|$false`).
- **Table fixes:** add `RTX 4050` → rank 2, mobile-exempt. Rank-1 label becomes
  `'esports / light 1080p'` (drops "(integrated-class)" — a discrete mobile chip
  landing there via −1 is not integrated).
- Sanity of the −1 across the range: 4090 Laptop → 4 (≈ desktop 4070 Ti ✓) ·
  3080 Laptop → 3 (≈ desktop 3070 ✓) · 2060 Max-Q → 2 (≈ desktop 1660 Ti ✓) ·
  RX 6800M → 3 ✓ · 1650 Ti Max-Q → 1 · 3050 Ti Laptop → 1 (slightly harsh,
  within coarse-bucket tolerance) · 4050 Laptop → 2 (exempt, no −1). Desktop
  names are unchanged.

### `New-GamingReport` (pure)

- **CPU limiter:** `Cores ≤ 4` → `"<n>-core CPU"` in `Limiters`.
- **Refresh wording:** limiter text for measured 59 or 60 → `"60 Hz-class
  display"`; other values keep the measured `"<n> Hz display"`. Threshold logic
  unchanged (`≤ 60`).
- **`Verdict` stays the plain (adjusted) tier label**; the report gains a
  passthrough **`MobileVariant`** field. Renderers append the qualifier (below)
  — keeps the Overview line short.

### `Get-GamingInsights` (pure)

- **New info note**, fired when `Cores ≤ 4` **and** `Rank ≥ 3` (same gating
  philosophy as the 60 Hz note — flag the CPU only when the GPU has headroom
  worth capping): *"Modern AAA games increasingly want 6+ CPU cores; a
  `<n>`-core CPU may cap frame rates even where the GPU has headroom."*
- Existing notes unchanged. **Grounded consequence:** on this machine the rank
  drops 3 → 2, so the existing "GPU can push past 60 fps" note (gated `Rank ≥
  3`) stops firing here — accepted; arguably more honest for a 2060 Max-Q.

### Renderers (console section + Gaming tab; Overview untouched in code)

- **Storage line (drift fix):** both renderers gain
  `Storage: <BootKind> boot drive` (e.g. `NVMe SSD boot drive`), `Unknown` when
  null — after `Display:`.
- **Laptop qualifier:** when `MobileVariant`, tab + console render
  `Overall: <Verdict> (laptop GPU)`. The **Overview** `Gaming:` line keeps the
  plain `Verdict` + limiters (already near its width limit; the tier itself is
  already adjusted, so the short line stays honest). Per-renderer duplication of
  the append matches the codebase's established per-renderer pattern.
- **Caption:** tab caption and the console trailing note gain the static
  sentence *"Laptop GPU variants ("Max-Q", "Laptop") are tiered one rank below
  the desktop card of the same name."*

## Reference data (dev machine, 2026-07-04 — expected after this slice)

- Overall: **"1080p mainstream / esports (laptop GPU)"** (rank 2,
  `MobileVariant = $true`; was rank 3)
- Limited by: **6 GB VRAM, 60 Hz-class display** (was "…, 59 Hz display")
- GPU: NVIDIA GeForce RTX 2060 with Max-Q Design · VRAM: 6 GB · CPU: 8 cores ·
  Memory: 16 GB dual-channel · Display: 1920×1200 @ 59 Hz ·
  **Storage: NVMe SSD boot drive** (new line)
- Notes: low-VRAM fires; 60 Hz note **no longer fires** (rank gate); no CPU note
  (8 cores).

## Testing (~15 new/updated unit tests + GUI smoke)

- **Tier:** `"…RTX 2060 with Max-Q Design"` → 2 + `MobileVariant`;
  `"…RTX 4090 Laptop GPU"` → 4; `"…RTX 3080 Laptop GPU"` → 3;
  `"AMD Radeon RX 6800M"` → 3; `"…RTX 4050 Laptop GPU"` → 2 (exempt);
  `"…GTX 1650 Ti with Max-Q Design"` → 1 (floor holds); desktop `"…RTX 2060"` →
  3, not mobile (regression); iGPU label = `'esports / light 1080p'`.
- **Report:** 4-core + rank-3 fixture → `"4-core CPU"` limiter; 6-core → none
  (boundary); refresh 59 → `"60 Hz-class display"`; 60 → same; 144 → none;
  Max-Q fixture → plain adjusted `Verdict` + `MobileVariant = $true`.
- **Insights:** cores 4 + rank 3 → note; cores 4 + rank 2 → silent; cores 8 →
  silent.
- **Console:** `Storage:` line present (`NVMe SSD boot drive` / `Unknown`
  fallback); `(laptop GPU)` qualifier on Overall when `MobileVariant`.
- **Existing fixtures updated** where expectations legitimately shift: the
  59-Hz limiter wording, any Max-Q-named fixture's rank/verdict, the rank-1
  label.
- **GUI smoke:** Gaming tab gains the `Storage:` row and the caption sentence;
  tab count stays **11**; off-screen PNG render. (Smoke runs on real hardware —
  this machine's verdict text changes as above.)

## Out of scope (YAGNI / deferred — with grounding recorded for the next slices)

- **Benchmark slice (queued next, by session decision).** Probed feasible
  2026-07-04 on this machine, all no-admin, zero-install (in-memory C# via
  `Add-Type`): CPU SHA256 406 MB/s single-thread → 2,654 MB/s all-threads (6.5×
  scale on 8C/16T; workload should switch to plain arithmetic — SHA-NI CPUs
  would skew crypto results); memory copy 19.0 GB/s single-thread vs 46.9 GB/s
  theoretical dual-channel DDR4-2933 (theoretical peak = channels × 8 B × MT/s
  is an honest, derivable reference); disk read with `FILE_FLAG_NO_BUFFERING`
  (`FileOptions 0x20000000`) works non-admin — 987 MB/s single-stream
  sequential (vs 3,735 MB/s cache-inflated without it), 5,135 IOPS random 4K.
  Shape: on-demand only (tab button + `-Benchmark` flag), never auto-run; no
  GPU pillar in v1 (no representative zero-install 3D workload; WPF would run
  on the iGPU under Optimus); no good/bad verdicts without an honest reference.
- **Displays slice (grounded viable).** `WmiMonitorID` /
  `WmiMonitorListedSupportedSourceModes` / `WmiMonitorBasicDisplayParams` all
  readable no-admin here (SHP 17.2″ panel, native 1920×1200, preferred
  59.95 Hz) — enables native-vs-current-resolution honesty and panel facts.
- **Published-FPS lookup tables** — permanent no (numbers measured on other
  machines are fabrication here; the tier labels are the honest coarse form).
- **Live FPS capture** (PresentMon-style ETW tracing) — honest but admin-gated;
  incompatible with the non-admin ethos today.
- Thermal feed into the verdict; AMD/Intel mobile handling beyond the M-suffix
  normalization; Upgrade-Advisor GPU-hardware recommendations.
