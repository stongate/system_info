# Show-RamInfo — Design Spec

- **Date:** 2026-06-30
- **Status:** Approved (design), pre-implementation
- **Target platform:** Windows 11 (PowerShell 5.1+ / 7+)

## Goal

A small program that reports the machine's RAM:

1. **What's installed** — total amount and speed (rated + currently running), broken down per slot.
2. **What the motherboard supports** — max capacity and number of slots.

Shown in a simple native GUI window, with a plain-text console fallback.

## Key constraint (the honest limitation)

Windows firmware (SMBIOS, read via CIM/WMI) exposes the **installed** speed and the **max capacity**, but there is **no field anywhere for "max speed the motherboard supports."** That value lives only on the board's spec sheet.

Decision (chosen by user): **detect-and-note.** Report everything detectable and label max supported speed as *"not reported by firmware — check board spec,"* shown next to the detected motherboard model. No runtime web lookup, no scraping. Fully offline, always works.

## Data sources (CIM classes)

| Field | Class.Property | Notes |
|---|---|---|
| Slot label | `Win32_PhysicalMemory.DeviceLocator` | e.g. "DIMM A" |
| Module size | `Win32_PhysicalMemory.Capacity` | bytes → GB |
| Rated speed | `Win32_PhysicalMemory.Speed` | MT/s, module's rated max |
| Current speed | `Win32_PhysicalMemory.ConfiguredClockSpeed` | MT/s, actual running |
| Vendor (raw) | `Win32_PhysicalMemory.Manufacturer` | JEDEC code e.g. "80AD…" |
| Part number | `Win32_PhysicalMemory.PartNumber` | |
| Memory type | `Win32_PhysicalMemory.SMBIOSMemoryType` | 26 = DDR4 |
| Max capacity | `Win32_PhysicalMemoryArray.MaxCapacityEx` | KB → GB; fall back to `MaxCapacity` |
| Total slots | `Win32_PhysicalMemoryArray.MemoryDevices` | |
| Board maker | `Win32_BaseBoard.Manufacturer` | |
| Board model | `Win32_BaseBoard.Product` | |
| Board rev | `Win32_BaseBoard.Version` | |

**Derived:** total installed = Σ Capacity · populated slots = module count · free slots = MemoryDevices − populated · memory type = decode of first module's SMBIOSMemoryType.

**Reference data from the target machine (2026-06-30):** 2× 8 GB SK Hynix `HMA81GS6CJR8N-XN`, rated 3200 / running 2933, DDR4; array max 64 GB across 2 slots; board Dell `0CXCCY` rev A03.

## Decoders

- **SMBIOS memory type → name:** 18=DDR, 19=DDR2, 24=DDR3, 26=DDR4, 27=LPDDR, 28=LPDDR2, 29=LPDDR3, 30=LPDDR4, 34=DDR5, 35=LPDDR5. Fallback: `Unknown (<n>)`.
- **JEDEC vendor code → name:** best-effort small table (SK Hynix `80AD`, Samsung `80CE`, Micron `802C`, Kingston `7F98`, Crucial, Corsair, G.Skill). Fallback: show the raw code.

## Behavior / UX

- **Default:** double-click `RamInfo.cmd` → launches the script with `-ExecutionPolicy Bypass` → GUI window appears.
- **`-Console` switch:** prints the same report as plain text to the terminal instead of opening the window. Doubles as the verification path (GUI can't be visually asserted in automation).
- **Fallback:** if WinForms assemblies fail to load, automatically render the console report instead of crashing.

### Window layout

```
┌─ RAM Info ───────────────────────────────────────┐
│ Total installed:  16 GB        Type: DDR4          │
│ Slots:            2 used of 2  (0 free)            │
│ Max capacity:     64 GB  (per firmware)           │
│ Motherboard:      Dell 0CXCCY  (rev A03)          │
│                                                    │
│ ┌ Slot ─ Size ─ Rated ─ Current ─ Maker ─ Part# ┐ │
│ │ DIMM A  8 GB  3200    2933      SK Hynix  HMA…  │ │
│ │ DIMM B  8 GB  3200    2933      SK Hynix  HMA…  │ │
│ └────────────────────────────────────────────────┘ │
│ ⚠ Max supported speed isn't stored in firmware.    │
│   Check the spec for Dell 0CXCCY.                  │
│                              [ Copy ]  [ Close ]   │
└────────────────────────────────────────────────────┘
```

- Summary fields as labels; per-module table as a `ListView` (Details view).
- **Copy** button → plain-text version of the whole report to the clipboard.
- **Close** button → exit.

## Architecture

Three thin layers, each independently runnable/testable:

1. **Collect** — `Get-RamModules`, `Get-RamArrayInfo`, `Get-MotherboardInfo`: query CIM, return clean PSCustomObjects. Decoders `ConvertTo-MemoryTypeName`, `ConvertTo-VendorName`.
2. **Report** — `Get-RamReport`: composes one summary object (totals, free slots, type, board string, module list).
3. **Render** — `Write-RamConsole` (text) and `Show-RamWindow` (WinForms) both consume the report object. `-Console` or WinForms load-failure routes to the text renderer.

Entry point parses params (`-Console`), builds the report once, dispatches to a renderer.

## Error handling

- Each `Get-CimInstance` wrapped in try/catch. On failure (non-Windows, broken WMI), show a friendly one-line error in whichever renderer is active rather than a stack trace.
- Missing/blank fields render as `Unknown`: null `Speed`, null/zero `ConfiguredClockSpeed`, blank `PartNumber`, blank `Manufacturer`.
- `MaxCapacityEx` preferred when > 0, else `MaxCapacity`; if both empty → `Unknown`.

## Files

- `Show-RamInfo.ps1` — the program (all layers).
- `RamInfo.cmd` — double-click launcher (`powershell -ExecutionPolicy Bypass -File Show-RamInfo.ps1`).

## Out of scope (YAGNI)

- No Refresh button (Copy + Close only).
- No runtime web/online spec lookup.
- No file export (Copy covers sharing).
- No admin elevation (these classes read as standard user).
- No cross-platform support.

## Verification

Run `Show-RamInfo.ps1 -Console` and confirm it reports: 16 GB total, rated 3200 / running 2933, DDR4, max 64 GB, 2 slots (0 free), Dell 0CXCCY. Confirm the WinForms form object constructs without error (build the form, skip `ShowDialog` in the smoke test). Confirm `-Console` fallback triggers if WinForms is unavailable.
