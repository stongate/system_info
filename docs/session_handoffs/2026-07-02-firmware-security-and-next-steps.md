# Session handoff — Firmware & Security (slice J) done + what's next

- **Date:** 2026-07-02
- **Repo:** `D:\stongate\system_info` (GitHub: `stongate/system_info`)
- **Status:** **Firmware & Security (slice J) complete, merged to `main`, pushed.**

## TL;DR / first action

The system-info tool now has **11 tabs** (Overview / CPU / GPU / Memory / Storage /
Gaming / Battery / Live / Network / **Firmware & Security** / Upgrade). Slices
**A–J** are done. There is **no work in progress** — pick a next expansion from
*"What's left to do"* below, start a fresh branch off `main`, and run the usual
flow: **brainstorm → committed spec → written plan → subagent-driven execution
(fresh implementer per task + two-stage review: spec compliance, then code quality)
→ verify → FF-merge to `main` → push.** Don't pre-bake designs here; brainstorm each
slice fresh, grounded in real data on this machine.

## Current project state

- Branch `main`, pushed to `origin`. Working tree clean (the distributable
  `Show-SystemInfo.zip` is git-ignored — regenerate from source, don't commit it).
- **Slices A–J merged:** CPU, GPU (+nvidia-smi sensors), Memory, Storage, Battery,
  Live/Load (memory pressure), Network, Gaming (synthesis), Upgrade Advisor
  (synthesis), **Firmware & Security** — each with a tab + console section + (most)
  an Overview line + bottleneck notes.
- **388 unit tests + a GUI smoke (51 checks) pass.** Zero-install, two distributed
  files: `Show-SystemInfo.ps1` + `SystemInfo.cmd`.
- Reference machine: **Dell XPS 15 9500**, i7-10750H / GTX 1650 Ti, **Windows 11
  Pro (build 26200)**, runs **non-admin** (the launcher does not elevate). Has
  battery, Wi-Fi, NVIDIA GPU; battery is worn; UEFI + Secure Boot On + TPM 2.0, so
  the Firmware slice shows a clean, "already on Windows 11" readout here.

## What is the Firmware & Security slice (just shipped)

A **self-contained collector** slice (unlike the Gaming/Upgrade syntheses), and one
that **does emit notes** (unlike the Upgrade Advisor). All sources are **no-admin**,
because the tool runs unelevated:

- **`Get-FirmwareInfo`** (collector) reads BIOS (`Win32_BIOS`), UEFI-vs-Legacy (the
  `…\SecureBoot\State` key's presence), Secure Boot (`UEFISecureBootEnabled`), TPM
  presence+version (`Win32_PnPEntity` `PNPClass='SecurityDevices'` friendly name),
  plus OS build / RAM / system-drive size / CPU address-width. Self-guarding; always
  returns a bundle (never `$null`). Verified via `-Console` (collectors aren't
  unit-tested). The authoritative `Get-Tpm`/`Confirm-SecureBootUEFI` need admin and
  are deliberately **not** used.
- **`New-FirmwareReport -Raw`** (pure) shapes `{ Bios; FirmwareType; SecureBoot;
  Tpm; Win11 }` and computes a **Windows 11 readiness** checklist. The **CPU-model**
  requirement is **always `unknown`** ("verify against Microsoft's list") — there is
  no honest API for it, and this is enforced structurally (the `-is [bool]` guard +
  a bool-only `$unmet` filter make it impossible to fabricate a pass or flip the
  verdict). Adaptive summary: already-Win11 / "meets checkable requirements" /
  "Not ready: `<reasons>`".
- **`Get-FirmwareInsights`** (pure) emits **three `info` notes** — Secure Boot off,
  Legacy/CSM, TPM not detected — and **deliberately no roll-up** "not-ready" note
  (the atomic notes already carry the blockers; a roll-up would duplicate the Notes
  box, the same call the Upgrade Advisor made).
- Rendered in `Write-SystemConsole`, an always-present **Firmware & Security** tab
  (after Network, before Upgrade), and an Overview **`Security:`** row
  (`Secure Boot On · TPM 2.0 · UEFI`, degrading gracefully).
- Honesty: TPM version + firmware type are **best-effort** (labelled); no BIOS-age
  judgment; nothing fabricated. Spec + plan:
  `docs/superpowers/specs/2026-07-02-firmware-security-design.md`,
  `docs/superpowers/plans/2026-07-02-firmware-security.md`.

## What's left to do (menu — brainstorm, don't assume)

**Breadth — new subsystem/tab (the biggest unfilled honest gaps):**
- **OS / Windows** — edition, build/version, uptime, install date, activation,
  pending-reboot. *(Some overlap: the Firmware slice already reads the OS build for
  the Win11 verdict, but surfaces no edition/uptime/activation.)*
- **Security posture** — Defender status, firewall, BitLocker/encryption. *(Heads-up
  from slice-J grounding: BitLocker and some Defender reads want admin, so this is a
  graceful-degradation-heavy slice on a non-admin tool.)*
- **Displays / monitors** — connected panels, native vs current resolution, refresh,
  HDR, scaling (partly overlaps Gaming's display data).

**Depth — richer data in an existing tab:**
- **Storage SMART / wear / temperature** — *verified weak on this machine:* the
  reliability counters + `MSStorageDriver` SMART need **admin** AND the boot NVMe
  sits behind a **RAID/VMD** bus that commonly hides SMART even elevated. Only
  `HealthStatus` (coarse) is readable no-admin here. Reconsider only if targeting
  machines with directly-addressable disks, or accept an admin/graceful-degrade path.
- CPU instruction-set flags / boost clock (fragile per-SKU; may stay out).
- CPU **live-load** sampling (needs sustained sampling; snapshot is ambiguous).
- Per-process memory breakdown; AMD/Intel GPU sensors (no zero-install source).

**Cross-cutting (not a subsystem):**
- **Export / save report** to HTML/JSON/text file (today only clipboard Copy).
- **Refresh button** — re-run collectors + repaint in place (pairs with Live tab).
- **Snapshot compare** — save now, diff later (free space, driver, battery wear).

**Firmware & Security follow-ups (deferred in its spec / review notes):**
- Deferred by design (YAGNI): BIOS-age / update-available checks; CPU approved-list
  judgment; admin-only authoritative TPM/`Win32_Tpm`/`Confirm-SecureBootUEFI`;
  DirectX 12 / WDDM readiness; feeding the Upgrade Advisor (Enable Secure Boot / TPM
  as ranked Free recs — carries a real "could break boot / trigger BitLocker
  recovery" caveat, so it stayed a note).
- Non-blocking review observations (working as intended): the Win11 "storage ≥ 64 GB"
  detail shows the **C: logical-partition** size (`Win32_LogicalDisk`, ~562 GB here),
  not the physical disk (954 GB) — both clear the bar. The tri-state mark logic
  (`[OK]/[NO]/[??]` console, `[OK]/[--]/[ ?]` GUI) and the BIOS-date format are
  duplicated across the console + GUI renderers (matches the codebase's per-renderer
  pattern; no shared helper). A total-read-failure bundle honestly reports
  "Not ready: no TPM 2.0" (absent TPM ⇒ a real `$false`), with `[??]` on the
  unknowable rows — no crash, no fabrication.
- **Open task chip (still unresolved from slice I):** an unmapped JEDEC RAM vendor
  code (`019800000000`, likely Kingston) in `ConvertTo-VendorName` + a test.

## Architecture — how a slice is added

Mirror the existing subsystems in `Show-SystemInfo.ps1`:
1. **Collector** (thin, CIM/registry/exe, I/O): `Get-<X>Info` → raw object(s).
   *Synthesis slices (Gaming, Upgrade) skip this — they read existing sections.
   Firmware is a self-contained collector.*
2. **Pure builder**: `New-<X>Report` → the section object (unit-tested; pass any
   "now"/non-deterministic value as a parameter).
3. **Pure insights**: `Get-<X>Insights` → `{ Kind; Text }` notes. *(The Upgrade
   Advisor has none; Firmware emits three `info` notes, no roll-up.)*
4. **Wire up**: add `-X` to `New-SystemReport` (and `Get-SystemInsights` if it emits
   notes). Array-flatten pattern: assign sub-results then `+=`, don't wrap
   `Get-*Insights` calls in `@()`.
5. **Renderers**: a tab in `New-SystemForm`, (usually) an Overview line, and a
   section in `Write-SystemConsole`. Wire the collector into `Invoke-SystemInfo`.
6. **Graceful absence**: handle null/empty cleanly (no tab/section, or an
   "Unknown"/"none" line) — desktops lack a battery, some machines lack Wi-Fi, an
   old box may be Legacy BIOS with no Secure Boot value.

## Workflow + commands

- Branch: `git switch -c feature/<name>` (off `main`).
- Unit tests: `pwsh -File tests/SystemInfo.Tests.ps1`  (388 passing)
- GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
- Console run (real hardware): `powershell.exe -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console`
- **GUI render check** (can't see the live window): build the report, call
  `New-SystemForm`, move it off-screen, `Show()` + `DoEvents`, `DrawToBitmap` to a
  PNG, read it. Windows PowerShell (STA). Tests set env `SYSTEMINFO_NOMAIN` to
  suppress the GUI on dot-source.
- **Honest-data ethos:** never fabricate; label derived/best-effort values (e.g.
  TPM version from the PnP name); never judge what has no honest source (e.g. the
  Win11 CPU-model requirement stays `unknown`); don't cry wolf.
- When done: verify both suites → FF-merge to `main` → `git push`.

See also memory notes `system-info-project` and `steven-build-workflow`, and the
prior handoff `docs/session_handoffs/2026-07-02-upgrade-advisor-and-next-steps.md`.
