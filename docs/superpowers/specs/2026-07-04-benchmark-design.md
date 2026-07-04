# System Info — Benchmarks (on-demand CPU / memory / disk) (slice L)

- **Date:** 2026-07-04
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/benchmark` (off `main`)
- **Part of:** full system-info effort (A=CPU … J=Firmware & Security, K=Gaming
  accuracy done, **L=Benchmarks**). First **on-demand prober** slice — the tool's
  first active measurement (everything before this reads passive state) and its
  first GUI interactivity beyond Copy/Close.

## Goal

A **Benchmark** tab (and `-Benchmark` console switch) that measures **CPU
arithmetic throughput, memory copy bandwidth, and disk read speed** on *this*
machine, on demand — zero-install, no-admin, **never auto-run**. Results are
labeled measurements given meaning only by **references the machine itself can
derive** (memory theoretical peak, multi/single-thread scaling). Explicitly
**not** gaming FPS, not a 0–100 score, and no good/bad verdicts.

## Why this scope (feasibility probed 2026-07-04, dev machine)

Grounded on the Dell XPS 17 9700 (i7-10875H 8C/16T, 16 GB DDR4-2933
dual-channel, SK hynix PC611 NVMe behind RAID/VMD, Windows 11 Pro 26200,
non-admin). Probes ran under **both** pwsh 7 and — decisively — **Windows
PowerShell 5.1** (the `SystemInfo.cmd` runtime, .NET Framework):

| Fact | Result on 5.1 (the real runtime) |
|------|----------------------------------|
| In-memory C# via `Add-Type` | Works; **0.48 s** compile (one-time per session — negligible UX lag) |
| CPU plain-arithmetic workload | 1,014 Mops/s single-thread → 11,080 all-threads (**10.9×** on 8C/16T; `Parallel.For` fine on .NET Framework) |
| Memory copy bandwidth | 19.3 GB/s single-thread (matches pwsh's 19.0 — runtime-independent) |
| Cache-bypass disk read (`FileOptions 0x20000000` = `FILE_FLAG_NO_BUFFERING`) | **Works no-admin on .NET Framework**: 1,186 MB/s sequential |
| Random-4K QD1 read (pwsh probe) | 5,135 IOPS (~20 MB/s) — the honest single-stream number |
| Cache-inflation control | Buffered read of a just-written file: 3,735 MB/s — proves the bypass flag is load-bearing |

Two scope-shaping findings:
- **SHA256 was rejected as the CPU workload**: the pwsh probe used SHA256 (406 →
  2,654 MB/s, 6.5×), but SHA-NI-capable CPUs (Ice Lake+, Zen) accelerate it in
  hardware, skewing cross-machine comparisons — and its 6.5× vs the arithmetic
  mix's 10.9× shows scaling is workload-defined. A plain integer+float mix
  (xorshift + multiply-add) has no such instruction-set trap.
- **File-level I/O benchmarking works where SMART didn't**: the RAID/VMD bus
  that blocks reliability counters (slices D/K grounding) does not block
  ordinary unbuffered file reads. Disk *speed* is measurable here even though
  disk *health detail* is not.
- The dev machine was **under memory pressure during grounding** (1 GB
  available, 7%) — a live demonstration of why the memory stage needs an
  availability guard rather than blindly allocating 512 MB.

## The honest core

- **Every number is a labeled measurement**, stamped with its conditions:
  workload named, **short-burst** (seconds, not sustained — no thermal-soak
  claims), disk marked **single-stream/QD1** (*"what one app reading a file
  sees — spec-sheet numbers need deep queues"*), plus a context line built from
  data the tool already collects: on AC / battery, active power plan (when a
  battery section exists), and the run timestamp.
- **References are derivable-only** (user decision): memory theoretical peak =
  `channels × 8 B × MT/s` (honest math from the Memory section; channels
  estimated as `min(populated slots, 2)`, labeled *"assumes a dual-channel
  platform — typical"*), and the multi/single-thread **scale factor**, labeled
  workload-specific. **No shipped comparison tables, no "good/bad", no
  percentile claims.** "Is this good?" stays unanswered by design; the numbers
  gain value across runs and machines.
- **The CPU unit is nominal**: "arith Mops/s" counts this workload's operations,
  labeled *"this tool's arithmetic mix — comparable across runs of this tool,
  not to other benchmarks."* No instructions-per-second claim.
- **Never auto-run.** The tool's contract is a fast passive snapshot; an active
  load must be user-initiated every time (button / switch).
- **Read-only disk measurement.** The temp file's setup *write* is not reported
  (cache-buffered, uncontrolled) — no write benchmark in v1 (SSD wear +
  honesty).
- **Guards, never crashes, never fabricates**: memory stage skipped below
  **2 GB available** RAM (reason shown); disk stage skipped below **5 GB free**
  on the target drive (reason shown); every stage try/catch → that line renders
  `Unavailable (<reason>)`; the temp file is deleted in `finally`.

## Architecture (on-demand prober — a new, fourth pattern)

Passive slices are collector → builder → insights → renderers. Benchmarks are
**user-triggered I/O** with a pure shaping core:

- **`Invoke-BenchmarkSuite [-OnStage {scriptblock}]`** (I/O, timed; not
  unit-tested, per the house rule for collectors). Contains the `Add-Type` C#
  (compiled once per session). Reads free RAM (`Win32_OperatingSystem`) and
  free disk space at run time, applies the guards, runs the stages in order —
  invoking `-OnStage 'CPU (single-thread)…'` etc. before each so the GUI status
  label / console progress lines can narrate — and returns a **raw bundle**:

  ```
  { CpuStMops; CpuMtMops; ThreadCount;
    MemStGBps; MemMtGBps; MemSkippedReason;
    DiskSeqMBps; DiskRandIops; DiskSkippedReason; DiskDrive;
    ElapsedS }
  ```

  Numeric fields are `$null` when a stage failed or was skipped; skip reasons
  are short strings (e.g. `'low available memory (1.0 GB)'`). A total failure
  returns a bundle of nulls — never throws to the caller.

- **Stage details (fixed v1):**
  | Stage | Working set | Duration | Metric |
  |-------|-------------|----------|--------|
  | CPU single-thread | registers only | ~1.5 s | arith Mops/s (xorshift + multiply-add) |
  | CPU all-threads | per-thread registers | ~2.0 s | arith Mops/s via `Parallel.For` over `ProcessorCount` |
  | Memory copy 1-thread | 2 × 256 MB buffers | ~1.5 s | GB/s (bytes touched = 2× copied; buffers ≫ L3 so cache can't lie) |
  | Memory copy all-threads | same buffers, sliced per thread | ~1.5 s | GB/s |
  | Disk sequential | 512 MB temp file in `$env:TEMP`, 1 MB unbuffered reads | time-capped 4 s (HDDs may not finish — MB/s over bytes actually read) | MB/s |
  | Disk random 4K | same file, aligned 4 KB unbuffered reads | ~2 s | IOPS (+derived MB/s) |

  Total ≈ 10–13 s + one-time ~0.5 s compile.

- **`New-BenchmarkReport -Raw <bundle> -Memory <section> -Battery <section> -RanAt <datetime>`**
  (pure, deterministic, unit-tested) → the section object:

  ```
  { Cpu     = { StMops; MtMops; Scale; Threads }          # Scale = Mt/St, 1 decimal
    Memory  = { StGBps; MtGBps; TheoreticalGBps; ChannelAssumption; SkippedReason }
    Disk    = { Drive; SeqMBps; RandIops; RandMBps; SkippedReason }
    Context = { OnAC; PowerPlan; RanAt }
    Ok }                                                   # $true if any stage measured
  ```

  - `TheoreticalGBps` = `min(PopulatedSlots,2) × 8 × RunningSpeed / 1000`;
    `$null` when the running speed is unknown. `ChannelAssumption` carries the
    "assumes dual-channel" label text (or "single module → 1 channel").
  - `RandMBps` = `RandIops × 4096 / 1e6` (derived, shown alongside IOPS).
  - `Context.OnAC`/`PowerPlan` come from the Battery section when present; a
    desktop without one degrades to timestamp-only (the power plan is only
    collected via the battery path — a known codebase property the Upgrade
    Advisor also inherits).
- **No `Get-BenchmarkInsights`.** Benchmarks emit **no notes** — the Notes box
  is for passive findings; an on-demand measurement is presentation only (the
  same call the Upgrade Advisor made).
- **Wiring:** `New-SystemReport` gains a **`Benchmark = $null` placeholder**
  property (its only change) so both entry points can assign to the same report
  object. `Invoke-SystemInfo` collectors are untouched.
- **Console:** a new top-level **`-Benchmark`** switch. It implies console mode
  (a GUI must never auto-run a load): collect everything as usual, print
  progress lines (via `-OnStage`), attach the section, render. Plain `-Console`
  → no Benchmarks section, unchanged output.
- **GUI (staged sync run — user decision):** the Run button's click handler
  disables the button, steps the stages synchronously with the status label
  updated via `-OnStage` + `[System.Windows.Forms.Application]::DoEvents()`
  between stages (the window is briefly unresponsive *during* each 2–5 s stage
  — accepted v1 trade-off; no background runspace), assigns
  `$Report.Benchmark`, renders the results, re-enables the button as **"Run
  again"**.
- **Copy button fix (grounded requirement):** today `$copyText` is rendered
  **once at form-build time** and captured in the click closure
  (`Show-SystemInfo.ps1:2301`), so benchmark results would never reach the
  clipboard. The Copy click handler changes to render
  `(Write-SystemConsole $Report | Out-String).Trim()` **at click time** —
  output is identical before a run (the report object is otherwise static) and
  includes the Benchmarks section after one.

## Presentation

- **Benchmark tab** — always present, placed **after Live, before Network**
  (both are "measure right now" surfaces) → **12 tabs**. Fresh state: an
  explanatory caption (*"Measures this machine right now — CPU arithmetic,
  memory bandwidth, disk read. Takes ~10–15 seconds and loads the machine.
  Nothing runs until you click."*), the **Run benchmarks** button, and an empty
  status label. Post-run state: a KV block —

  ```
  CPU:        1,014 arith Mops/s single-thread -> 11,080 all-threads (10.9x on 16 threads)
  Memory:     19.3 GB/s copy (1 thread) / 34.0 GB/s (all threads) - theoretical dual-channel DDR4-2933 peak ~46.9 GB/s
  Disk (C:):  1,186 MB/s sequential / 5,135 IOPS random 4K (~21.0 MB/s)
  Context:    Run on AC power, Balanced plan, 2026-07-04 18:05 (short-burst, single-stream)
  ```

  (Illustrative — probe-derived where measured; the all-threads memory figure
  is a placeholder shape until the implementation capture.)

  plus a caption: *"Measured by this tool's own workloads; comparable across
  runs of this tool, not to other benchmarks. Disk is single-stream (QD1) —
  spec-sheet numbers need deep queues."* A skipped/failed stage renders its
  line as `Unavailable (<reason>)`.
- **Console** — with `-Benchmark`: progress lines while running, then a
  **`Benchmarks`** section (after `Live / Load`, before `Network`) with the
  same lines. Without the switch: no section.
- **Overview: unchanged** (passive snapshot; benchmarks are on-demand).

## Reference data (dev machine — recorded at implementation)

Expected from the probes: CPU ≈ 1,000 ST / ≈ 11,000 MT arith Mops/s (~10–11×);
memory 1T ≈ 19 GB/s with the all-thread number landing between that and the
46.9 GB/s theoretical; disk ≈ 1,000–1,200 MB/s sequential, ≈ 5,000 IOPS random
4K. **The memory stage may legitimately skip on this machine** (it was at 1 GB
available during grounding) — if it does, the skip line is itself the verified
graceful-degradation path; re-run after freeing RAM for the full capture. Real
numbers, and the all-thread memory figure, get recorded here during
implementation verification.

## Testing

- **Pure `New-BenchmarkReport`:**
  - Full bundle + dual-channel DDR4-2933 Memory section → `TheoreticalGBps`
    46.9, `Scale` computed, context from Battery (`OnAC`, plan), `Ok = $true`.
  - Single-module Memory section → 1-channel theoretical (23.5),
    `ChannelAssumption` says single.
  - Memory section with unknown running speed (or unknown populated-slot
    count) → `TheoreticalGBps = $null`, no crash.
  - Bundle with `MemSkippedReason`/`DiskSkippedReason` → reasons surfaced,
    other pillars intact.
  - All-null bundle → `Ok = $false`, every line renders `Unavailable`, no
    crash.
  - No Battery section → context degrades to timestamp-only.
  - Deterministic: `RanAt` is a parameter; two calls with the same inputs are
    identical.
- **Console:** report with a fake attached Benchmark section → `Benchmarks`
  section present with CPU/Memory/Disk/Context lines; report with
  `Benchmark = $null` → no section (byte-identical to today's output).
- **GUI (`GuiSmoke.ps1`):** tab count **11 → 12** (and the no-battery desktop
  fixture **8 → 9** — the tab is always present); fresh report → Benchmark tab
  has the Run button + caption and **no** results block; a report with a fake
  pre-attached Benchmark section → results KV block renders (tests the
  renderer without a 15 s live run). The smoke never clicks Run.
- **Real run:** `-Benchmark` console mode on this machine during final
  verification; numbers recorded in this spec's reference section.

## Out of scope (YAGNI / honesty)

- **GPU benchmark** — no representative zero-install 3D workload (GDI/WPF
  isn't gaming-like, and WPF would land on the iGPU under Optimus — it would
  benchmark the wrong GPU on this very machine); revisit only with a real,
  honest workload.
- **Published FPS / score / percentile tables** — permanent no (numbers
  measured on other machines are fabrication here; slice H/K's tier labels
  remain the honest coarse form).
- Write benchmarks; non-system drives; sustained / thermal-soak runs;
  background-runspace UI; result history / snapshot compare (pairs with the
  future snapshot slice); an Overview line; notes/insights.
