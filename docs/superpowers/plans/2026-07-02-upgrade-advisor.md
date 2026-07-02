# Upgrade Advisor (slice I) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an **Upgrade** tab (and console section) that synthesizes the tool's already-collected subsystem facts into one ranked upgrade action plan — Free fixes first, then Hardware, each with a coarse impact tag.

**Architecture:** One new pure function `New-UpgradeReport` applies a 9-rule catalog to the section objects and returns pre-ranked `{ Group; Action; Detail; Impact }` recommendations. It is composed inside `New-SystemReport` exactly like `New-GamingReport`, emits **no** notes (it does not feed `Get-SystemInsights`), and is rendered by the console renderer and a new WinForms tab. No new collector; `Invoke-SystemInfo` is untouched.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7 (the one script runs under both), WinForms (System.Windows.Forms), the repo's zero-dependency test harness.

---

## Background: conventions you must follow

- **Everything lives in one file:** `Show-SystemInfo.ps1`. Functions are dot-sourced before use, so definition order does not matter for calls.
- **Section objects are `[pscustomobject]`.** Notes are `[pscustomobject]@{ Kind='warn'|'info'|'ok'; Text='...' }`. The Upgrade Advisor does **not** produce notes — it produces recommendation objects `{ Group; Action; Detail; Impact }`.
- **Honesty:** every `Detail` string uses only values already measured on the section objects. No prices, no invented %/FPS, no product names.
- **Console strings use ASCII hyphen** `-` (not `—`), matching the existing renderer.
- **Unit tests** run with `pwsh -File tests\SystemInfo.Tests.ps1` (harness helpers: `It 'name' { ... }`, `Assert-Equal $expected $actual $label`, `HasNote $notes 'substr'`).
- **GUI smoke** runs with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\GuiSmoke.ps1` (needs Windows PowerShell 5.1 for WinForms/STA). It reads control text via `Get-AllText`, so exact widget geometry is not asserted.
- **`Sort-Object -Stable` is NOT available in Windows PowerShell 5.1**, so ranking uses an explicit `Order` tie-break index (below), never `-Stable`.

## File Structure

- **Modify** `Show-SystemInfo.ps1`:
  - Add `New-UpgradeReport` (pure) after `New-GamingReport` (after line 399).
  - Wire it into `New-SystemReport` (lines 1028-1042).
  - Add an `Upgrade Advisor` console section in `Write-SystemConsole` (before the Notes block, ~line 1455).
  - Add an `Upgrade` tab in `New-SystemForm` (after the Network tab block, before line 1858).
- **Modify** `tests/SystemInfo.Tests.ps1`: append an Upgrade Advisor test section before the summary (line 668).
- **Modify** `tests/GuiSmoke.ps1`: bump tab counts (9→10, 6→7), add Upgrade assertions.
- **Modify** `README.md`: one bullet describing the Upgrade Advisor.

---

## Task 1: `New-UpgradeReport` pure function

**Files:**
- Modify: `Show-SystemInfo.ps1` (insert after line 399, the closing `}` of `New-GamingReport`)
- Test: `tests/SystemInfo.Tests.ps1` (append before line 668)

- [ ] **Step 1: Write the failing tests**

Append this block to `tests/SystemInfo.Tests.ps1` immediately **before** the final summary line (`Write-Host "`n$script:Pass passed, $script:Fail failed`n"`, currently line 668). It reuses existing fixtures (`$cpuDev`, `$cpuVirtOn`, `$memDual`, `$memSingle`, `$gpu`, `$st`, `$stHdd`, `$stSata`, `$stLow`, `$batDev`, `$batSaverName`) defined earlier in the file.

```powershell
# =====================================================================
# Upgrade Advisor (slice I)
# =====================================================================

Write-Host "`nNew-UpgradeReport" -ForegroundColor Cyan
function UpHas($up, $action) { [bool](@($up.Recommendations) | Where-Object { $_.Action -match [regex]::Escape($action) }) }
function UpRec($up, $action) { @($up.Recommendations | Where-Object { $_.Action -match [regex]::Escape($action) })[0] }

# One rule per fixture (isolated so only the rule under test fires).
$upSsd = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Storage $stHdd
It 'up ssd action' { Assert-Equal $true (UpHas $upSsd 'Move Windows to an SSD') 'hdd -> ssd rec' }
It 'up ssd group'  { Assert-Equal 'Hardware' (UpRec $upSsd 'Move Windows to an SSD').Group 'ssd group' }
It 'up ssd impact' { Assert-Equal 'High' (UpRec $upSsd 'Move Windows to an SSD').Impact 'ssd impact' }

$upDual = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memSingle -Storage $st
It 'up dual action' { Assert-Equal $true (UpHas $upDual 'Add a matched RAM module') 'single -> dual rec' }
It 'up dual impact' { Assert-Equal 'High' (UpRec $upDual 'Add a matched RAM module').Impact 'dual impact' }

$upVirt = New-UpgradeReport -Cpu $cpuDev -Memory $memDual -Storage $st
It 'up virt action' { Assert-Equal $true (UpHas $upVirt 'Enable virtualization') 'virt off -> rec' }
It 'up virt group'  { Assert-Equal 'Free' (UpRec $upVirt 'Enable virtualization').Group 'virt group' }

$upSaver = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Battery $batSaverName
It 'up saver action' { Assert-Equal $true (UpHas $upSaver 'Power saver') 'saver -> rec' }
It 'up saver group'  { Assert-Equal 'Free' (UpRec $upSaver 'Power saver').Group 'saver group' }

$upSpace = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Storage $stLow
It 'up space action' { Assert-Equal $true (UpHas $upSpace 'Free up disk space') 'low space -> rec' }
It 'up space impact' { Assert-Equal 'Med' (UpRec $upSpace 'Free up disk space').Impact 'space impact' }

$upDrv = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Gpu $gpu
It 'up drv action' { Assert-Equal $true (UpHas $upDrv 'Update the GPU driver') 'old driver -> rec' }
It 'up drv impact' { Assert-Equal 'Low' (UpRec $upDrv 'Update the GPU driver').Impact 'driver impact' }

$upBat = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Battery $batDev
It 'up bat action' { Assert-Equal $true (UpHas $upBat 'Replace the worn battery') 'wear 45 -> rec' }
It 'up bat group'  { Assert-Equal 'Hardware' (UpRec $upBat 'Replace the worn battery').Group 'battery group' }

$upNvme = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Storage $stSata
It 'up nvme action' { Assert-Equal $true (UpHas $upNvme 'Consider an NVMe SSD') 'sata -> nvme rec' }
It 'up nvme impact' { Assert-Equal 'Low' (UpRec $upNvme 'Consider an NVMe SSD').Impact 'nvme impact' }

# XMP: running below what CPU (2933) and modules (3200) both support.
$memXmp = New-MemoryReport -Modules @(
    [pscustomobject]@{ Slot='A'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2133; VendorRaw='x'; PartNumber='y'; TypeCode=26 }
    [pscustomobject]@{ Slot='B'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2133; VendorRaw='x'; PartNumber='y'; TypeCode=26 }
) -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker x -BoardModel y
$upXmp = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memXmp
It 'up xmp action' { Assert-Equal $true (UpHas $upXmp 'Enable XMP') 'below supported -> xmp rec' }
It 'up xmp impact' { Assert-Equal 'Med' (UpRec $upXmp 'Enable XMP').Impact 'xmp impact' }

# Well-configured machine -> nothing fires.
$gpuFresh = New-GpuReport -Gpus @([pscustomobject]@{ Name='NVIDIA GeForce RTX 4090'; Vendor='NVIDIA'; AdapterRamBytes=25769803776; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=[datetime]'2026-05-01'; Availability=3; ResH=3840; ResV=2160; ResRefresh=144 }) -Now ([datetime]'2026-06-30')
$stGood  = New-StorageReport -Disks @([pscustomobject]@{ Name='NVMe X'; MediaType='SSD'; BusType='NVMe'; SizeBytes=1000204886016; Health='Healthy'; IsBoot=$true }) -Volumes @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=1000000000000; FreeBytes=500000000000 })
$batGood = New-BatteryReport -ChargePercent 100 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 100000 -FullChargeCapacityMWh 98000 -PowerPlan 'Balanced' -PowerPlanGuid '381b4222-f694-41f0-9685-ff5bb260df2e'
$upGood = New-UpgradeReport -Cpu $cpuVirtOn -Memory $memDual -Gpu $gpuFresh -Storage $stGood -Battery $batGood
It 'up good none'  { Assert-Equal $false $upGood.HasAny 'well-configured -> no recs' }
It 'up good count' { Assert-Equal 0 (@($upGood.Recommendations).Count) 'zero recs' }

# Ranking: Free before Hardware; High before Low within a group.
$upRank = New-UpgradeReport -Cpu $cpuDev -Memory $memSingle -Gpu $gpu -Storage $stHdd -Battery $batDev
It 'up rank first free'  { Assert-Equal 'Free' $upRank.Recommendations[0].Group 'free group ranked first' }
It 'up rank first med'   { Assert-Equal 'Med'  $upRank.Recommendations[0].Impact 'med before low in free' }
It 'up rank free count'  { Assert-Equal 2 $upRank.FreeCount 'two free (virt + driver)' }
$upFirstHw = @($upRank.Recommendations | Where-Object { $_.Group -eq 'Hardware' })[0]
It 'up rank hw high'     { Assert-Equal 'High' $upFirstHw.Impact 'hardware high ranked first' }
It 'up rank hw ssd'      { Assert-Equal $true ([bool]($upFirstHw.Action -match 'SSD')) 'SSD first among hardware' }
$upGrps = @($upRank.Recommendations | ForEach-Object { $_.Group })
It 'up rank grouping'    { Assert-Equal $true ([array]::IndexOf($upGrps,'Hardware') -gt [array]::LastIndexOf($upGrps,'Free')) 'all free before all hardware' }

# Null-safety: missing sections skip their rules, no error.
$upNull = New-UpgradeReport -Cpu $cpuDev -Memory $memDual -Gpu $null -Storage $null -Battery $null
It 'up null virt' { Assert-Equal $true  (UpHas $upNull 'virtualization') 'null sections -> virt rec only' }
It 'up null ssd'  { Assert-Equal $false (UpHas $upNull 'SSD') 'no storage -> no ssd rec' }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: the new `up *` tests FAIL (`New-UpgradeReport` is not recognized), and the run exits non-zero. Existing tests still PASS.

- [ ] **Step 3: Implement `New-UpgradeReport`**

Insert this function into `Show-SystemInfo.ps1` immediately after the closing `}` of `New-GamingReport` (after line 399, before `function Get-DiskKind`):

```powershell
function New-UpgradeReport {
    # Synthesize a ranked upgrade action plan from the already-built subsystem
    # sections (pure; no I/O). Free fixes first, then Hardware; High -> Med -> Low
    # within each group, construction order breaking ties. Emits NO notes - this is
    # presentation-only synthesis (it does not feed Get-SystemInsights). Each rule
    # guards its own section, so missing sections simply skip their rules.
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null, [object] $Battery = $null)

    $recs = @()

    # ---- Free fixes ----
    # XMP/EXPO: RAM running below what the CPU and the modules both support.
    if ($null -ne $Memory) {
        $run = if ($null -ne $Memory.RunningSpeed -and [int]$Memory.RunningSpeed -gt 0) { [int]$Memory.RunningSpeed } else { $null }
        $rated = @($Memory.RatedSpeeds | Where-Object { $_ -gt 0 })
        $ratedEff = if ($rated.Count -gt 0) { ($rated | Measure-Object -Minimum).Minimum } else { $null }
        $cap = if ($null -ne $Cpu -and $null -ne $Cpu.MaxMemSpeed -and [int]$Cpu.MaxMemSpeed -gt 0) { [int]$Cpu.MaxMemSpeed } else { $null }
        if ($null -ne $run -and $null -ne $ratedEff) {
            $target = $null
            if ($null -ne $cap) {
                if ($run -lt $cap -and $run -lt $ratedEff) { $target = [math]::Min($cap, $ratedEff) }
            } elseif ($run -lt $ratedEff) { $target = $ratedEff }
            if ($null -ne $target) {
                $recs += [pscustomobject]@{ Group = 'Free'; Action = 'Enable XMP/EXPO in BIOS'; Impact = 'Med'; Detail = "RAM runs at $run MT/s; the CPU and modules support up to $target - enabling XMP/EXPO could reach it." }
            }
        }
    }
    # Virtualization disabled in firmware.
    if ($null -ne $Cpu -and $Cpu.VirtualizationEnabled -eq $false) {
        $recs += [pscustomobject]@{ Group = 'Free'; Action = 'Enable virtualization (VT-x/AMD-V) in BIOS'; Impact = 'Med'; Detail = 'Virtualization appears disabled - needed for Hyper-V, WSL2, Docker or VMs (the firmware flag can be unreliable).' }
    }
    # Power saver plan active.
    if ($null -ne $Battery) {
        $guid = "$($Battery.PowerPlanGuid)".Trim()
        $plan = "$($Battery.PowerPlan)".Trim()
        if ($guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a' -or $plan -match 'saver') {
            $recs += [pscustomobject]@{ Group = 'Free'; Action = 'Switch off the Power saver plan'; Impact = 'Med'; Detail = "Active plan '$plan' caps CPU speed to save energy - switch to Balanced for full performance." }
        }
    }
    # Low free space (one rec per qualifying volume).
    if ($null -ne $Storage) {
        foreach ($v in $Storage.Volumes) {
            if ($null -ne $v.FreePercent -and ([double]$v.FreePercent -lt 10 -or [double]$v.FreeGB -lt 25)) {
                $recs += [pscustomobject]@{ Group = 'Free'; Action = "Free up disk space on $($v.DriveLetter):"; Impact = 'Med'; Detail = "$($v.DriveLetter): has $($v.FreeGB) GB free ($($v.FreePercent)%) - Windows slows when a drive is nearly full." }
            }
        }
    }
    # Old GPU driver (one rec per old GPU).
    if ($null -ne $Gpu) {
        foreach ($g in $Gpu.Gpus) {
            if ($null -ne $g.DriverAgeMonths -and [int]$g.DriverAgeMonths -gt 12) {
                $recs += [pscustomobject]@{ Group = 'Free'; Action = 'Update the GPU driver'; Impact = 'Low'; Detail = "$($g.Name) driver is ~$($g.DriverAgeMonths) months old." }
            }
        }
    }

    # ---- Hardware upgrades ----
    $boot = if ($null -ne $Storage) { @($Storage.Disks | Where-Object { $_.IsBoot }) | Select-Object -First 1 } else { $null }
    # HDD boot -> SSD.
    if ($null -ne $boot -and $boot.Kind -eq 'HDD') {
        $recs += [pscustomobject]@{ Group = 'Hardware'; Action = 'Move Windows to an SSD'; Impact = 'High'; Detail = "Boot drive $($boot.Name) is a mechanical HDD - the single biggest responsiveness upgrade." }
    }
    # Single-channel -> add a matched module.
    if ($null -ne $Memory -and [int]$Memory.PopulatedSlots -eq 1 -and [int]$Memory.TotalSlots -ge 2) {
        $recs += [pscustomobject]@{ Group = 'Hardware'; Action = 'Add a matched RAM module (dual-channel)'; Impact = 'High'; Detail = "Only 1 of $($Memory.TotalSlots) slots populated - a matched module enables dual-channel (up to ~2x memory bandwidth)." }
    }
    # Worn battery.
    if ($null -ne $Battery -and $null -ne $Battery.WearPercent -and [int]$Battery.WearPercent -ge 35) {
        $recs += [pscustomobject]@{ Group = 'Hardware'; Action = 'Replace the worn battery'; Impact = 'Med'; Detail = "Battery holds ~$($Battery.HealthPercent)% of design capacity ($($Battery.WearPercent)% lost)." }
    }
    # SATA SSD boot -> NVMe.
    if ($null -ne $boot -and $boot.Kind -eq 'SATA SSD') {
        $recs += [pscustomobject]@{ Group = 'Hardware'; Action = 'Consider an NVMe SSD'; Impact = 'Low'; Detail = 'Boot drive is a SATA SSD; an NVMe SSD is several times faster if you have an M.2 NVMe slot.' }
    }

    # ---- Rank: Free before Hardware; High -> Med -> Low; construction order ties.
    # (Explicit Order tie-break: Sort-Object -Stable is unavailable in PS 5.1.)
    $grpRank = @{ 'Free' = 0; 'Hardware' = 1 }
    $impRank = @{ 'High' = 0; 'Med' = 1; 'Low' = 2 }
    for ($k = 0; $k -lt $recs.Count; $k++) { $recs[$k] | Add-Member -NotePropertyName Order -NotePropertyValue $k -Force }
    $ranked = @($recs |
        Sort-Object @{ e = { $grpRank[[string]$_.Group] } }, @{ e = { $impRank[[string]$_.Impact] } }, @{ e = { $_.Order } } |
        ForEach-Object { [pscustomobject]@{ Group = $_.Group; Action = $_.Action; Detail = $_.Detail; Impact = $_.Impact } })

    [pscustomobject]@{
        Recommendations = $ranked
        FreeCount       = @($ranked | Where-Object { $_.Group -eq 'Free' }).Count
        HardwareCount   = @($ranked | Where-Object { $_.Group -eq 'Hardware' }).Count
        HasAny          = ($ranked.Count -gt 0)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: all `up *` tests PASS; existing tests unaffected; run exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Upgrade Advisor: New-UpgradeReport pure synthesis (slice I)"
```

---

## Task 2: Wire `New-UpgradeReport` into `New-SystemReport`

**Files:**
- Modify: `Show-SystemInfo.ps1:1025-1042` (`New-SystemReport`)
- Test: `tests/SystemInfo.Tests.ps1` (append after the Task 1 block)

- [ ] **Step 1: Write the failing tests**

Append after the Task 1 tests (still before the summary line):

```powershell
Write-Host "`nSystem report (Upgrade wiring)" -ForegroundColor Cyan
$repUp = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Battery $batDev
It 'report has upgrade'   { Assert-Equal $true $repUp.Upgrade.HasAny 'upgrade section computed into report' }
It 'report upgrade bat'   { Assert-Equal $true (UpHas $repUp.Upgrade 'Replace the worn battery') 'battery rec present in report' }
# The advisor must NOT inject its Action text into the notes (no duplication).
$repUpHdd = New-SystemReport -Cpu $cpuVirtOn -Memory $memDual -Storage $stHdd
It 'upgrade no notes'     { Assert-Equal $false (HasNote $repUpHdd.Insights 'Move Windows to an SSD') 'advisor emits no notes' }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: `report has upgrade` and `report upgrade bat` FAIL (`$repUp.Upgrade` is null). (`upgrade no notes` may already pass — that is fine.)

- [ ] **Step 3: Implement the wiring**

In `New-SystemReport`, after the `$gaming = ...` line (line 1029), add the upgrade computation:

```powershell
    # Gaming is a synthesis of the sections above (computed here, not passed in).
    $gaming = if ($null -ne $Gpu) { New-GamingReport -Gpu $Gpu -Cpu $Cpu -Memory $Memory -Storage $Storage } else { $null }
    # Upgrade Advisor is a synthesis too (computed here; emits no notes, so it is
    # NOT passed to Get-SystemInsights).
    $upgrade = New-UpgradeReport -Cpu $Cpu -Memory $Memory -Gpu $Gpu -Storage $Storage -Battery $Battery
```

Then add `Upgrade` to the returned object, right after the `Gaming = $gaming` line (line 1040):

```powershell
        Gaming    = $gaming
        Upgrade   = $upgrade
        Insights  = $insights
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: all Upgrade wiring tests PASS; full suite exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Upgrade Advisor: compose into New-SystemReport (slice I)"
```

---

## Task 3: Console `Upgrade Advisor` section

**Files:**
- Modify: `Show-SystemInfo.ps1` (`Write-SystemConsole`, insert before the Notes block at ~line 1455)
- Test: `tests/SystemInfo.Tests.ps1` (append after the Task 2 block)

- [ ] **Step 1: Write the failing tests**

Append after the Task 2 tests:

```powershell
Write-Host "`nWrite-SystemConsole (Upgrade Advisor)" -ForegroundColor Cyan
$conUp = (Write-SystemConsole $repUp | Out-String)
It 'console upgrade sect'  { Assert-Equal $true ([bool]($conUp -match 'Upgrade Advisor')) 'upgrade section present' }
It 'console upgrade hw'    { Assert-Equal $true ([bool]($conUp -match 'Hardware upgrades')) 'hardware group present' }
$repUpGood = New-SystemReport -Cpu $cpuVirtOn -Memory $memDual -Gpu $gpuFresh -Storage $stGood -Battery $batGood
$conUpGood = (Write-SystemConsole $repUpGood | Out-String)
It 'console upgrade empty' { Assert-Equal $true ([bool]($conUpGood -match 'No upgrades suggested')) 'empty-state line' }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: `console upgrade sect`, `console upgrade hw`, `console upgrade empty` FAIL (no such text yet).

- [ ] **Step 3: Implement the console section**

In `Write-SystemConsole`, insert this block **after** the Gaming section's closing `}` (line 1454) and **before** the `if (@($Report.Insights).Count -gt 0) {` Notes block (line 1455):

```powershell
    if ($Report.Upgrade) {
        $up = $Report.Upgrade
        '  Upgrade Advisor'
        '  ---------------'
        if ($up.HasAny) {
            $free = @($up.Recommendations | Where-Object { $_.Group -eq 'Free' })
            $hw   = @($up.Recommendations | Where-Object { $_.Group -eq 'Hardware' })
            if ($free.Count -gt 0) {
                '  Free fixes'
                foreach ($r in $free) { '    - {0} - {1} ({2})' -f $r.Action, $r.Detail, $r.Impact }
            }
            if ($hw.Count -gt 0) {
                '  Hardware upgrades'
                foreach ($r in $hw) { '    - {0} - {1} ({2})' -f $r.Action, $r.Detail, $r.Impact }
            }
        } else {
            '  No upgrades suggested - your system is well configured for its components.'
        }
        '  (from measured facts; impact is a coarse estimate, not a benchmark)'
        ''
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: the three console Upgrade tests PASS; full suite exits 0.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Upgrade Advisor: console section (slice I)"
```

---

## Task 4: `Upgrade` WinForms tab + GUI smoke updates

**Files:**
- Modify: `Show-SystemInfo.ps1` (`New-SystemForm`, insert after the Network tab block at line 1856, before `$form.Controls.Add($tabs)` at line 1858)
- Modify: `tests/GuiSmoke.ps1` (tab-count and Upgrade assertions)

- [ ] **Step 1: Update the GUI smoke test (the failing check)**

Make these four edits to `tests/GuiSmoke.ps1`:

1. Line 52 — bump the full-report tab count from 9 to 10:

```powershell
    Check ($tabControl.TabPages.Count -eq 10) 'ten tabs'
```

2. Line 54 — add `Upgrade` to the tab-name check (replace the whole `Check (...)` statement):

```powershell
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'GPU') -and ($tabNames -contains 'Memory') -and ($tabNames -contains 'Storage') -and ($tabNames -contains 'Gaming') -and ($tabNames -contains 'Battery') -and ($tabNames -contains 'Live') -and ($tabNames -contains 'Network') -and ($tabNames -contains 'Upgrade')) 'Overview/CPU/GPU/Memory/Storage/Gaming/Battery/Live/Network/Upgrade tabs'
```

3. After the Network block (after line 115, the `Check ([bool]($ovText -match 'Gaming:')) ...` line), add Upgrade tab checks:

```powershell
    $upgTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Upgrade' } | Select-Object -First 1
    Check ($null -ne $upgTab) 'has Upgrade tab'
    $upgText = (Get-AllText $upgTab) -join "`n"
    Check ([bool]($upgText -match 'Free fixes'))        'Upgrade tab shows Free fixes group'
    Check ([bool]($upgText -match 'Hardware upgrades'))  'Upgrade tab shows Hardware upgrades group'
    Check ([bool]($upgText -match 'coarse estimate'))    'Upgrade tab shows the honesty caption'
```

4. Lines 121-122 — the desktop (no-battery) case now has 7 tabs incl. Upgrade. Replace those two `Check` lines:

```powershell
    Check ($tc2.TabPages.Count -eq 7)          'desktop: seven tabs (Gaming + Upgrade present; no Battery/Live/Network)'
    Check ($names2 -contains 'Gaming')         'desktop: Gaming tab present'
    Check ($names2 -contains 'Upgrade')        'desktop: Upgrade tab present'
```

- [ ] **Step 2: Run the GUI smoke to verify it fails**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\GuiSmoke.ps1`
Expected: FAILs — `ten tabs` (still 9), `has Upgrade tab` (null), and the desktop `seven tabs` check — because the tab is not built yet.

- [ ] **Step 3: Implement the Upgrade tab**

In `New-SystemForm`, insert this block **after** the Network tab `if` block (after line 1856, the closing `}`) and **before** `$form.Controls.Add($tabs)` (line 1858):

```powershell
    # --- Upgrade tab (synthesis; always present - every machine can be assessed) ---
    if ($null -ne $Report.Upgrade) {
        $up = $Report.Upgrade
        $tabUpgrade = New-Object System.Windows.Forms.TabPage
        $tabUpgrade.Text = 'Upgrade'
        $tabUpgrade.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
        $uy = 10
        if ($up.HasAny) {
            foreach ($grp in @(
                    @{ Name = 'Free fixes'; Key = 'Free' },
                    @{ Name = 'Hardware upgrades'; Key = 'Hardware' })) {
                $items = @($up.Recommendations | Where-Object { $_.Group -eq $grp.Key })
                if ($items.Count -eq 0) { continue }
                $hdr = New-Object System.Windows.Forms.Label
                $hdr.Text = $grp.Name
                $hdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
                $hdr.Location = New-Object System.Drawing.Point(10, $uy)
                $hdr.AutoSize = $true
                $tabUpgrade.Controls.Add($hdr)
                $uy += 24
                $body = New-Object System.Windows.Forms.Label
                $body.Text = (@($items | ForEach-Object { "- $($_.Action) - $($_.Detail) ($($_.Impact))" }) -join "`r`n")
                $body.Location = New-Object System.Drawing.Point(20, $uy)
                $body.MaximumSize = New-Object System.Drawing.Size(560, 0)
                $body.AutoSize = $true
                $body.Anchor = 'Top,Left,Right'
                $tabUpgrade.Controls.Add($body)
                $uy += [Math]::Max($body.PreferredHeight, ($items.Count * 20)) + 14
            }
        } else {
            $none = New-Object System.Windows.Forms.Label
            $none.Text = 'No upgrades suggested - your system is well configured for its components.'
            $none.Location = New-Object System.Drawing.Point(10, $uy)
            $none.AutoSize = $true
            $tabUpgrade.Controls.Add($none)
            $uy += 28
        }
        $upCap = New-Object System.Windows.Forms.Label
        $upCap.Text = 'Recommendations come only from measured facts. Impact is a coarse estimate (High / Med / Low), not a benchmark.'
        $upCap.Location = New-Object System.Drawing.Point(10, ($uy + 6))
        $upCap.MaximumSize = New-Object System.Drawing.Size(580, 0)
        $upCap.AutoSize = $true
        $upCap.ForeColor = [System.Drawing.Color]::Gray
        $tabUpgrade.Controls.Add($upCap)
        [void]$tabs.TabPages.Add($tabUpgrade)
    }
```

- [ ] **Step 4: Run the GUI smoke to verify it passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\GuiSmoke.ps1`
Expected: `GUI smoke: all passed`, exit 0.

- [ ] **Step 5: Run the full unit suite too (guard against regressions)**

Run: `pwsh -File tests\SystemInfo.Tests.ps1`
Expected: all tests PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add Show-SystemInfo.ps1 tests/GuiSmoke.ps1
git commit -m "Upgrade Advisor: WinForms Upgrade tab + GUI smoke (slice I)"
```

---

## Task 5: README + final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add an Upgrade Advisor bullet**

In `README.md`, under the **What it shows** list, add a bullet after the "Notes / Bottlenecks" bullet (line 15):

```markdown
- **Upgrade Advisor** — turns the detected bottlenecks into a ranked *what-to-do-first* plan: free BIOS/driver/config fixes first (enable XMP, enable virtualization, update the GPU driver, free up disk space, switch off Power saver), then hardware upgrades (SSD, dual-channel RAM, replace a worn battery), each tagged with a coarse High/Med/Low impact. Pure synthesis of the data above — no invented prices, percentages, or product names.
```

- [ ] **Step 2: Run both test suites (final verification)**

Run:
```
pwsh -File tests\SystemInfo.Tests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\GuiSmoke.ps1
```
Expected: unit suite reports `N passed, 0 failed` and exits 0; GUI smoke reports `all passed` and exits 0.

- [ ] **Step 3: Optionally launch the app to eyeball the tab (manual)**

Run: `powershell.exe -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console`
Expected: an `Upgrade Advisor` section appears before `Notes`, grouped into Free fixes / Hardware upgrades (or the "No upgrades suggested" line). Capture the real dev-machine output and paste it into the spec's "Reference data" section if desired.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "Upgrade Advisor: README (slice I)"
```

---

## Self-review checklist (already applied)

- **Spec coverage:** all 9 catalog rules → Task 1 tests + function; ranking (Free-first, High→Low) → Task 1 ranking tests; empty-state → Task 1 `up good *` + console/GUI empty-state; wiring (no notes) → Task 2; console section → Task 3; always-present tab + `9→10`/`6→7` counts → Task 4; honesty caption → Task 4 GUI check.
- **No placeholders:** every code and test step is complete and runnable.
- **Type consistency:** the function returns `{ Recommendations=@({Group;Action;Detail;Impact}); FreeCount; HardwareCount; HasAny }`; every task and test references exactly those names, and `$Report.Upgrade` is used identically in console and GUI.
- **PS 5.1 safety:** ranking avoids `Sort-Object -Stable` via an explicit `Order` tie-break, so it is deterministic under both Windows PowerShell 5.1 (GUI) and PowerShell 7 (unit tests).
