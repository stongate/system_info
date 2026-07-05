# Session handoff — Gaming accuracy (K) + Benchmarks (L) done + what's next

- **Date:** 2026-07-05 (session spanned 2026-07-04 → 05)
- **Repo:** `C:\Users\stong\Development\memory_checker` (GitHub: `stongate/system_info`)
- **Status:** **Slices K and L complete, merged to `main`, pushed.** No work in progress.

## TL;DR / first action

The tool now has **12 tabs** (Overview / CPU / GPU / Memory / Storage / Gaming /
Battery / Live / **Benchmark** / Network / Firmware & Security / Upgrade).
Slices **A–L** are done. Pick a next expansion from *"What's left"* below, branch
off `main`, and run the usual flow: **brainstorm (grounded on the machine at
hand) → committed spec → written plan → subagent-driven execution with two-stage
reviews → verify both suites → FF-merge → push.**

## Current project state

- Branch `main` pushed; working tree clean. **451 unit tests + a 70-check GUI
  smoke pass.** Reference machine this session: **Dell XPS 17 9700** (i7-10875H
  8C/16T, RTX 2060 **Max-Q** 6 GB + Intel UHD, 16 GB DDR4-2933 dual-channel,
  1920×1200@59 native, NVMe behind RAID/VMD, Win 11 Pro 26200, non-admin).
  Machines alternate between sessions (slice J was an XPS 15 9500) — **re-ground
  every slice on the machine at hand.**

## What shipped this session

### Slice K — Gaming accuracy (revision slice)
Name-declared laptop GPU variants ("Max-Q", "Laptop GPU", AMD `RX nM`) tier
**one rank below** their desktop namesake (floor 1; laptop-native rows like the
new RTX 4050 exempt); `MobileVariant` flows tier → report → renderers, which
append **"(laptop GPU)"** (report `Verdict` stays plain — pinned by test); CPU
limiter (`1–4 cores` → `"<n>-core CPU"`) + rank-gated low-core note; measured
59/60 Hz renders as **"60 Hz-class display"**; the spec-H-promised Gaming
**Storage** line finally renders. This machine's own verdict honestly dropped
from "1080p high / 1440p mainstream" to **"1080p mainstream / esports (laptop
GPU)"**. Spec/plan: `docs/superpowers/{specs,plans}/2026-07-04-gaming-accuracy*`.

### Slice L — Benchmarks (first "on-demand prober" slice)
On-demand **CPU / memory / disk micro-benchmarks** — never auto-run: a
**Benchmark tab** (Run button, staged sync + `DoEvents`, status label, results
re-render, "Run again") and a **`-Benchmark`** console switch (implies console
mode; progress lines via Write-Host). Engine: in-memory **C# via `Add-Type`**
(`SysInfoBench`: xorshift+multiply-add CPU — deliberately not crypto (SHA-NI
skew); `Buffer.BlockCopy` bandwidth over 512 MB; unbuffered
`FILE_FLAG_NO_BUFFERING` disk reads, seq 4 s cap + random 4K — all single-stream
QD1, labelled). Guards: <2 GB RAM / <5 GB disk → honest skip reasons;
per-stage try/catch; never throws; temp file always cleaned. **References are
derivable-only** (theoretical peak = `min(slots,2)×8×MT/s`, labelled "assumes
dual-channel"; MT/ST scale labelled workload-specific) — no comparison tables,
no verdicts. The Copy button now renders **at click time** so benchmark results
reach the clipboard. Dev capture: CPU 995 → 10,978 Mops (11×), memory 19.3/20.8
GB/s vs 46.9 theoretical (**1 thread already saturates copy bandwidth here**),
disk 1,197 MB/s / 8,360 IOPS. Spec/plan:
`docs/superpowers/{specs,plans}/2026-07-04-benchmark*`.

## Hard-won PowerShell/WinForms gotchas (slice L's five review-fix rounds)

Recorded because they will bite again:
1. **`Add-Type` on pwsh 7+ compiles C# at Debug optimization** (Roslyn;
   `IsJITOptimizerDisabled`) — CPU-bound workloads run ~2.4× slow vs Windows
   PowerShell's CodeDom (optimizes by default). Fix shipped: PSEdition-gated
   `-CompilerOptions '/optimize'`.
2. **`GetNewClosure()` binds handlers to a dynamic module that resolves
   commands module→global only** — script functions are invisible when the
   script is dot-run (`.\` / `&`) instead of `-File`. Fix shipped: capture
   `${function:Name}` references at form-build time, invoke via `& $fn`.
3. **A closure created *inside* a click handler executes in that dynamic-module
   scope and cannot see form-build locals** (`$bStatus` resolved `$null` → the
   suite's outer catch swallowed the throw → all-null "Done in 0s" results in
   every launch mode, invisible to every green suite). Fix shipped: create
   `$onStage` at form-build scope. **Regression guard shipped:** GuiSmoke stubs
   `Invoke-BenchmarkSuite` and fires the real handler via reflection-raised
   protected `OnClick` (**`PerformClick()` is a silent no-op on never-shown
   forms**) — proven to fail 5 checks against the buggy build.
4. **Callback pipeline output is captured by the caller's assignment** —
   `Write-Output` in an `-OnStage` scriptblock polluted `$bundle` into an
   `Object[]`. Fix shipped: `Write-Host` for ephemeral progress + `$null = &
   $OnStage` at every invocation site (bundle purity by construction).
5. Review harnesses can **mask scope bugs via name collisions** (a probe's own
   `$bStatus` global made the broken closure accidentally resolve) — probe with
   non-colliding names and assert *measured values* (`Ok`, `StMops`), not just
   structure.

## What's left (menu — brainstorm fresh, grounded, don't assume)

**Breadth — new subsystem/tab:**
- **OS / Windows** — edition, build+UBR, 25H2 DisplayVersion, uptime, install
  date, activation (all verified clean no-admin on the XPS 17, 2026-07-04;
  bonus honesty hook: registry `ProductName` lies "Windows 10 Pro" while CIM
  `Caption` says 11 — source from Caption).
- **Displays / monitors** — `WmiMonitorID` / `WmiMonitorListedSupportedSourceModes`
  / `WmiMonitorBasicDisplayParams` all verified readable no-admin (XPS 17: SHP
  17.2″, native 1920×1200, preferred 59.95 Hz) → native-vs-current honesty,
  panel facts, could feed Gaming.
- **Security posture** — Defender/firewall/BitLocker (graceful-degradation-heavy;
  several reads want admin).

**Cross-cutting:**
- **Export / save report** to HTML/JSON/text (Copy is the only egress today).
- **Refresh button**; **snapshot compare** (benchmarks would slot in nicely).

**Still blocked / deferred:** Storage SMART/wear/temp (RAID/VMD + non-admin —
re-verified blocked on BOTH reference machines); GPU benchmark (no honest
zero-install 3D workload; Optimus would benchmark the iGPU); published-FPS
tables (permanent no); live FPS capture (ETW needs admin).

**Open task chips (pending on the session UI):** README refresh (stale "~148
tests" + missing Gaming bullet — also no Benchmark bullet now); align the 60-fps
insight note's "59 Hz" wording with the "60 Hz-class" limiter; unmapped JEDEC
RAM vendor code `019800000000` (Kingston?) from slice I.

## Workflow + commands (unchanged)

- Branch: `git switch -c feature/<name>` off `main`.
- Unit tests: `pwsh -File tests/SystemInfo.Tests.ps1` (451 passing)
- GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` (70 checks)
- Console run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console` (add `-Benchmark` to measure)
- GUI render check: off-screen `Show()` + `DrawToBitmap` under Windows
  PowerShell STA; `SYSTEMINFO_NOMAIN=1` suppresses main on dot-source.
- Honest-data ethos: never fabricate; label derived/best-effort; never judge
  what has no honest source; don't cry wolf.

See also the prior handoff `docs/session_handoffs/2026-07-02-firmware-security-and-next-steps.md`
and memory notes `system-info-project` / `steven-build-workflow`.
