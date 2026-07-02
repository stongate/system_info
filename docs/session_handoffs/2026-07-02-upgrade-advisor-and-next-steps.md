# Session handoff — Upgrade Advisor (slice I) done + what's next

- **Date:** 2026-07-02
- **Repo:** `D:\stongate\system_info` (GitHub: `stongate/system_info`)
- **Status:** **Upgrade Advisor (slice I) complete, merged to `main`, pushed.**

## TL;DR / first action

The system-info tool now has **10 tabs** (Overview / CPU / GPU / Memory / Storage /
Gaming / Battery / Live / Network / **Upgrade**). Slices **A–I** are done. There is
**no work in progress** — pick a next expansion from *"What's left to do"* below,
start a fresh branch off `main`, and run the usual flow: **brainstorm → committed
spec → written plan → subagent-driven execution (fresh implementer per task +
two-stage review) → verify → FF-merge to `main` → push.** Don't pre-bake designs
here; brainstorm each slice fresh, grounded in real data on this machine.

## Current project state

- Branch `main`, pushed to `origin`. Working tree clean (the distributable
  `Show-SystemInfo.zip` is now git-ignored — regenerate it from source, don't
  commit it).
- **Slices A–I merged:** CPU, GPU (+nvidia-smi sensors), Memory, Storage, Battery,
  Live/Load (memory pressure), Network, Gaming (synthesis), **Upgrade Advisor
  (synthesis)** — each with tab + console section + (most) an Overview line +
  bottleneck notes.
- **352 unit tests + GUI smoke pass.** Zero-install, two distributed files:
  `Show-SystemInfo.ps1` + `SystemInfo.cmd`.
- Reference machine: Dell laptop, i7-10750H / GTX 1650 Ti (has battery, Wi-Fi,
  NVIDIA GPU). Virtualization is disabled and the battery is ~59% worn here, so
  the Upgrade Advisor fires on real hardware.

## What is the Upgrade Advisor (just shipped)

Pure synthesis (no collector), mirroring the Gaming slice. `New-UpgradeReport`
applies a 9-rule catalog to the section objects → pre-ranked
`{ Recommendations=@({Group;Action;Detail;Impact}); FreeCount; HardwareCount;
HasAny }` (Free fixes first, then Hardware; High→Med→Low). Composed in
`New-SystemReport` as `$Report.Upgrade`; **emits no notes** (deliberately not in
`Get-SystemInsights`, to avoid duplicating the Notes box). Rendered in
`Write-SystemConsole` and an always-present `Upgrade` tab. Honesty: every Detail
uses only measured values — no prices/percentages/products. Spec + plan:
`docs/superpowers/specs/2026-07-02-upgrade-advisor-design.md`,
`docs/superpowers/plans/2026-07-02-upgrade-advisor.md`.

## What's left to do (menu — brainstorm, don't assume)

**Breadth — new subsystem/tab (the biggest unfilled honest gaps):**
- **Firmware / Security / Windows-11 readiness** — BIOS version+date, UEFI vs
  legacy, **Secure Boot** on/off, **TPM** presence+version → a Win11-readiness
  verdict. Highly readable, actionable, and timely (Win10 EOL). Strong candidate.
- **OS / Windows** — edition, build/version, uptime, install date, activation,
  pending-reboot.
- **Security posture** — Defender status, firewall, BitLocker/encryption.
- **Displays / monitors** — connected panels, native vs current resolution,
  refresh, HDR, scaling (partly overlaps Gaming's display data).

**Depth — richer data in an existing tab:**
- **Storage SMART / wear / temperature** (early drive-failure warning) — verify
  data availability first (`Get-StorageReliabilityCounter`, `MSStorageDriver`).
- CPU instruction-set flags / boost clock (fragile per-SKU; may stay out).
- CPU **live-load** sampling (needs sustained sampling; snapshot is ambiguous).
- Per-process memory breakdown; AMD/Intel GPU sensors (no zero-install source).

**Cross-cutting (not a subsystem):**
- **Export / save report** to HTML/JSON/text file (today only clipboard Copy).
- **Refresh button** — re-run collectors + repaint in place (pairs with Live tab).
- **Snapshot compare** — save now, diff later (free space, driver, battery wear).

**Upgrade Advisor follow-ups (deferred in its own spec / review nits):**
- README bullet doesn't name the SATA→NVMe rule (cosmetic; illustrative list).
- Optional: a one-line comment on the XMP rule (only the actionable branch fires)
  and on the GUI `PreferredHeight` layout; a positional GUI-smoke assertion if
  that layout technique gets reused.
- Deferred rules: generic capacity-based "add more RAM"; recommendations for the
  excluded findings (idle GPU, thermal, failing-drive health, network); no cost
  bands / FPS.
- **Open task chip:** resolve an unmapped JEDEC RAM vendor code
  (`019800000000`, likely Kingston) in `ConvertTo-VendorName` + a test.

## Architecture — how a slice is added

Mirror the existing subsystems in `Show-SystemInfo.ps1`:
1. **Collector** (thin, CIM/registry/exe, I/O): `Get-<X>Info` → raw object(s).
   *Synthesis slices (Gaming, Upgrade) skip this — they read existing sections.*
2. **Pure builder**: `New-<X>Report` → the section object (unit-tested; pass any
   "now"/non-deterministic value as a parameter).
3. **Pure insights**: `Get-<X>Insights` → `{ Kind; Text }` notes. *(The Upgrade
   Advisor deliberately has none — it emits no notes.)*
4. **Wire up**: add `-X` to `New-SystemReport` (and `Get-SystemInsights` if it
   emits notes). Array-flatten pattern: assign sub-results then `+=`, don't wrap
   `Get-*Insights` calls in `@()`.
5. **Renderers**: a tab in `New-SystemForm`, (usually) an Overview line, and a
   section in `Write-SystemConsole`. Wire the collector into `Invoke-SystemInfo`.
6. **Graceful absence**: handle null/empty cleanly (no tab/section, or an
   "Unknown"/"none" line) — desktops lack a battery, some machines lack Wi-Fi.

## Workflow + commands

- Branch: `git switch -c feature/<name>` (off `main`).
- Unit tests: `pwsh -File tests/SystemInfo.Tests.ps1`
- GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
- Console run (real hardware): `powershell.exe -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console`
- **GUI render check** (can't see the live window): build the report, call
  `New-SystemForm`, move it off-screen, `Show()` + `DoEvents`, `DrawToBitmap`
  to a PNG, read it. Windows PowerShell (STA). Tests set env `SYSTEMINFO_NOMAIN`
  to suppress the GUI on dot-source.
- **Honest-data ethos:** never fabricate; label derived/best-effort values;
  when a slice's honest scope shrinks (like Live dropping thermals), that's fine.
- When done: verify both suites → FF-merge to `main` → `git push`.

See also memory notes `system-info-project` and `steven-build-workflow`, and the
prior handoff `docs/session_handoffs/2026-06-30-battery-subsystem.md`.
