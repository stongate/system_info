# Firmware & Security (slice J) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a *Firmware & Security* tab that reports BIOS, UEFI-vs-Legacy, Secure Boot, and TPM, and derives a Windows-11-readiness checklist — all from no-admin sources, honest about what it can't check.

**Architecture:** Mirror the established pattern — a self-contained collector `Get-FirmwareInfo` (thin I/O) → a pure `New-FirmwareReport -Raw` (shapes facts + computes readiness) → a pure `Get-FirmwareInsights` (info notes) → wired into `New-SystemReport`/`Get-SystemInsights`/`Invoke-SystemInfo` → rendered in `Write-SystemConsole`, a new tab, and an Overview line. No change to `New-UpgradeReport`.

**Tech Stack:** Windows PowerShell / PowerShell 7, WinForms, CIM/WMI + registry, the repo's zero-dependency `It`/`Assert-Equal` test harness.

**Spec:** `docs/superpowers/specs/2026-07-02-firmware-security-design.md`

**Conventions (from the codebase):**
- Pure builders (`New-*Report`) and insights (`Get-*Insights`) are unit-tested; collectors (`Get-*Info`) are **not** — they are verified via the real `-Console` run (see the comments on `Get-BatteryInfo`/`Get-LoadInfo`).
- Notes are `[pscustomobject]@{ Kind; Text }`; insight functions end with `return , @($notes)`.
- Insight wiring uses assign-then-`+=` (never `@()`-wrap the call).
- Null/missing → `Unknown`/omit; never fabricate.
- Commit after each green task. End every commit message with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer (two `-m` flags).
- Branch is already `feature/firmware_security`.

---

## File Structure

| File | Change |
|------|--------|
| `Show-SystemInfo.ps1` | Add `New-FirmwareReport` (after `New-GpuSensorReport`, before the `# Insights` banner); `Get-FirmwareInsights` (after `Get-GamingInsights`, before `Get-SystemInsights`); `Get-FirmwareInfo` (after `Get-GpuSensorInfo`, before the `# Renderers` banner). Wire `-Firmware` into `Get-SystemInsights`, `New-SystemReport`, `Invoke-SystemInfo`. Add a console section in `Write-SystemConsole` (before the `if ($Report.Upgrade)` block), a `Security:` Overview row, and a `Firmware & Security` tab (before the Upgrade tab) in `New-SystemForm`. |
| `tests/SystemInfo.Tests.ps1` | Add a Firmware test section before the final summary (`Write-Host "`n$script:Pass passed…"`). |
| `tests/GuiSmoke.ps1` | Add a firmware fixture; pass `-Firmware` to both reports; bump 10→11 and 7→8 tab counts; assert the new tab + Overview line. |
| `README.md` | Add a *Firmware & Security* bullet under "What it shows". |

Line numbers below are guides from the pre-implementation file; anchor edits to the named functions/nearby code, since earlier edits shift later line numbers.

---

## Task 1: `New-FirmwareReport` (pure builder)

**Files:**
- Modify: `Show-SystemInfo.ps1` (insert after `New-GpuSensorReport`, i.e. after the line `ThermalThrottle = ...}` / its closing `}` near line 805, before the `# ===` Insights banner at ~807)
- Test: `tests/SystemInfo.Tests.ps1` (insert new section before the summary at the tail, ~line 758)

- [ ] **Step 1: Write the failing tests**

Insert this block in `tests/SystemInfo.Tests.ps1` immediately **before** the final two lines (`Write-Host "`n$script:Pass passed, $script:Fail failed`n"` and the `if ($script:Fail)…`):

```powershell
Write-Host "`nNew-FirmwareReport" -ForegroundColor Cyan
$fwWin11 = New-FirmwareReport -Raw ([pscustomobject]@{ BiosVendor='Dell Inc.'; BiosVersion='1.33.1'; BiosDate=[datetime]'2024-11-17'; IsUefi=$true; SecureBootRaw=1; TpmName='Trusted Platform Module 2.0'; OsBuild=26200; RamBytes=17179869184; SysDriveBytes=1024209543168; AddressWidth=64 })
It 'fw type uefi'         { Assert-Equal 'UEFI'   $fwWin11.FirmwareType 'uefi' }
It 'fw secure boot on'    { Assert-Equal 'On'     $fwWin11.SecureBoot 'sb on' }
It 'fw tpm present'       { Assert-Equal $true    $fwWin11.Tpm.Present 'tpm present' }
It 'fw tpm version'       { Assert-Equal '2.0'    $fwWin11.Tpm.Version 'tpm ver' }
It 'fw bios version'      { Assert-Equal '1.33.1' $fwWin11.Bios.Version 'bios ver' }
It 'fw already win11'     { Assert-Equal $true    $fwWin11.Win11.AlreadyWin11 'already' }
It 'fw summary running'   { Assert-Equal $true ([bool]($fwWin11.Win11.Summary -match 'running Windows 11')) 'summary' }
It 'fw cpu model unknown' { Assert-Equal 'unknown' (@($fwWin11.Win11.Requirements | Where-Object { $_.Name -eq 'CPU model' })[0].Met) 'cpu unknown' }
It 'fw tpm req met'       { Assert-Equal $true (@($fwWin11.Win11.Requirements | Where-Object { $_.Name -eq 'TPM 2.0' })[0].Met) 'tpm met' }

$fwLegacy = New-FirmwareReport -Raw ([pscustomobject]@{ BiosVendor='X'; BiosVersion='A1'; BiosDate=$null; IsUefi=$false; SecureBootRaw=$null; TpmName=$null; OsBuild=19045; RamBytes=8589934592; SysDriveBytes=256060514304; AddressWidth=64 })
It 'fw legacy type'       { Assert-Equal 'Legacy'      $fwLegacy.FirmwareType 'legacy' }
It 'fw legacy sb unavail' { Assert-Equal 'Unavailable' $fwLegacy.SecureBoot 'sb unavail' }
It 'fw legacy tpm absent' { Assert-Equal $false        $fwLegacy.Tpm.Present 'no tpm' }
It 'fw legacy not win11'  { Assert-Equal $false        $fwLegacy.Win11.AlreadyWin11 'not win11' }
It 'fw legacy not ready'  { Assert-Equal $true ([bool]($fwLegacy.Win11.Summary -match 'Not ready')) 'not ready' }

$fwSbOff = New-FirmwareReport -Raw ([pscustomobject]@{ BiosVendor='X'; BiosVersion='A1'; BiosDate=$null; IsUefi=$true; SecureBootRaw=0; TpmName='Trusted Platform Module 2.0'; OsBuild=19045; RamBytes=17179869184; SysDriveBytes=512110190592; AddressWidth=64 })
It 'fw sb off'            { Assert-Equal 'Off' $fwSbOff.SecureBoot 'sb off' }
It 'fw sb off reason'     { Assert-Equal $true ([bool]($fwSbOff.Win11.Summary -match 'Secure Boot off')) 'sb off reason' }

$fwTpmNoVer = New-FirmwareReport -Raw ([pscustomobject]@{ IsUefi=$true; SecureBootRaw=1; TpmName='Trusted Platform Module'; OsBuild=19045; RamBytes=17179869184; SysDriveBytes=512110190592; AddressWidth=64 })
It 'fw tpm no version'    { Assert-Equal '' "$($fwTpmNoVer.Tpm.Version)" 'no ver' }
It 'fw tpm unknown met'   { Assert-Equal 'unknown' (@($fwTpmNoVer.Win11.Requirements | Where-Object { $_.Name -eq 'TPM 2.0' })[0].Met) 'tpm unknown' }

$fwReady = New-FirmwareReport -Raw ([pscustomobject]@{ IsUefi=$true; SecureBootRaw=1; TpmName='Trusted Platform Module 2.0'; OsBuild=19045; RamBytes=17179869184; SysDriveBytes=512110190592; AddressWidth=64 })
It 'fw win10 meets'       { Assert-Equal $true ([bool]($fwReady.Win11.Summary -match 'Meets Windows 11')) 'meets' }

$fwNull = New-FirmwareReport -Raw $null
It 'fw null type'         { Assert-Equal '' "$($fwNull.FirmwareType)" 'null type' }
It 'fw null tpm absent'   { Assert-Equal $false $fwNull.Tpm.Present 'null tpm' }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: the new `fw …` lines FAIL (`New-FirmwareReport` not recognized); the run ends `… failed` and exits 1.

- [ ] **Step 3: Implement `New-FirmwareReport`**

Insert into `Show-SystemInfo.ps1` after `New-GpuSensorReport` (before the `# ===… Insights` banner):

```powershell
function New-FirmwareReport {
    # Build the Firmware & Security section (pure) from the raw firmware bundle
    # (no cmdlets here). Computes a Windows 11 readiness checklist; the CPU-model
    # requirement has no honest source and is always 'unknown' (never judged).
    param([object] $Raw)
    if ($null -eq $Raw) { $Raw = [pscustomobject]@{} }

    $firmwareType = if ($Raw.IsUefi) { 'UEFI' } elseif ($null -ne $Raw.IsUefi) { 'Legacy' } else { $null }
    $secureBoot = if ($Raw.SecureBootRaw -eq 1) { 'On' }
                  elseif ($Raw.SecureBootRaw -eq 0) { 'Off' }
                  elseif ($firmwareType -eq 'Legacy') { 'Unavailable' }
                  else { $null }

    $tpmPresent = -not [string]::IsNullOrWhiteSpace($Raw.TpmName)
    $tpmVersion = $null
    if ($tpmPresent -and "$($Raw.TpmName)" -match '(\d+\.\d+)') { $tpmVersion = $Matches[1] }

    $bios = [pscustomobject]@{
        Vendor      = if ([string]::IsNullOrWhiteSpace($Raw.BiosVendor)) { $null } else { "$($Raw.BiosVendor)".Trim() }
        Version     = if ([string]::IsNullOrWhiteSpace($Raw.BiosVersion)) { $null } else { "$($Raw.BiosVersion)".Trim() }
        ReleaseDate = $Raw.BiosDate
    }

    # ---- Windows 11 readiness ----
    $alreadyWin11 = ($null -ne $Raw.OsBuild -and [int]$Raw.OsBuild -ge 22000)
    $ramGB  = if ($null -ne $Raw.RamBytes) { [math]::Round([double]$Raw.RamBytes / 1GB, 1) } else { $null }
    $diskGB = if ($null -ne $Raw.SysDriveBytes) { [math]::Round([double]$Raw.SysDriveBytes / 1GB, 0) } else { $null }

    if ($tpmPresent -and "$tpmVersion" -like '2*') { $tpmMet = $true }
    elseif (-not $tpmPresent) { $tpmMet = $false }
    elseif ($tpmVersion) { $tpmMet = $false }
    else { $tpmMet = 'unknown' }
    $tpmDetail = if ($tpmPresent) { if ($tpmVersion) { "TPM $tpmVersion detected" } else { 'TPM present (version unknown)' } } else { 'No TPM detected' }

    if ($secureBoot -eq 'On') { $sbMet = $true } elseif ($null -eq $secureBoot) { $sbMet = 'unknown' } else { $sbMet = $false }
    if ($firmwareType -eq 'UEFI') { $uefiMet = $true } elseif ($null -eq $firmwareType) { $uefiMet = 'unknown' } else { $uefiMet = $false }
    if ($null -eq $ramGB) { $ramMet = 'unknown' } elseif ($ramGB -ge 4) { $ramMet = $true } else { $ramMet = $false }
    if ($null -eq $diskGB) { $diskMet = 'unknown' } elseif ($diskGB -ge 64) { $diskMet = $true } else { $diskMet = $false }
    if ($null -eq $Raw.AddressWidth) { $cpuBitMet = 'unknown' } elseif ([int]$Raw.AddressWidth -eq 64) { $cpuBitMet = $true } else { $cpuBitMet = $false }

    $reqs = @(
        [pscustomobject]@{ Name = 'TPM 2.0';          Met = $tpmMet;    Detail = $tpmDetail }
        [pscustomobject]@{ Name = 'Secure Boot';      Met = $sbMet;     Detail = $(if ($secureBoot) { $secureBoot } else { 'Unknown' }) }
        [pscustomobject]@{ Name = 'UEFI firmware';    Met = $uefiMet;   Detail = $(if ($firmwareType) { $firmwareType } else { 'Unknown' }) }
        [pscustomobject]@{ Name = 'RAM >= 4 GB';      Met = $ramMet;    Detail = $(if ($null -ne $ramGB) { "$ramGB GB" } else { 'Unknown' }) }
        [pscustomobject]@{ Name = 'Storage >= 64 GB'; Met = $diskMet;   Detail = $(if ($null -ne $diskGB) { "$diskGB GB" } else { 'Unknown' }) }
        [pscustomobject]@{ Name = '64-bit CPU';       Met = $cpuBitMet; Detail = $(if ($null -ne $Raw.AddressWidth) { "$($Raw.AddressWidth)-bit" } else { 'Unknown' }) }
        [pscustomobject]@{ Name = 'CPU model';        Met = 'unknown';  Detail = "Verify against Microsoft's supported-CPU list" }
    )

    $unmet = @($reqs | Where-Object { ($_.Met -is [bool]) -and (-not $_.Met) })
    if ($alreadyWin11) {
        $summary = 'This PC is running Windows 11.'
    } elseif ($unmet.Count -eq 0) {
        $summary = "Meets Windows 11's checkable requirements - verify the CPU model against Microsoft's supported-CPU list."
    } else {
        $reasons = @($unmet | ForEach-Object {
            switch ($_.Name) {
                'TPM 2.0'          { 'no TPM 2.0' }
                'Secure Boot'      { 'Secure Boot off' }
                'UEFI firmware'    { 'Legacy firmware' }
                'RAM >= 4 GB'      { 'insufficient RAM' }
                'Storage >= 64 GB' { 'insufficient storage' }
                '64-bit CPU'       { '32-bit CPU' }
                default            { $_.Name }
            }
        }) -join ', '
        $summary = "Not ready for Windows 11: $reasons."
    }

    [pscustomobject]@{
        Bios         = $bios
        FirmwareType = $firmwareType
        SecureBoot   = $secureBoot
        Tpm          = [pscustomobject]@{ Present = $tpmPresent; Version = $tpmVersion }
        Win11        = [pscustomobject]@{ AlreadyWin11 = $alreadyWin11; Requirements = $reqs; Summary = $summary }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: all `fw …` lines PASS; the run ends `… 0 failed` and exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Firmware & Security: New-FirmwareReport + readiness (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `Get-FirmwareInsights` (pure notes)

**Files:**
- Modify: `Show-SystemInfo.ps1` (insert after `Get-GamingInsights`, before `Get-SystemInsights` at ~line 1051)
- Test: `tests/SystemInfo.Tests.ps1` (append to the Firmware section from Task 1)

- [ ] **Step 1: Write the failing tests**

Append after the Task-1 block in `tests/SystemInfo.Tests.ps1` (the `$fwWin11`, `$fwSbOff`, `$fwLegacy` fixtures are already defined above):

```powershell
Write-Host "`nGet-FirmwareInsights" -ForegroundColor Cyan
It 'fw note sb off'     { Assert-Equal $true (HasNote (Get-FirmwareInsights -Firmware $fwSbOff) 'Secure Boot is supported but turned off') 'sb off note' }
It 'fw note legacy'     { Assert-Equal $true (HasNote (Get-FirmwareInsights -Firmware $fwLegacy) 'Legacy (CSM) mode') 'legacy note' }
It 'fw note no tpm'     { Assert-Equal $true (HasNote (Get-FirmwareInsights -Firmware $fwLegacy) 'No TPM detected') 'no tpm note' }
It 'fw healthy no note' { Assert-Equal 0 (@(Get-FirmwareInsights -Firmware $fwWin11).Count) 'healthy none' }
It 'fw null no note'    { Assert-Equal 0 (@(Get-FirmwareInsights -Firmware $null).Count) 'null none' }
It 'fw notes all info'  { Assert-Equal 'info' ((@(Get-FirmwareInsights -Firmware $fwLegacy) | ForEach-Object { $_.Kind } | Sort-Object -Unique) -join ',') 'info kind' }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: the six `fw note…`/`fw … note` lines FAIL (`Get-FirmwareInsights` not recognized); exits 1.

- [ ] **Step 3: Implement `Get-FirmwareInsights`**

Insert into `Show-SystemInfo.ps1` after `Get-GamingInsights` (before `Get-SystemInsights`):

```powershell
function Get-FirmwareInsights {
    # Firmware/security posture notes (all 'info' - configuration/posture, not a
    # malfunction). Deliberately NO roll-up "not Win11-ready" note: the atomic
    # notes below already carry the blockers, and a roll-up would duplicate them in
    # the Notes box (the same don't-duplicate choice the Upgrade Advisor made). The
    # readiness verdict is presentation (tab + console), not a note.
    param([object] $Firmware)
    $notes = @()
    if ($null -eq $Firmware) { return , @($notes) }
    if ($Firmware.SecureBoot -eq 'Off') {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = 'Secure Boot is supported but turned off; enabling it in firmware improves boot security (and is required for Windows 11).' }
    }
    if ($Firmware.FirmwareType -eq 'Legacy') {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = 'Firmware is in Legacy (CSM) mode; UEFI is required for Secure Boot and Windows 11.' }
    }
    if ($Firmware.Tpm -and $Firmware.Tpm.Present -eq $false) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = 'No TPM detected. Windows 11 requires TPM 2.0; a firmware TPM (Intel PTT / AMD fTPM) may be disabled in BIOS.' }
    }
    return , @($notes)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: all `fw` lines PASS; exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Firmware & Security: Get-FirmwareInsights notes (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire into `New-SystemReport` + `Get-SystemInsights`

**Files:**
- Modify: `Show-SystemInfo.ps1` — `Get-SystemInsights` (~1051), `New-SystemReport` (~1117)
- Test: `tests/SystemInfo.Tests.ps1` (append to the Firmware section)

- [ ] **Step 1: Write the failing tests**

Append to the Firmware section in `tests/SystemInfo.Tests.ps1` (uses existing `$cpuDev`, `$memDual`, `$gpu`, `$st` fixtures):

```powershell
Write-Host "`nSystem report (Firmware wiring)" -ForegroundColor Cyan
$sysFw = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $fwSbOff
It 'fw wiring note'    { Assert-Equal $true  (HasNote $sysFw 'Secure Boot is supported but turned off') 'wired' }
$sysNoFw = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $null
It 'fw wiring null ok' { Assert-Equal $false (HasNote $sysNoFw 'Secure Boot') 'null no note' }
$repFw = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $fwWin11
It 'fw report section' { Assert-Equal 'UEFI' $repFw.Firmware.FirmwareType 'section' }
It 'fw report no arg'  { Assert-Equal '' "$((New-SystemReport -Cpu $cpuDev -Memory $memDual).Firmware)" 'null default' }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: `fw wiring note` and `fw report section` FAIL (no `-Firmware` param; `.Firmware` is empty); exits 1.

- [ ] **Step 3a: Add `-Firmware` to `Get-SystemInsights`**

In `Show-SystemInfo.ps1`, change the `Get-SystemInsights` `param(...)` line to add `-Firmware`:

```powershell
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null, [object] $Battery = $null, [object] $Load = $null, [object] $Network = $null, [object] $GpuSensor = $null, [object] $Gaming = $null, [object] $Firmware = $null)
```

Then, immediately after the Gaming block (the `if ($null -ne $Gaming) { $gamingNotes = …; $notes += $gamingNotes }`), add:

```powershell
    if ($null -ne $Firmware) {
        $firmwareNotes = Get-FirmwareInsights -Firmware $Firmware
        $notes += $firmwareNotes
    }
```

- [ ] **Step 3b: Add `-Firmware` to `New-SystemReport`**

Change the `New-SystemReport` `param(...)` line to add `-Firmware`:

```powershell
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null, [object] $Battery = $null, [object] $Load = $null, [object] $Network = $null, [object] $GpuSensor = $null, [object] $Firmware = $null)
```

Pass it into the `Get-SystemInsights` call (append `-Firmware $Firmware`):

```powershell
    $insights = Get-SystemInsights -Cpu $Cpu -Memory $Memory -Gpu $Gpu -Storage $Storage -Battery $Battery -Load $Load -Network $Network -GpuSensor $GpuSensor -Gaming $gaming -Firmware $Firmware
```

Add `Firmware = $Firmware` to the returned object (place it just before `Upgrade = $upgrade`):

```powershell
        Firmware  = $Firmware
        Upgrade   = $upgrade
        Insights  = $insights
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: all `fw …` lines PASS; exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Firmware & Security: wire into report + insights (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Console section in `Write-SystemConsole`

**Files:**
- Modify: `Show-SystemInfo.ps1` — `Write-SystemConsole` (insert before the `if ($Report.Upgrade)` block, ~line 1551)
- Test: `tests/SystemInfo.Tests.ps1` (append to the Firmware section)

- [ ] **Step 1: Write the failing tests**

Append to the Firmware section in `tests/SystemInfo.Tests.ps1`:

```powershell
Write-Host "`nWrite-SystemConsole (Firmware & Security)" -ForegroundColor Cyan
$conFw = (Write-SystemConsole (New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $fwWin11) | Out-String)
It 'fw console header'    { Assert-Equal $true ([bool]($conFw -match 'Firmware & Security')) 'header' }
It 'fw console tpm'       { Assert-Equal $true ([bool]($conFw -match 'TPM')) 'tpm' }
It 'fw console readiness' { Assert-Equal $true ([bool]($conFw -match 'Windows 11 readiness')) 'readiness' }
It 'fw console verdict'   { Assert-Equal $true ([bool]($conFw -match 'running Windows 11')) 'verdict' }
$conNoFw = (Write-SystemConsole (New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st) | Out-String)
It 'fw console absent'    { Assert-Equal $false ([bool]($conNoFw -match 'Firmware & Security')) 'absent' }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: `fw console header/tpm/readiness/verdict` FAIL (no console section yet); exits 1.

- [ ] **Step 3: Implement the console section**

In `Write-SystemConsole`, insert immediately **before** the `if ($Report.Upgrade) {` block:

```powershell
    if ($Report.Firmware) {
        $fw = $Report.Firmware
        $biosStr = if ($fw.Bios.Version) {
            "$(if ($fw.Bios.Vendor) { $fw.Bios.Vendor + ' ' } else { '' })$($fw.Bios.Version)" + $(if ($fw.Bios.ReleaseDate) { ' ({0:MMM yyyy})' -f $fw.Bios.ReleaseDate } else { '' })
        } else { 'Unknown' }
        $tpmStr = if ($fw.Tpm.Present) { if ($fw.Tpm.Version) { $fw.Tpm.Version } else { 'Present (version unknown)' } } else { 'Not detected' }
        '  Firmware & Security'
        '  -------------------'
        '  BIOS             : {0}' -f $biosStr
        '  Firmware type    : {0}' -f $(if ($fw.FirmwareType) { $fw.FirmwareType } else { 'Unknown' })
        '  Secure Boot      : {0}' -f $(if ($fw.SecureBoot) { $fw.SecureBoot } else { 'Unknown' })
        '  TPM              : {0}' -f $tpmStr
        if ($fw.Win11) {
            '  Windows 11 readiness'
            foreach ($r in $fw.Win11.Requirements) {
                $mark = if ($r.Met -is [bool] -and $r.Met) { 'OK' } elseif ($r.Met -is [bool]) { 'NO' } else { '??' }
                '    [{0}] {1} - {2}' -f $mark, $r.Name, $r.Detail
            }
            '  Verdict          : {0}' -f $fw.Win11.Summary
        }
        '  (firmware/security read without admin, best-effort; CPU-model requirement not checked here)'
        ''
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: all `fw console …` lines PASS; exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Firmware & Security: console section (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `Get-FirmwareInfo` collector + `Invoke-SystemInfo` wiring

No unit test (collectors are verified via the real `-Console` run, per codebase convention). This task makes the tool actually read this machine's firmware.

**Files:**
- Modify: `Show-SystemInfo.ps1` — add `Get-FirmwareInfo` (after `Get-GpuSensorInfo`, before the `# Renderers` banner ~1381); wire into `Invoke-SystemInfo` (~2060)

- [ ] **Step 1: Implement `Get-FirmwareInfo`**

Insert after `Get-GpuSensorInfo` (before the `# ===… Renderers` banner):

```powershell
function Get-FirmwareInfo {
    # Firmware + platform-security facts for New-FirmwareReport, all from no-admin
    # sources (the authoritative Get-Tpm / Confirm-SecureBootUEFI need admin, so we
    # use the registry + the PnP SecurityDevices friendly name instead). Firmware
    # type is derived from the SecureBoot\State key's presence. Self-guarding;
    # always returns a bundle (never $null); verified via the -Console run.
    $bios = $null
    try { $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object -First 1 } catch { }

    $sbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    $isUefi = Test-Path $sbKey
    $sbEnabled = $null
    if ($isUefi) {
        try { $sbEnabled = [int](Get-ItemProperty -Path $sbKey -Name UEFISecureBootEnabled -ErrorAction Stop).UEFISecureBootEnabled } catch { }
    }

    $tpmName = $null
    try {
        $tpmDev = Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
                  Where-Object { $_.PNPClass -eq 'SecurityDevices' -and $_.Name -match 'Trusted Platform|TPM' } |
                  Select-Object -First 1
        if ($tpmDev) { $tpmName = "$($tpmDev.Name)".Trim() }
    } catch { }

    $osBuild = $null
    try { $osBuild = [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber } catch { }
    $ramBytes = $null
    try { $ramBytes = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory } catch { }
    $sysDriveBytes = $null
    try {
        $sd = "$env:SystemDrive".TrimEnd('\')
        $sysDriveBytes = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sd'" -ErrorAction Stop).Size
    } catch { }
    $addrWidth = $null
    try { $addrWidth = [int](Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).AddressWidth } catch { }

    [pscustomobject]@{
        BiosVendor    = if ($bios) { "$($bios.Manufacturer)".Trim() } else { $null }
        BiosVersion   = if ($bios) { "$($bios.SMBIOSBIOSVersion)".Trim() } else { $null }
        BiosDate      = if ($bios) { $bios.ReleaseDate } else { $null }
        IsUefi        = $isUefi
        SecureBootRaw = $sbEnabled
        TpmName       = $tpmName
        OsBuild       = $osBuild
        RamBytes      = $ramBytes
        SysDriveBytes = $sysDriveBytes
        AddressWidth  = $addrWidth
    }
}
```

- [ ] **Step 2: Wire into `Invoke-SystemInfo`**

In the collector `try { … }` block (where `$gsRaw = Get-GpuSensorInfo` is), add a line:

```powershell
        $gsRaw   = Get-GpuSensorInfo
        $fwRaw   = Get-FirmwareInfo
```

After the `$gpuSensor = …` build block (before the `$report = New-SystemReport …` line), add:

```powershell
    $firmware = New-FirmwareReport -Raw $fwRaw
```

Change the `New-SystemReport` call to pass `-Firmware $firmware`:

```powershell
    $report = New-SystemReport -Cpu $cpu -Memory $memory -Gpu $gpu -Storage $storage -Battery $battery -Load $load -Network $network -GpuSensor $gpuSensor -Firmware $firmware
```

- [ ] **Step 3: Verify on real hardware via `-Console`**

Run: `powershell.exe -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console`
Expected: a `Firmware & Security` section appears (after Gaming, before Upgrade Advisor) showing — on this Dell XPS 15 9500 — BIOS `Dell Inc. 1.33.1 (Nov 2024)`, Firmware type `UEFI`, Secure Boot `On`, TPM `2.0`, a `Windows 11 readiness` checklist with `[OK]` on TPM/Secure Boot/UEFI/RAM/Storage/64-bit and `[??]` on CPU model, and Verdict `This PC is running Windows 11.` No crash; the unit suite still passes.

Also run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1` → `0 failed`.

- [ ] **Step 4: Commit**

```bash
git add Show-SystemInfo.ps1
git commit -m "Firmware & Security: collector + Invoke-SystemInfo wiring (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: GUI — Overview `Security:` row + `Firmware & Security` tab

**Files:**
- Modify: `Show-SystemInfo.ps1` — `New-SystemForm` (Overview block ~1637-1667; insert new tab before the Upgrade tab ~1976)
- Modify: `tests/GuiSmoke.ps1` (fixture + counts + assertions)

- [ ] **Step 1: Update the GUI smoke test (the failing spec)**

In `tests/GuiSmoke.ps1`:

(a) After the `$gsen = New-GpuSensorReport …` line (~32), add a firmware fixture:

```powershell
$fw = New-FirmwareReport -Raw ([pscustomobject]@{ BiosVendor='Dell Inc.'; BiosVersion='1.33.1'; BiosDate=[datetime]'2024-11-17'; IsUefi=$true; SecureBootRaw=1; TpmName='Trusted Platform Module 2.0'; OsBuild=26200; RamBytes=17179869184; SysDriveBytes=1024209543168; AddressWidth=64 })
```

(b) Change the two report builds (~33-34) to pass `-Firmware $fw`:

```powershell
$report = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st -Battery $bat -Load $load -Network $net -GpuSensor $gsen -Firmware $fw
$reportNoBat = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st -Firmware $fw
```

(c) Change the tab-count check (~52) from 10 to 11:

```powershell
    Check ($tabControl.TabPages.Count -eq 11) 'eleven tabs'
```

(d) In the tab-names check (~54), add `Firmware & Security` to the `-and` chain and its message, e.g. append before the closing `)`:

```powershell
 -and ($tabNames -contains 'Firmware & Security')
```

(e) After the Upgrade-tab checks (after the `'Upgrade tab shows the honesty caption'` line, ~122), add:

```powershell
    $fwTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Firmware & Security' } | Select-Object -First 1
    Check ($null -ne $fwTab) 'has Firmware & Security tab'
    $fwText = (Get-AllText $fwTab) -join "`n"
    Check ([bool]($fwText -match 'Windows 11 readiness')) 'Firmware tab shows readiness checklist'
    Check ([bool]($fwText -match 'running Windows 11'))    'Firmware tab shows the summary verdict'
    Check ([bool]($fwText -match 'Microsoft'))             'Firmware tab shows the honesty caption'
    Check ([bool]($ovText -match 'Security:'))             'Overview has a Security line'
```

(f) In the desktop case, change the count (~128) from 7 to 8 and add a presence check:

```powershell
    Check ($tc2.TabPages.Count -eq 8)                     'desktop: eight tabs (Gaming + Firmware & Security + Upgrade; no Battery/Live/Network)'
    Check ($names2 -contains 'Firmware & Security')       'desktop: Firmware & Security tab present'
```

- [ ] **Step 2: Run the GUI smoke to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: FAILs — `eleven tabs` (still 10), no `Firmware & Security` tab, no Overview `Security:` line; exits 1.

- [ ] **Step 3a: Add the Overview `Security:` row**

In `New-SystemForm`, just before the `$oy = Add-KvBlock -Parent $ovTop -Keys @('Processor:', …)` line, compute the security line:

```powershell
    $securityLine = if ($null -ne $Report.Firmware) {
        $fwo = $Report.Firmware
        $segs = @()
        if ($fwo.SecureBoot) { $segs += "Secure Boot $($fwo.SecureBoot)" }
        if ($fwo.Tpm.Present) { $segs += $(if ($fwo.Tpm.Version) { "TPM $($fwo.Tpm.Version)" } else { 'TPM present' }) } else { $segs += 'No TPM' }
        if ($fwo.FirmwareType) { $segs += $fwo.FirmwareType }
        if ($segs.Count) { $segs -join '  -  ' } else { 'Unknown' }
    } else { 'Unknown' }
```

Change the `Add-KvBlock` call to add the `Security:` key and `$securityLine` value:

```powershell
    $oy = Add-KvBlock -Parent $ovTop -Keys @('Processor:', 'Graphics:', 'Memory:', 'Storage:', 'Battery:', 'Network:', 'Gaming:', 'Security:') -Values @($cpuLine, $gpuLine, $memLine, $storageLine, $batteryLine, $networkLine, $gamingLine, $securityLine) -X 4 -Y 6 -KeyW 90 -ValW 460
```

Give the 8th row room — change `$ovTop.Height = 194` to:

```powershell
    $ovTop.Height = 214
```

- [ ] **Step 3b: Add the `Firmware & Security` tab**

In `New-SystemForm`, insert **before** the `# --- Upgrade tab …` block (`if ($null -ne $Report.Upgrade) {`):

```powershell
    # --- Firmware & Security tab (present whenever firmware was read;
    #     Invoke-SystemInfo always collects it, so it is effectively always shown) ---
    if ($null -ne $Report.Firmware) {
        $fw = $Report.Firmware
        $tabFw = New-Object System.Windows.Forms.TabPage
        $tabFw.Text = 'Firmware & Security'
        $tabFw.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)

        $biosStr = if ($fw.Bios.Version) {
            "$(if ($fw.Bios.Vendor) { $fw.Bios.Vendor + ' ' } else { '' })$($fw.Bios.Version)" + $(if ($fw.Bios.ReleaseDate) { ' ({0:MMM yyyy})' -f $fw.Bios.ReleaseDate } else { '' })
        } else { 'Unknown' }
        $tpmStr = if ($fw.Tpm.Present) { if ($fw.Tpm.Version) { $fw.Tpm.Version } else { 'Present (version unknown)' } } else { 'Not detected' }
        $fwKeys = @('BIOS:', 'Firmware type:', 'Secure Boot:', 'TPM:')
        $fwVals = @(
            $biosStr
            $(if ($fw.FirmwareType) { $fw.FirmwareType } else { 'Unknown' })
            $(if ($fw.SecureBoot) { $fw.SecureBoot } else { 'Unknown' })
            $tpmStr
        )
        $fy = Add-KvBlock -Parent $tabFw -Keys $fwKeys -Values $fwVals -KeyW 130 -ValW 420

        if ($fw.Win11) {
            $rHdr = New-Object System.Windows.Forms.Label
            $rHdr.Text = 'Windows 11 readiness'
            $rHdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $rHdr.Location = New-Object System.Drawing.Point(14, ($fy + 4))
            $rHdr.AutoSize = $true
            $tabFw.Controls.Add($rHdr)
            $ry = $fy + 28
            $rBody = New-Object System.Windows.Forms.Label
            $rBody.Text = (@($fw.Win11.Requirements | ForEach-Object {
                $mark = if ($_.Met -is [bool] -and $_.Met) { '[OK]' } elseif ($_.Met -is [bool]) { '[--]' } else { '[ ?]' }
                "$mark $($_.Name) - $($_.Detail)"
            }) -join "`r`n")
            $rBody.Location = New-Object System.Drawing.Point(20, $ry)
            $rBody.AutoSize = $true
            $tabFw.Controls.Add($rBody)
            $ry += ($fw.Win11.Requirements.Count * 20) + 8

            $sumLbl = New-Object System.Windows.Forms.Label
            $sumLbl.Text = $fw.Win11.Summary
            $sumLbl.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $sumLbl.Location = New-Object System.Drawing.Point(14, ($ry + 2))
            $sumLbl.MaximumSize = New-Object System.Drawing.Size(560, 0)
            $sumLbl.AutoSize = $true
            $tabFw.Controls.Add($sumLbl)
            $fy = $ry + $sumLbl.PreferredHeight + 6
        }

        $fwCap = New-Object System.Windows.Forms.Label
        $fwCap.Text = "Firmware/security facts are read without admin (best-effort). The CPU-model requirement isn't checked here - verify it against Microsoft's list."
        $fwCap.Location = New-Object System.Drawing.Point(14, ($fy + 6))
        $fwCap.MaximumSize = New-Object System.Drawing.Size(580, 0)
        $fwCap.AutoSize = $true
        $fwCap.ForeColor = [System.Drawing.Color]::Gray
        $tabFw.Controls.Add($fwCap)
        [void]$tabs.TabPages.Add($tabFw)
    }
```

- [ ] **Step 4: Run the GUI smoke to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: `GUI smoke: all passed`, exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/GuiSmoke.ps1
git commit -m "Firmware & Security: Overview line + WinForms tab + GUI smoke (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: README + full verification + off-screen render check

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the README bullet**

In `README.md`, under `## What it shows`, insert after the **Storage** bullet (line ~14, before the *Notes / Bottlenecks* bullet):

```markdown
- **Firmware & Security** — BIOS version/date, UEFI vs. Legacy, **Secure Boot** on/off, and **TPM** presence/version, rolled up into a **Windows 11 readiness** checklist. All read without admin (best-effort); the CPU-model requirement points you to Microsoft's supported-CPU list rather than guessing it.
```

- [ ] **Step 2: Off-screen PNG render check (visual confirmation; not committed)**

Write this to the scratchpad and run it under Windows PowerShell (STA) to eyeball the tab layout (8-row Overview + the new tab). Confirm no clipping/overlap and the readiness checklist is readable.

```powershell
# scratchpad\fw_render.ps1
$env:SYSTEMINFO_NOMAIN = '1'
. "D:\stongate\system_info\Show-SystemInfo.ps1"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$fw = New-FirmwareReport -Raw ([pscustomobject]@{ BiosVendor='Dell Inc.'; BiosVersion='1.33.1'; BiosDate=[datetime]'2024-11-17'; IsUefi=$true; SecureBootRaw=1; TpmName='Trusted Platform Module 2.0'; OsBuild=26200; RamBytes=17179869184; SysDriveBytes=1024209543168; AddressWidth=64 })
$mods = @([pscustomobject]@{ Slot='A'; CapacityBytes=8GB; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='X'; TypeCode=26 })
$cpu = New-CpuReport -Name 'Intel(R) Core(TM) i7-10750H CPU @ 2.60GHz' -Cores 6 -Threads 12 -MaxClockMHz 2600 -L2CacheKB 1536 -L3CacheKB 12288 -Socket 'U3E1' -AddressWidth 64 -VirtualizationEnabled $true -MemoryType 'DDR4'
$mem = New-MemoryReport -Modules $mods -MaxCapacityBytes 64GB -TotalSlots 2 -BoardMaker 'Dell' -BoardModel 'X' -BoardVersion 'A00'
$st = New-StorageReport -Disks @([pscustomobject]@{ Name='NVMe KINGSTON'; MediaType='SSD'; BusType='RAID'; SizeBytes=1024209543168; Health='Healthy'; IsBoot=$true }) -Volumes @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=1000000000000; FreeBytes=400000000000 })
$report = New-SystemReport -Cpu $cpu -Memory $mem -Storage $st -Firmware $fw
$form = New-SystemForm $report
$form.StartPosition = 'Manual'; $form.Location = New-Object System.Drawing.Point(-2000, -2000)
$form.Show(); [System.Windows.Forms.Application]::DoEvents()
$tc = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
$tc.SelectedTab = $tc.TabPages | Where-Object { $_.Text -eq 'Firmware & Security' } | Select-Object -First 1
[System.Windows.Forms.Application]::DoEvents()
$bmp = New-Object System.Drawing.Bitmap $form.Width, $form.Height
$form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle 0, 0, $form.Width, $form.Height))
$out = "$env:TEMP\fw_tab.png"; $bmp.Save($out); $form.Close()
Write-Host "Saved $out"
```

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <scratchpad>\fw_render.ps1`, then read the PNG. Also render the **Overview** tab (set `$tc.SelectedTab` to Overview) to confirm the 8-row header + Notes box aren't clipped.

- [ ] **Step 3: Full verification of both suites**

Run: `pwsh -NoProfile -File tests/SystemInfo.Tests.ps1`
Expected: `<N> passed, 0 failed` (N = 352 + the new firmware assertions), exits 0.

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: `GUI smoke: all passed`, exits 0.

Run: `powershell.exe -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console`
Expected: the real `Firmware & Security` section renders correctly on this machine (BIOS 1.33.1, UEFI, Secure Boot On, TPM 2.0, "running Windows 11").

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Firmware & Security: README bullet (slice J)" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Definition of Done

- `New-FirmwareReport`, `Get-FirmwareInsights`, `Get-FirmwareInfo` added, following the collector→builder→insights→wiring→renderers pattern.
- `-Firmware` wired through `Get-SystemInsights`, `New-SystemReport`, `Invoke-SystemInfo`; **no change** to `New-UpgradeReport`.
- Console section, Overview `Security:` row, and `Firmware & Security` tab render; 11 tabs (8 on a no-battery/net desktop).
- Honesty preserved: TPM version + firmware type labelled best-effort; CPU-model requirement always `unknown`; three `info` notes only; no roll-up note; no BIOS-age judgment; nothing fabricated.
- Both suites green; real `-Console` verified on this machine.

## Spec-coverage self-check (fill during implementation)

- BIOS/UEFI/Secure Boot/TPM facts → Task 1 (`New-FirmwareReport`) + Task 5 (`Get-FirmwareInfo`). ✅
- Win11 readiness checklist + adaptive summary, CPU always `unknown` → Task 1. ✅
- Three atomic info notes, no roll-up → Task 2. ✅
- Wiring (`-Firmware`) → Task 3, Task 5. ✅
- Console section → Task 4. Tab + Overview line → Task 6. ✅
- 11/8 tab counts, GUI smoke → Task 6. README → Task 7. ✅
- Graceful null (null `-Raw`, null section) → Task 1 (`fw null*` tests), Task 4 (`fw console absent`). ✅
