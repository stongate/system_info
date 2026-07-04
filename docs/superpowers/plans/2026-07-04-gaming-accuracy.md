# Gaming Accuracy (slice K) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Gaming verdict honest for laptop GPUs (name-declared −1 tier), add a CPU-core limiter + note, render the missing Storage line, use "60 Hz-class" wording, and patch tier-table gaps (RTX 4050).

**Architecture:** All changes are pure-function edits inside `Show-SystemInfo.ps1` (`Get-GpuGamingTier`, `New-GamingReport`, `Get-GamingInsights`) plus the two Gaming renderers (console section, WinForms tab). No new collector, no `Invoke-SystemInfo`/`New-SystemReport` wiring changes, no new tab. Spec: `docs/superpowers/specs/2026-07-04-gaming-accuracy-design.md`.

**Tech Stack:** PowerShell 5.1-compatible script; hand-rolled test harness in `tests/SystemInfo.Tests.ps1` (`It`/`Assert-Equal`/`HasNote` helpers, plain functions, no Pester); WinForms smoke in `tests/GuiSmoke.ps1` (`Check` helper, synthetic fixtures).

**Test idiom notes for the implementer (read first):**
- Unit suite: `It 'name' { Assert-Equal <expected> <actual> 'label' }`. `Assert-Equal` compares **stringified** values. `HasNote $notes 'substring'` regex-escapes the substring.
- Existing shared fixtures used below: `$cpuDev` (8C/16T i7-10875H, [tests/SystemInfo.Tests.ps1:33](tests/SystemInfo.Tests.ps1)), `$memDual` (16 GB dual-channel, line 160), and the Gaming-block fixtures at lines 622–645 (`$gGpu` Max-Q 2060 + UHD@60Hz, `$gStorage` NVMe boot, `$gm`, `$hiGpu`/`$hiGm` RTX 5080@144Hz, `$igGpu`/`$igGm` UHD-only).
- Run unit suite: `pwsh -File tests/SystemInfo.Tests.ps1` → prints per-test PASS/FAIL and a final count; expect **0 FAIL**.
- Run GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → expect "GUI smoke: all passed".
- **Seven existing assertions legitimately shift** under this slice (the Max-Q fixture's rank drops 3→2 by design). They are updated inside the tasks below — do not "fix" them any other way: unit lines 602, 630, 631, 651, 659, 665; GuiSmoke line 63.

---

### Task 1: `Get-GpuGamingTier` — laptop-variant detection, −1 adjustment, RTX 4050 row, rank-1 label, `MobileVariant`

**Files:**
- Modify: `Show-SystemInfo.ps1:310-349` (`Get-GpuGamingTier`)
- Modify: `Show-SystemInfo.ps1:361` (`New-GamingReport` fallback tier object — gains `MobileVariant`)
- Test: `tests/SystemInfo.Tests.ps1` (tier block at 598–612; Gaming-report assertions at 630–631, 651, 659, 665)

- [ ] **Step 1: Update + add tier tests (they must fail first)**

In `tests/SystemInfo.Tests.ps1`, **replace** line 602:

```powershell
It 'tier 2060'    { Assert-Equal 3 (Tier 'NVIDIA GeForce RTX 2060 with Max-Q Design') 'rtx 2060' }
```

with:

```powershell
It 'tier 2060 desktop' { Assert-Equal 3 (Tier 'NVIDIA GeForce RTX 2060') 'desktop rtx 2060 unchanged' }
It 'tier 2060 maxq'    { Assert-Equal 2 (Tier 'NVIDIA GeForce RTX 2060 with Max-Q Design') 'max-q tiers one below desktop' }
```

and **add** after the existing `It 'tier label'` line (612):

```powershell
It 'tier 4090 laptop' { Assert-Equal 4 (Tier 'NVIDIA GeForce RTX 4090 Laptop GPU') '4090 laptop = desktop 4070 Ti class' }
It 'tier 3080 laptop' { Assert-Equal 3 (Tier 'NVIDIA GeForce RTX 3080 Laptop GPU') '3080 laptop' }
It 'tier 6800m'       { Assert-Equal 3 (Tier 'AMD Radeon RX 6800M') 'amd M suffix' }
It 'tier 4050'        { Assert-Equal 2 (Tier 'NVIDIA GeForce RTX 4050 Laptop GPU') 'laptop-native 4050 exempt from -1' }
It 'tier 1650ti maxq' { Assert-Equal 1 (Tier 'NVIDIA GeForce GTX 1650 Ti with Max-Q Design') 'floor holds at 1' }
It 'tier maxq flag'   { Assert-Equal $true  ((Get-GpuGamingTier -Name 'NVIDIA GeForce RTX 2060 with Max-Q Design').MobileVariant) 'mobile flag set' }
It 'tier desk flag'   { Assert-Equal $false ((Get-GpuGamingTier -Name 'NVIDIA GeForce RTX 2060').MobileVariant) 'desktop not mobile' }
It 'tier rank1 label' { Assert-Equal 'esports / light 1080p' ((Get-GpuGamingTier -Name 'Intel(R) UHD Graphics').Label) 'rank-1 label drops integrated-class' }
```

- [ ] **Step 2: Update the six downstream assertions that shift with the Max-Q rank**

Still in `tests/SystemInfo.Tests.ps1` (the `$gm` fixture at line 628 uses the Max-Q name, so its rank drops 3→2 by design):

Line 630 — replace:
```powershell
It 'gaming rank'     { Assert-Equal 3 $gm.Rank 'rank 3' }
```
with:
```powershell
It 'gaming rank'     { Assert-Equal 2 $gm.Rank 'max-q adjusted rank 2' }
```

Line 631 — replace:
```powershell
It 'gaming verdict'  { Assert-Equal $true ([bool]($gm.Verdict -match '1080p high')) 'verdict label' }
```
with:
```powershell
It 'gaming verdict'  { Assert-Equal $true ([bool]($gm.Verdict -match '1080p mainstream')) 'adjusted verdict label' }
```

After line 645 (below the `$igGm` tests), **add a desktop-2060 fixture** (rank 3, 60 Hz display — it keeps the 60 Hz note testable now that `$gm` is rank 2, and later tasks reuse it):

```powershell
$gmDeskGpu = New-GpuReport -Gpus @([pscustomobject]@{ Name='NVIDIA GeForce RTX 2060'; Vendor='NVIDIA'; AdapterRamBytes=6442450944; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=1920; ResV=1080; ResRefresh=60 }) -Now ([datetime]'2026-07-01')
$gmDesk = New-GamingReport -Gpu $gmDeskGpu -Cpu $cpuDev -Memory $memDual -Storage $gStorage
It 'gaming desk rank' { Assert-Equal 3 $gmDesk.Rank 'desktop 2060 stays rank 3' }
```

Line 651 — the 60 Hz note is rank-gated (`Rank -ge 3`); `$gm` is now rank 2, so the note must **stop** firing for it and keep firing for `$gmDesk`. Replace:
```powershell
It 'game 60hz info'  { Assert-Equal $true (HasNote $giVram 'caps what you see') '60 Hz note' }
```
with:
```powershell
It 'game 60hz gated' { Assert-Equal $false (HasNote $giVram 'caps what you see') '60 Hz note gated off at rank 2' }
It 'game 60hz info'  { Assert-Equal $true (HasNote (Get-GamingInsights -Gaming $gmDesk) 'caps what you see') '60 Hz note fires at rank 3' }
```

Line 659 — replace:
```powershell
It 'report has gaming'  { Assert-Equal 3 $repGame.Gaming.Rank 'gaming section computed into report' }
```
with:
```powershell
It 'report has gaming'  { Assert-Equal 2 $repGame.Gaming.Rank 'gaming section computed into report (max-q adjusted)' }
```

Line 665 — replace:
```powershell
It 'console gaming verdict' { Assert-Equal $true ([bool]($conGame -match '1080p high')) 'verdict shown' }
```
with:
```powershell
It 'console gaming verdict' { Assert-Equal $true ([bool]($conGame -match '1080p mainstream')) 'adjusted verdict shown' }
```

- [ ] **Step 3: Run the suite to verify the new/updated tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: FAILs for `tier 2060 maxq` (got 3), `tier 4090 laptop` (got 5), `tier 3080 laptop` (got 4), `tier 6800m` (got $null — unmatched M suffix), `tier 4050` (got $null), `tier 1650ti maxq` (got 2), `tier maxq flag` / `tier desk flag` (no `MobileVariant` property → got empty), `tier rank1 label` (got the old "(integrated-class)" label), `gaming rank` (got 3), `gaming verdict` (Verdict still "1080p high…"), `game 60hz gated` (note still fires), `report has gaming` (got 3), `console gaming verdict`. Everything else PASSes.

- [ ] **Step 4: Implement the new `Get-GpuGamingTier`**

Replace the whole function (`Show-SystemInfo.ps1:310-349`) with:

```powershell
function Get-GpuGamingTier {
    # Coarse, best-effort gaming tier for a GPU name (generation-level; refreshed
    # from 2026 GPU hierarchies). Ordered highest-rank-first; first match wins.
    # Name-declared laptop variants ("Max-Q", "Laptop GPU", AMD's trailing M) are
    # tiered one rank below the desktop card of the same name (floor 1); rules
    # flagged exempt already describe laptop-native or bottom-tier parts. Returns
    # { Rank (5..1 or $null); Label; MobileVariant }. The precise value is the
    # limiters, not this bucket.
    param([string] $Name)
    $out = [pscustomobject]@{ Rank = $null; Label = 'Unrecognized'; MobileVariant = $false }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $out }
    # Name-declared mobile variant? (word-bounded: "Mobility" does not match)
    $mobile = ($Name -match 'Max-?Q|\bLaptop\b|\bMobile\b') -or ($Name -match 'RX\s*\d{3,4}M\b')
    $out.MobileVariant = $mobile
    # Normalize to the base SKU so the desktop row matches.
    $base = $Name -replace 'with\s+Max-?Q\s+Design', '' -replace 'Max-?Q', '' `
                  -replace 'Laptop\s+GPU', '' -replace '\bLaptop\b', '' -replace '\bMobile\b', ''
    $base = $base -replace '(RX\s*\d{3,4})M\b', '$1'
    $rules = @(
        @{ r = 'RTX\s*(5090|5080|4090|4080)\b'; k = 5 }
        @{ r = 'RX\s*(9070\s*XT|7900\s*XTX)'; k = 5 }
        @{ r = 'RTX\s*(5070|4070|3090|3080)\b'; k = 4 }
        @{ r = 'RX\s*(9070|7900|7800|6900|6800)\b'; k = 4 }
        @{ r = 'RTX\s*(5060|4060|3070|3060|2080|2070|2060)\b'; k = 3 }
        @{ r = 'RX\s*(9060|7700|7600|6750|6700|6650|6600)\b'; k = 3 }
        @{ r = 'Arc\s*(B580|A770|A750)\b'; k = 3 }
        @{ r = 'RTX\s*4050\b'; k = 2; exempt = $true }   # laptop-only SKU; rank already reflects it
        @{ r = 'RTX\s*(5050|3050)\b'; k = 2 }
        @{ r = 'GTX\s*(1660|1650|1080|1070|1060)\b'; k = 2 }
        @{ r = 'RX\s*(5700|5600|590|580)\b'; k = 2 }
        @{ r = 'Arc\s*(B570|A580|A380)\b'; k = 2 }
        @{ r = 'GTX\s*(1050|1030)\b|\bMX\d'; k = 1; exempt = $true }
        @{ r = 'RX\s*(570|560|550)\b|Vega'; k = 1 }
        @{ r = 'Iris|UHD|HD\s*Graphics|Radeon.*Graphics'; k = 1; exempt = $true }
    )
    $labels = @{
        5 = '4K ultra / max settings'
        4 = '1440p ultra / entry 4K'
        3 = '1080p high / 1440p mainstream'
        2 = '1080p mainstream / esports'
        1 = 'esports / light 1080p'
    }
    foreach ($rule in $rules) {
        if ($base -match $rule.r) {
            $k = $rule.k
            if ($mobile -and -not $rule.exempt) { $k = [Math]::Max(1, $k - 1) }
            $out.Rank = $k
            $out.Label = $labels[$k]
            return $out
        }
    }
    return $out
}
```

Then in `New-GamingReport`, update the no-GPU fallback tier object at line 361 — replace:

```powershell
    $tier       = if ($gamingGpu) { Get-GpuGamingTier -Name $gamingGpu.Name } else { [pscustomobject]@{ Rank = $null; Label = 'Unrecognized' } }
```

with:

```powershell
    $tier       = if ($gamingGpu) { Get-GpuGamingTier -Name $gamingGpu.Name } else { [pscustomobject]@{ Rank = $null; Label = 'Unrecognized'; MobileVariant = $false } }
```

- [ ] **Step 5: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (399 passing: 388 base − 2 replaced + 13 added; the printed count is guidance — 0 FAIL is the gate).

- [ ] **Step 6: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Gaming accuracy: laptop-variant GPU tiers + RTX 4050 row (slice K)"
```

---

### Task 2: `New-GamingReport` — CPU-core limiter, 60 Hz-class wording, `MobileVariant` passthrough

**Files:**
- Modify: `Show-SystemInfo.ps1:375-398` (`New-GamingReport` limiters + output object)
- Test: `tests/SystemInfo.Tests.ps1` (add after the `$gmDesk` block from Task 1)

- [ ] **Step 1: Write the failing tests**

Add after the `It 'gaming desk rank'` line (Task 1 placed it below the `$igGm` tests):

```powershell
$cpu4 = New-CpuReport -Name 'Intel(R) Core(TM) i5-7400 CPU @ 3.00GHz' -Cores 4 -Threads 4 -AddressWidth 64 -MemoryType 'DDR4'
$cpu6 = New-CpuReport -Name 'Intel(R) Core(TM) i5-9400F CPU @ 2.90GHz' -Cores 6 -Threads 6 -AddressWidth 64 -MemoryType 'DDR4'
$gm4 = New-GamingReport -Gpu $gmDeskGpu -Cpu $cpu4 -Memory $memDual -Storage $gStorage
It 'gaming 4core lim'  { Assert-Equal $true  ($gm4.Limiters -contains '4-core CPU') '4-core limiter fires' }
$gm6 = New-GamingReport -Gpu $gmDeskGpu -Cpu $cpu6 -Memory $memDual -Storage $gStorage
It 'gaming 6core none' { Assert-Equal $false ([bool](($gm6.Limiters -join ',') -match 'core CPU')) '6 cores clean (boundary)' }
$g59Gpu = New-GpuReport -Gpus @([pscustomobject]@{ Name='NVIDIA GeForce RTX 2060'; Vendor='NVIDIA'; AdapterRamBytes=6442450944; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=1920; ResV=1200; ResRefresh=59 }) -Now ([datetime]'2026-07-01')
$gm59 = New-GamingReport -Gpu $g59Gpu -Cpu $cpuDev -Memory $memDual -Storage $gStorage
It 'gaming 59 wording' { Assert-Equal $true ($gm59.Limiters -contains '60 Hz-class display') '59 reported -> 60 Hz-class' }
It 'gaming 60 wording' { Assert-Equal $true ($gmDesk.Limiters -contains '60 Hz-class display') '60 measured -> 60 Hz-class' }
It 'gaming mv pass'    { Assert-Equal $true  $gm.MobileVariant 'max-q flag on report' }
It 'gaming mv desk'    { Assert-Equal $false $gmDesk.MobileVariant 'desktop flag off' }
It 'gaming verdict plain' { Assert-Equal '1080p mainstream / esports' $gm.Verdict 'Verdict carries no qualifier (renderers append it)' }
```

(`$hiGm` at 144 Hz already asserts zero limiters at line 640 — that covers "no display limiter above 60".)

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: FAILs for `gaming 4core lim` (no CPU limiter exists), `gaming 59 wording` / `gaming 60 wording` (old text "59 Hz display" / "60 Hz display"), `gaming mv pass` / `gaming mv desk` (no `MobileVariant` on the report). `gaming 6core none` and `gaming verdict plain` PASS trivially (nothing fires yet / Verdict is already plain) — that's fine; they pin the boundary and the invariant. Everything else PASSes.

- [ ] **Step 3: Implement the limiter + output changes**

In `New-GamingReport` (`Show-SystemInfo.ps1`), replace the limiter block (lines 375-381):

```powershell
    $limiters = @()
    if (-not $isDiscrete) { $limiters += 'no discrete GPU' }
    elseif ($null -ne $vram -and [double]$vram -lt 8) { $limiters += "$vram GB VRAM" }
    if ($null -ne $cores -and [int]$cores -le 4) { $limiters += "$cores-core CPU" }
    if ($null -ne $ramGB -and [double]$ramGB -lt 16) { $limiters += "$ramGB GB RAM" }
    if (-not $dual) { $limiters += 'single-channel RAM' }
    if ($null -ne $refresh -and [int]$refresh -le 60) {
        # 59 is Windows' rounding of a 59.94 Hz mode - "60 Hz-class" is the honest read.
        $limiters += $(if ([int]$refresh -eq 59 -or [int]$refresh -eq 60) { '60 Hz-class display' } else { "$refresh Hz display" })
    }
    if ($bootKind -eq 'HDD') { $limiters += 'HDD boot drive' }
```

and add `MobileVariant` to the output object (after the `TierLabel` line at 386):

```powershell
        TierLabel   = $tier.Label
        MobileVariant = [bool]$tier.MobileVariant
```

- [ ] **Step 4: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (406 passing). Note: existing `gaming hz lim` (line 634) still passes — "60 Hz-class display" matches its `'Hz'` regex.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Gaming accuracy: CPU-core limiter + 60 Hz-class wording (slice K)"
```

---

### Task 3: `Get-GamingInsights` — low-core note (rank-gated)

**Files:**
- Modify: `Show-SystemInfo.ps1:1113-1128` (`Get-GamingInsights`)
- Test: `tests/SystemInfo.Tests.ps1` (add after the Task 2 fixtures)

- [ ] **Step 1: Write the failing tests**

Add after Task 2's tests (fixtures `$gm4` = 4 cores + rank-3 desktop 2060, `$gGpu` = Max-Q rank 2 from Task 1):

```powershell
$gi4 = Get-GamingInsights -Gaming $gm4
It 'game core note'   { Assert-Equal $true (HasNote $gi4 'want 6+ CPU cores') 'low-core note fires at rank 3' }
It 'game core kind'   { Assert-Equal 'info' (@($gi4 | Where-Object { $_.Text -match 'CPU cores' })[0].Kind) 'low-core note is info' }
$gm4Lo = New-GamingReport -Gpu $gGpu -Cpu $cpu4 -Memory $memDual -Storage $gStorage
It 'game core gated'  { Assert-Equal $false (HasNote (Get-GamingInsights -Gaming $gm4Lo) 'want 6+ CPU cores') 'gated off at rank 2' }
It 'game core 8c off' { Assert-Equal $false (HasNote (Get-GamingInsights -Gaming $gmDesk) 'want 6+ CPU cores') '8 cores silent' }
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: FAILs for `game core note` (no such note exists) and `game core kind` (index into empty array throws → caught by `It`, reported FAIL). `game core gated` / `game core 8c off` PASS trivially — they pin the gates. Everything else PASSes.

- [ ] **Step 3: Implement the note**

In `Get-GamingInsights` (`Show-SystemInfo.ps1`), insert before the `return , @($notes)` line (1127):

```powershell
    if ($null -ne $Gaming.Cores -and [int]$Gaming.Cores -le 4 -and $null -ne $Gaming.Rank -and [int]$Gaming.Rank -ge 3) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "Modern AAA games increasingly want 6+ CPU cores; a $($Gaming.Cores)-core CPU may cap frame rates even where the GPU has headroom." }
    }
```

- [ ] **Step 4: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (410 passing).

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Gaming accuracy: low-core gaming note, rank-gated (slice K)"
```

---

### Task 4: Console renderer — Storage line, laptop qualifier, caption sentence

**Files:**
- Modify: `Show-SystemInfo.ps1:1690-1705` (Gaming block in `Write-SystemConsole`)
- Test: `tests/SystemInfo.Tests.ps1` (console block at 662–666)

- [ ] **Step 1: Write the failing tests**

Add after line 666 (`console mem footnote`; `$conGame` is built from `$repGame`, whose GPU is the Max-Q 2060 and whose storage is NVMe boot):

```powershell
It 'console gaming laptop' { Assert-Equal $true ([bool]($conGame -match '\(laptop GPU\)')) 'laptop qualifier on Overall' }
It 'console gaming storage' { Assert-Equal $true ([bool]($conGame -match 'NVMe SSD boot drive')) 'Storage line rendered' }
It 'console gaming caption' { Assert-Equal $true ([bool]($conGame -match 'one rank below')) 'laptop tier rule in caption' }
$repGameNoSt = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gGpu
It 'console gaming st unk'  { Assert-Equal $true ([bool]((Write-SystemConsole $repGameNoSt | Out-String) -match 'Storage\s+: Unknown')) 'Storage Unknown fallback' }
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: the four new tests FAIL (no qualifier, no Storage line, no caption sentence). Everything else PASSes.

- [ ] **Step 3: Implement the console changes**

Replace the Gaming block in `Write-SystemConsole` (`Show-SystemInfo.ps1:1690-1705`) with:

```powershell
    if ($Report.Gaming) {
        $gm = $Report.Gaming
        $lim = if (@($gm.Limiters).Count -gt 0) { ($gm.Limiters -join ', ') } else { 'none - well balanced' }
        $dispStr = if ($null -ne $gm.RefreshHz) { "$($gm.DisplayW)x$($gm.DisplayH) @ $($gm.RefreshHz) Hz" } else { 'Unknown' }
        $overall = $gm.Verdict + $(if ($gm.MobileVariant -and $null -ne $gm.Rank) { ' (laptop GPU)' } else { '' })
        '  Gaming'
        '  ------'
        '  Overall          : {0}' -f $overall
        '  Limited by       : {0}' -f $lim
        '  GPU              : {0}' -f $(if ($gm.GpuName) { $gm.GpuName } else { 'Unknown' })
        '  VRAM             : {0}' -f $(if ($null -ne $gm.VramGB) { "$($gm.VramGB) GB" } else { 'Unknown' })
        '  CPU              : {0}' -f $(if ($null -ne $gm.Cores) { "$($gm.Cores) cores" } else { 'Unknown' })
        '  Memory           : {0}' -f $(if ($null -ne $gm.RamGB) { "$($gm.RamGB) GB $(if ($gm.DualChannel) { 'dual-channel' } else { 'single-channel' })" } else { 'Unknown' })
        '  Display          : {0}' -f $dispStr
        '  Storage          : {0}' -f $(if ($gm.BootKind) { "$($gm.BootKind) boot drive" } else { 'Unknown' })
        '  (tiering is approximate / generation-level; laptop GPU variants'
        '   - "Max-Q", "Laptop" - are tiered one rank below the desktop card of the same name)'
        ''
    }
```

(This keeps every existing line; the changes are the `$overall` composition, the new `Storage` line after `Display`, and the two-line caption replacing the old single-line one. Note the trailing `''` blank line is preserved.)

- [ ] **Step 4: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (414 passing). `console gaming verdict` (line 665) still passes — the qualifier appends after the label.

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Gaming accuracy: console Storage line + laptop qualifier + caption (slice K)"
```

---

### Task 5: GUI tab — Storage row, laptop qualifier, caption; GuiSmoke updates

**Files:**
- Modify: `Show-SystemInfo.ps1:2060-2085` (Gaming tab in `New-SystemForm`)
- Modify: `tests/GuiSmoke.ps1:63` (+ 4 new checks after it)

The GUI has no unit tests (WinForms) — GuiSmoke is its test. GuiSmoke's fixtures already exercise everything: its GPU fixture is the Max-Q 2060 (`tests/GuiSmoke.ps1:22`) with a 59 Hz display (line 23) and an NVMe-RAID boot disk (line 26).

- [ ] **Step 1: Update GuiSmoke so it fails first**

Replace `tests/GuiSmoke.ps1:63`:

```powershell
    Check ([bool]($gameText -match '1080p high')) 'Gaming tab shows the tier'
```

with:

```powershell
    Check ([bool]($gameText -match '1080p mainstream'))    'Gaming tab shows the (laptop-adjusted) tier'
    Check ([bool]($gameText -match '\(laptop GPU\)'))      'Gaming tab shows the laptop-variant qualifier'
    Check ([bool]($gameText -match 'Storage:'))            'Gaming tab has a Storage line'
    Check ([bool]($gameText -match 'NVMe SSD boot drive')) 'Gaming tab shows the boot drive kind'
    Check ([bool]($gameText -match 'one rank below'))      'Gaming tab caption states the laptop tier rule'
```

- [ ] **Step 2: Run GuiSmoke to verify the new checks fail**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: FAILs for the qualifier, Storage line, boot-drive kind, and caption checks ('1080p mainstream' already passes — Task 1 changed the report). Exit code 1.

- [ ] **Step 3: Implement the GUI tab changes**

Replace the Gaming tab block in `New-SystemForm` (`Show-SystemInfo.ps1:2060-2085`) with:

```powershell
    # --- Gaming tab (synthesis; present whenever a GPU was assessed) ---
    if ($null -ne $Report.Gaming) {
        $gm = $Report.Gaming
        $tabGame = New-Object System.Windows.Forms.TabPage
        $tabGame.Text = 'Gaming'
        $lim = if (@($gm.Limiters).Count -gt 0) { ($gm.Limiters -join ', ') } else { 'none - well balanced' }
        $disp = if ($null -ne $gm.RefreshHz) { "$($gm.DisplayW)x$($gm.DisplayH) @ $($gm.RefreshHz) Hz" } else { 'Unknown' }
        $gOverall = $gm.Verdict + $(if ($gm.MobileVariant -and $null -ne $gm.Rank) { ' (laptop GPU)' } else { '' })
        $gKeys = @('Overall:', 'Limited by:', 'GPU:', 'VRAM:', 'CPU:', 'Memory:', 'Display:', 'Storage:')
        $gVals = @(
            $gOverall
            $lim
            $(if ($gm.GpuName) { $gm.GpuName } else { 'Unknown' })
            $(if ($null -ne $gm.VramGB) { "$($gm.VramGB) GB" } else { 'Unknown' })
            $(if ($null -ne $gm.Cores) { "$($gm.Cores) cores" } else { 'Unknown' })
            $(if ($null -ne $gm.RamGB) { "$($gm.RamGB) GB $(if ($gm.DualChannel) { 'dual-channel' } else { 'single-channel' })" } else { 'Unknown' })
            $disp
            $(if ($gm.BootKind) { "$($gm.BootKind) boot drive" } else { 'Unknown' })
        )
        $gy = Add-KvBlock -Parent $tabGame -Keys $gKeys -Values $gVals -KeyW 110 -ValW 440
        $gCap = New-Object System.Windows.Forms.Label
        $gCap.Text = "Gaming tiering is approximate / generation-level, not a benchmark.`r`nLaptop GPU variants (`"Max-Q`", `"Laptop`") are tiered one rank below the desktop card of the same name."
        $gCap.Location = New-Object System.Drawing.Point(14, ($gy + 6))
        $gCap.AutoSize = $true
        $gCap.ForeColor = [System.Drawing.Color]::Gray
        $tabGame.Controls.Add($gCap)
        [void]$tabs.TabPages.Add($tabGame)
    }
```

(The Overview `Gaming:` line at `Show-SystemInfo.ps1:1841-1844` is deliberately untouched — it shows the plain adjusted `Verdict` + limiters, per spec.)

- [ ] **Step 4: Run both suites to verify everything passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: "GUI smoke: all passed" (55 checks: 51 − 1 replaced + 5 new), exit 0.
Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (414 passing — unchanged by this task).

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/GuiSmoke.ps1
git commit -m "Gaming accuracy: GUI Storage row + laptop qualifier + caption; smoke updates (slice K)"
```

---

### Task 6: End-to-end verification on real hardware

**Files:** none modified (verification only)

- [ ] **Step 1: Run the full unit suite and GUI smoke one more time**

Run: `pwsh -File tests/SystemInfo.Tests.ps1` → 0 FAIL.
Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → all passed, exit 0.

- [ ] **Step 2: Run the real console mode and check the Gaming section against the spec's reference data**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Show-SystemInfo.ps1 -Console`

Expected Gaming section on this machine (Dell XPS 17 9700 — RTX 2060 Max-Q, 8C, 16 GB dual, 1920×1200@59, NVMe boot):

```
  Gaming
  ------
  Overall          : 1080p mainstream / esports (laptop GPU)
  Limited by       : 6 GB VRAM, 60 Hz-class display
  GPU              : NVIDIA GeForce RTX 2060 with Max-Q Design
  VRAM             : 6 GB
  CPU              : 8 cores
  Memory           : 16 GB dual-channel
  Display          : 1920x1200 @ 59 Hz
  Storage          : NVMe SSD boot drive
  (tiering is approximate / generation-level; laptop GPU variants
   - "Max-Q", "Laptop" - are tiered one rank below the desktop card of the same name)
```

And in Notes: the 6-GB-VRAM note **fires**; the "caps what you see" 60 Hz note **does not** (rank 2 gate); no CPU-core note (8 cores). If any of these differ, stop and investigate before proceeding.

- [ ] **Step 3: Report done**

No commit (nothing changed). The branch is ready for the finishing flow (verify → fast-forward merge to `main` → push), which the session drives via superpowers:finishing-a-development-branch.
