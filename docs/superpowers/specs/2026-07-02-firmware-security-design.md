# System Info — Firmware & Security (+ Windows 11 readiness) (slice J)

- **Date:** 2026-07-02
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/firmware_security` (off `main`)
- **Part of:** full system-info effort (A=CPU … H=Gaming, I=Upgrade Advisor done,
  **J=Firmware & Security**).

## Goal

A **Firmware & Security** tab that reports the machine's platform-security state —
**BIOS** (vendor/version/date), **UEFI vs Legacy**, **Secure Boot** on/off, and
**TPM** presence/version — and derives a **Windows 11 readiness** verdict from it.
Timely (Windows 10 end-of-life), highly readable, and actionable. All four pillars
are read from **no-admin** sources, so it works in the tool's normal (unelevated)
run context.

Scope is deliberately **tight**: firmware + platform security + readiness only.
Windows edition/activation/uptime and security *posture* (Defender, firewall,
BitLocker) are explicitly out — each is a separate future slice, and several need
admin.

## Why this scope (honest-data findings, dev machine 2026-07-02)

Grounding on this machine (Dell XPS 15 9500, **non-admin**, `SystemInfo.cmd` does
not elevate) decided the sourcing:

| Fact | No-admin source that works here | Admin-only source (rejected) |
|------|----------------------------------|------------------------------|
| BIOS vendor/version/date | `Win32_BIOS` ✓ (`1.33.1`, Dell, 2024-11-17) | — |
| UEFI vs Legacy | presence of `…\SecureBoot\State` key ✓ | `bcdedit` (admin) |
| Secure Boot on/off | registry `UEFISecureBootEnabled` ✓ (`1`) | `Confirm-SecureBootUEFI` → *Access denied* |
| TPM presence + version | `Win32_PnPEntity` `PNPClass='SecurityDevices'` friendly name ✓ (`Trusted Platform Module 2.0`) | `Get-Tpm` / `Win32_Tpm` → *Access denied* |

The authoritative TPM (`Win32_Tpm.SpecVersion`) and Secure Boot
(`Confirm-SecureBootUEFI`) cmdlets **both require admin** and throw here. The
no-admin fallbacks give the same facts as **best-effort, labelled** reads — the
same posture the Network slice used for its netsh-derived Wi-Fi fields.

This machine is **already on Windows 11** (build 26200), so its readiness verdict
reads *"This PC is running Windows 11."* The readiness logic still matters for the
many Windows 10 machines the tool runs on; the firmware/security facts are valuable
regardless of OS.

## The honest core

- **TPM presence + version come from the PnP device friendly-name**
  (`"Trusted Platform Module 2.0"` → present, `2.0`), because the authoritative
  `Win32_Tpm` class needs admin. Labelled best-effort. Present-but-unversioned name
  → `Present=$true, Version=$null`; no `SecurityDevices` TPM device → `Present=$false`.
- **Firmware type is derived** from the presence of the `SecureBoot\State`
  registry key (present ⇒ UEFI; absent ⇒ Legacy/CSM). Best-effort. (`Get-ComputerInfo`
  reports `BiosFirmwareType` authoritatively but is avoided — it is seconds-slow.)
- **The CPU "on Microsoft's approved list" requirement is never judged.** There is
  no API for it (PC Health Check checks a hardcoded, staleable model list). The
  readiness checklist shows the CPU requirement as **`unknown` — "verify against
  Microsoft's supported-CPU list"**, never a fabricated approve/deny. Same
  never-fabricate ethos as the Advisor refusing invented %/FPS/prices.
- **No BIOS-age judgment.** The release date is shown as a fact; the tool does not
  claim a BIOS is "outdated" (an old BIOS is not necessarily insecure — cry-wolf).
- Nothing is fabricated; a field the tool cannot read is `Unknown`/omitted.

## Architecture (self-contained collector, mirrors the established pattern)

Not a synthesis slice — the firmware facts live in no existing section, and the
readiness check needs OS build (uncollected today). So a real collector plus a pure
builder, like Storage/Network/Battery.

- **`Get-FirmwareInfo`** (collector, I/O, wrapped in try/catch, all no-admin) reads
  a **raw bundle**:
  - **BIOS** — `Win32_BIOS` → `Manufacturer`, `SMBIOSBIOSVersion`, `ReleaseDate`
    (already a `DateTime` via CIM — no CIM_DATETIME parsing).
  - **Firmware type** — `Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'`.
  - **Secure Boot** — `UEFISecureBootEnabled` from that key (may be absent).
  - **TPM** — `Get-CimInstance Win32_PnPEntity` where `PNPClass -eq 'SecurityDevices'`,
    first matching `Name` (fallback filter `Name -match 'Trusted Platform|TPM'`).
  - **Readiness inputs** — `Win32_OperatingSystem.BuildNumber`;
    `Win32_ComputerSystem.TotalPhysicalMemory`; system-drive total size
    (`Win32_LogicalDisk` `$env:SystemDrive`); `Win32_Processor.AddressWidth`.
  - Returns `$null`-tolerant fields; a total failure returns an object of nulls.

- **`New-FirmwareReport -Raw <bundle>`** (pure, deterministic) → the section object:

  ```
  { Bios         = { Vendor; Version; ReleaseDate }        # ReleaseDate may be $null
    FirmwareType = 'UEFI' | 'Legacy' | $null
    SecureBoot   = 'On' | 'Off' | 'Unavailable' | $null    # Unavailable = Legacy (no key)
    Tpm          = { Present = $true|$false; Version }      # '2.0' | '1.2' | $null
    Win11        = { AlreadyWin11 = $true|$false
                     Requirements = @( { Name; Met = $true|$false|'unknown'; Detail } … )
                     Summary } }
  ```

  - **Secure Boot mapping:** key value `1`→`'On'`, `0`→`'Off'`, key absent →
    `'Unavailable'` (Legacy has no Secure Boot).
  - **TPM version** parsed from the friendly name (`… (\d+\.\d+)$`).
  - Deterministic — the BIOS date is displayed, never aged, so no "now" parameter.

- **`Get-FirmwareInsights`** (pure) → notes `{ Kind; Text }`, all **info** (config /
  posture, not a malfunction — nothing here "fails" like a worn battery):
  1. **Secure Boot off** (`SecureBoot -eq 'Off'`): *"Secure Boot is supported but
     turned off; enabling it in firmware improves boot security (and is required for
     Windows 11)."*
  2. **Legacy/CSM** (`FirmwareType -eq 'Legacy'`): *"Firmware is in Legacy (CSM)
     mode; UEFI is required for Secure Boot and Windows 11."*
  3. **TPM not detected** (`Tpm.Present -eq $false`): *"No TPM detected. Windows 11
     requires TPM 2.0; a firmware TPM (Intel PTT / AMD fTPM) may be disabled in
     BIOS."*
  - **No roll-up "not-ready" note.** The atomic notes above already carry the
    actionable Win11 blockers; a separate roll-up would duplicate them in the Notes
    box (the same don't-duplicate call the Upgrade Advisor made). The readiness
    verdict is **presentation** (tab + console), not a note.
  - No note when data is missing (never fabricated).

- **Wiring:** add `-Firmware` to `New-SystemReport` and `Get-SystemInsights`
  (assign-then-`+=`, not `@(...)`-wrapped); `Invoke-SystemInfo` collects it. **No
  change to `New-UpgradeReport`** — "Enable Secure Boot / TPM" stay as notes, not
  Free upgrade recs: unlike Enable-VT/XMP they carry a real "could break boot
  (MBR→GPT), could trigger BitLocker recovery" caveat. Revisitable later.

## Windows 11 readiness logic

`Requirements` (each `{ Name; Met; Detail }`), all from no-admin facts:

| Name | Met when | Detail (measured) |
|------|----------|-------------------|
| TPM 2.0 | `Tpm.Present && Version -like '2*'` | friendly name, or "not detected" |
| Secure Boot | `SecureBoot -eq 'On'` | On / Off / Unavailable |
| UEFI firmware | `FirmwareType -eq 'UEFI'` | UEFI / Legacy (CSM) |
| RAM ≥ 4 GB | `TotalPhysicalMemory -ge 4GB` | e.g. "15.8 GB" |
| Storage ≥ 64 GB | system-drive total `-ge 64GB` | e.g. "954 GB" |
| 64-bit CPU | `AddressWidth -eq 64` | "64-bit" / "32-bit" |
| CPU model | **always `'unknown'`** | "verify against Microsoft's supported-CPU list" |

`Met` is `'unknown'` (not `$false`) when the input is unreadable, and always
`'unknown'` for CPU model — an unknown never counts as a failure.

**`Summary` (adaptive):**
- `AlreadyWin11` (`BuildNumber -ge 22000`) → *"This PC is running Windows 11."*
- else, no checkable requirement `-eq $false` → *"Meets Windows 11's checkable
  requirements — verify the CPU model against Microsoft's supported-CPU list."*
- else → *"Not ready for Windows 11: `<unmet, comma-joined>`."* (e.g. "no TPM 2.0,
  Secure Boot off").

## Presentation

- **Tab "Firmware & Security"** — placed **after Network, before Upgrade** (Upgrade
  stays last as the closing synthesis): Overview / CPU / GPU / Memory / Storage /
  Gaming / Battery / Live / Network / **Firmware & Security** / Upgrade →
  **11 tabs**. Always present (every machine has firmware). Stacked `Add-KvBlock`
  layout (like CPU/Memory/Battery), two blocks:
  - **Firmware** — `BIOS: <vendor> <version> (<Mon YYYY>)`, `Firmware: UEFI` |
    `Legacy (CSM)`, `Secure Boot: On` | `Off` | `Unavailable (Legacy)`,
    `TPM: 2.0` | `Present (version unknown)` | `Not detected`.
  - **Windows 11 readiness** — one line per requirement, each prefixed with a
    status marker (`Met` / `Not met` / `?`, exact glyph chosen at implementation to
    render in the WinForms font and stay ASCII-safe for console — verified via the
    off-screen PNG), then the adaptive `Summary` line.
  - A caption: *"Firmware/security facts are read without admin (best-effort). The
    CPU-model requirement is not checked here — verify it against Microsoft's list."*
- **Overview** — one new **`Security:`** row (8th row of the header block):
  `Secure Boot On · TPM 2.0 · UEFI`, degrading gracefully
  (`Secure Boot Off · No TPM · Legacy`, or `Unknown`).
- **Console** — a **`Firmware & Security`** section (after `Network`, before
  `Upgrade Advisor`): the firmware lines, the readiness checklist, and the summary.
- **Graceful absence** — total read failure → tab shows `Unknown` lines and the
  readiness summary is omitted; no crash.

## Reference data (dev machine, 2026-07-02 — Dell XPS 15 9500)

Non-admin capture: **BIOS** Dell `1.33.1`, 2024-11-17 · **Firmware** UEFI
(`SecureBoot\State` present) · **Secure Boot** On (`UEFISecureBootEnabled = 1`) ·
**TPM** `Trusted Platform Module 2.0` (Status OK) → `Present, 2.0`. **OS** build
26200 → `AlreadyWin11`. Readiness: TPM 2.0 ✓, Secure Boot ✓, UEFI ✓, RAM 15.8 GB ✓,
Storage 954 GB ✓, 64-bit ✓, CPU model `?`. **Summary:** *"This PC is running
Windows 11."* No firmware/security notes fire (Secure Boot on, UEFI, TPM present) —
honest, like a healthy disk in Storage.

## Testing

- **Pure `New-FirmwareReport`** — one fixture per shape:
  - UEFI + Secure Boot On + TPM `"…Module 2.0"` + build 26200 → FirmwareType `UEFI`,
    SecureBoot `On`, Tpm `{present,2.0}`, `AlreadyWin11`, Summary "running".
  - Legacy (no key) → FirmwareType `Legacy`, SecureBoot `Unavailable`.
  - `UEFISecureBootEnabled = 0` → SecureBoot `Off`.
  - TPM device absent → `Tpm.Present -eq $false, Version -eq $null`.
  - TPM name without version → `Present, Version $null`.
  - Win10 build 19045, Secure Boot Off, no TPM → not-`AlreadyWin11`, Summary
    "Not ready: … Secure Boot off, no TPM 2.0", CPU requirement `unknown`.
  - Win10 meeting all checkable → Summary "Meets … verify the CPU model".
  - CPU-model requirement `Met -eq 'unknown'` in every fixture.
- **Pure `Get-FirmwareInsights`** — Secure-Boot-off → info; Legacy → info; no-TPM →
  info; healthy (UEFI, SB on, TPM 2.0) → **no note**; no roll-up note ever emitted.
- **Wiring** — `New-SystemReport` populates `.Firmware`; `-Firmware` flows notes;
  `Get-SystemInsights -Firmware $null` → no note, no error.
- **Console** — `Firmware & Security` section present with facts + checklist;
  handles a null/failure bundle without crashing.
- **GUI (`GuiSmoke.ps1`)** — bump **10 → 11 tabs**; assert a `Firmware & Security`
  tab exists with the firmware block, the readiness checklist, and the caption;
  off-screen PNG render.

## Out of scope (YAGNI / deferred)

- Windows edition / activation / install date / uptime; Defender / firewall /
  BitLocker (each a separate slice; several need admin).
- Admin-only authoritative reads (`Get-Tpm`, `Win32_Tpm`, `Confirm-SecureBootUEFI`)
  and any elevation prompt — the tool stays zero-install/non-admin.
- CPU approved-list judgment; BIOS-age / update-available checks; DirectX 12 /
  WDDM readiness (rarely the blocker, no clean no-admin read).
- Feeding the Upgrade Advisor (Enable Secure Boot / TPM as ranked recs).
