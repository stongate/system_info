# Tab Consolidation (slice N) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate the WinForms window from 12 tabs to 10 — merge GPU+sensors+Gaming into `Graphics`, Battery+Live into `Power`, and rename `Firmware & Security` to `Security` — so the tab strip stops overflowing.

**Architecture:** Pure presentation change inside `New-SystemForm` in `Show-SystemInfo.ps1`, plus the `tests/GuiSmoke.ps1` structure test. No collector, builder, insight, report-object, or console-renderer change — so the pure-function unit suite is untouched (stays 457/0) and `-Console`/`-Benchmark` output is byte-identical. Spec: `docs/superpowers/specs/2026-07-06-tab-consolidation-design.md`.

**Tech Stack:** PowerShell 5.1-compatible WinForms; `tests/GuiSmoke.ps1` headless structure check (`Check` helper, off-screen `New-SystemForm`, synthetic fixtures) run under Windows PowerShell STA.

**Implementer notes (read first):**
- The GUI has **no unit tests** — `GuiSmoke.ps1` is its only test. There is no red/green unit cycle here; the discipline is: update the smoke expectations first (watch them fail), implement, watch them pass, then eyeball an off-screen PNG render.
- Commands:
  - GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → gate is the final line `GUI smoke: all passed` and exit 0.
  - Unit suite (regression only — must stay green): `pwsh -File tests/SystemInfo.Tests.ps1` → `457 passed, 0 failed`.
- `Add-KvBlock -Parent <ctrl> -Keys <string[]> -Values <string[]> -X <int> -Y <int> -KeyW <int> -ValW <int>` places a two-column label pair and **returns the next Y offset** (`$Y + Keys.Count*20 + 8`). Defaults: X=14, Y=14, KeyW=150, ValW=404.
- Line numbers below are from the current `main`/branch HEAD — verify with Read before editing; edits are exact-match.
- ASCII-only in `Show-SystemInfo.ps1` (no BOM; Windows PowerShell 5.1 mis-decodes non-ASCII). The degree sign is built at runtime as `$([char]176)`.

---

### Task 1: Graphics tab (merge GPU + live sensors + Gaming)

**Files:**
- Modify: `Show-SystemInfo.ps1` — replace the `# --- GPU tab ---` block (currently lines 2218-2274) with a new `# --- Graphics tab ---` block; **delete** the separate `# --- Gaming tab ---` block (currently lines 2386-2413).
- Modify: `tests/GuiSmoke.ps1` — retarget the GPU + Gaming checks to a single `Graphics` tab; drop the full count to 11 and desktop to 8.

- [ ] **Step 1: Update GuiSmoke expectations (they must fail first)**

In `tests/GuiSmoke.ps1`:

(a) Line 55 — replace:
```powershell
    Check ($tabControl.TabPages.Count -eq 12) 'twelve tabs'
```
with:
```powershell
    Check ($tabControl.TabPages.Count -eq 11) 'eleven tabs'
```

(b) Line 57 — replace the whole tab-names `Check` (the `-contains 'GPU'`/`'Gaming'` conjunction) with:
```powershell
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'Graphics') -and ($tabNames -contains 'Memory') -and ($tabNames -contains 'Storage') -and ($tabNames -contains 'Battery') -and ($tabNames -contains 'Live') -and ($tabNames -contains 'Benchmark') -and ($tabNames -contains 'Network') -and ($tabNames -contains 'Firmware & Security') -and ($tabNames -contains 'Upgrade')) 'Overview/CPU/Graphics/Memory/Storage/Battery/Live/Benchmark/Network/Firmware & Security/Upgrade tabs'
```

(c) Lines 61-69 (the `$gameTab = ... 'Gaming'` block) AND lines 88-94 (the `$gpuTab = ... 'GPU'` block) — replace **both blocks** with one consolidated Graphics block. Delete lines 88-94 entirely, and replace lines 61-69 with:
```powershell
    $gfxTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Graphics' } | Select-Object -First 1
    Check ($null -ne $gfxTab) 'has Graphics tab'
    $glv = $gfxTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $glv)         'Graphics tab has a GPU ListView'
    Check ($glv.Items.Count -eq 2) 'two GPU rows'
    $gfxText = (Get-AllText $gfxTab) -join "`n"
    Check ([bool]($gfxText -match 'Temperature'))          'Graphics tab shows the live sensor panel'
    Check ([bool]($gfxText -match 'nvidia-smi'))           'Graphics sensor panel labelled live'
    Check ([bool]($gfxText -match 'Overall'))              'Graphics tab shows the gaming verdict'
    Check ([bool]($gfxText -match '1080p mainstream'))     'Graphics tab shows the (laptop-adjusted) tier'
    Check ([bool]($gfxText -match '\(laptop GPU\)'))       'Graphics tab shows the laptop-variant qualifier'
    Check ([bool]($gfxText -match 'NVMe SSD boot drive'))  'Graphics tab shows the gaming Storage line'
    Check ([bool]($gfxText -match 'one rank below'))       'Graphics tab shows the laptop tier caption'
```

(d) Desktop fixture — line 150 replace:
```powershell
    Check ($tc2.TabPages.Count -eq 9)          'desktop: nine tabs (Gaming + Benchmark + Firmware & Security + Upgrade; no Battery/Live/Network)'
```
with:
```powershell
    Check ($tc2.TabPages.Count -eq 8)          'desktop: eight tabs (Graphics + Benchmark + Firmware & Security + Upgrade; no Battery/Live/Network)'
```
Line 152 replace:
```powershell
    Check ($names2 -contains 'Gaming')         'desktop: Gaming tab present'
```
with:
```powershell
    Check ($names2 -contains 'Graphics')       'desktop: Graphics tab present'
```
Lines 158-159 replace:
```powershell
    $gpu2 = $tc2.TabPages | Where-Object { $_.Text -eq 'GPU' } | Select-Object -First 1
    Check (-not ((Get-AllText $gpu2) -join "`n" -match 'nvidia-smi')) 'no-sensor: GPU tab has no sensor panel'
```
with:
```powershell
    $gfx2 = $tc2.TabPages | Where-Object { $_.Text -eq 'Graphics' } | Select-Object -First 1
    Check (-not ((Get-AllText $gfx2) -join "`n" -match 'nvidia-smi')) 'no-sensor: Graphics tab has no sensor panel'
```

- [ ] **Step 2: Run GuiSmoke to verify the new checks fail**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: FAILs — `eleven tabs` (still 12), the tab-names check (no `Graphics` tab yet, `GPU`/`Gaming` still exist), `has Graphics tab` and every `Graphics tab ...` check (no such tab), `desktop: eight tabs` (still 9), `desktop: Graphics tab present`. Exit 1.

- [ ] **Step 3: Replace the GPU tab block with the Graphics block**

In `Show-SystemInfo.ps1`, replace the entire `# --- GPU tab ---` block (from the comment through its `[void]$tabs.TabPages.Add($tabGpu)` line) with:

```powershell
    # --- Graphics tab (GPU adapters + live sensors + gaming verdict) ---
    $tabGraphics = New-Object System.Windows.Forms.TabPage
    $tabGraphics.Text = 'Graphics'
    $tabGraphics.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
    $tabGraphics.AutoScroll = $true
    $glist = New-Object System.Windows.Forms.ListView
    $glist.View = 'Details'; $glist.FullRowSelect = $true; $glist.GridLines = $true
    $glist.Location = New-Object System.Drawing.Point(8, 8)
    $glist.Size = New-Object System.Drawing.Size(596, 86)
    $glist.Anchor = 'Top,Left,Right'
    [void]$glist.Columns.Add('GPU', 230)
    [void]$glist.Columns.Add('Vendor', 120)
    [void]$glist.Columns.Add('Type', 85)
    [void]$glist.Columns.Add('VRAM', 60)
    [void]$glist.Columns.Add('Status', 60)
    [void]$glist.Columns.Add('Driver', 110)
    if ($null -ne $gpu) {
        foreach ($g in $gpu.Gpus) {
            $vram = if ($null -ne $g.VramGB) { "$($g.VramGB) GB" } else { 'Unknown' }
            $item = New-Object System.Windows.Forms.ListViewItem([string]$g.Name)
            [void]$item.SubItems.Add([string]$g.Vendor)
            [void]$item.SubItems.Add([string]$g.Type)
            [void]$item.SubItems.Add($vram)
            [void]$item.SubItems.Add([string]$g.Status)
            [void]$item.SubItems.Add([string]$g.DriverVersion)
            [void]$glist.Items.Add($item)
        }
    }
    $tabGraphics.Controls.Add($glist)
    # Let the GPU-name column (the primary identifier) absorb the slack width.
    $gFill = {
        $other = 0
        for ($idx = 1; $idx -lt $glist.Columns.Count; $idx++) { $other += $glist.Columns[$idx].Width }
        $f = $glist.ClientSize.Width - $other
        if ($f -gt 150) { $glist.Columns[0].Width = $f }
    }.GetNewClosure()
    $glist.Add_Resize($gFill)
    & $gFill
    $gRunY = 100
    # Live GPU sensor panel (nvidia-smi), when present.
    if ($null -ne $Report.GpuSensor) {
        $gsr = $Report.GpuSensor
        $gsHdr = New-Object System.Windows.Forms.Label
        $gsHdr.Text = 'GPU sensors (live, via nvidia-smi)'
        $gsHdr.Location = New-Object System.Drawing.Point(14, $gRunY); $gsHdr.AutoSize = $true
        $gsHdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $tabGraphics.Controls.Add($gsHdr)
        $gsKeys = @('Temperature:', 'Utilization:', 'Core clock:', 'Power draw:', 'Perf. state:')
        $gsVals = @(
            $(if ($null -ne $gsr.TempC) { "$($gsr.TempC)$([char]176)C" } else { 'Unknown' })
            $(if ($null -ne $gsr.UtilPercent) { "$($gsr.UtilPercent)%" } else { 'Unknown' })
            $(if ($null -ne $gsr.ClockMHz) { "$($gsr.ClockMHz)$(if ($null -ne $gsr.MaxClockMHz) { " / $($gsr.MaxClockMHz)" }) MHz" } else { 'Unknown' })
            $(if ($null -ne $gsr.PowerW) { '{0:N1} W' -f $gsr.PowerW } else { 'Unknown' })
            $(if ($gsr.PState) { $gsr.PState } else { 'Unknown' })
        )
        if ($gsr.ThermalThrottle) { $gsKeys += 'Thermal:'; $gsVals += 'THROTTLING (reducing clocks)' }
        $gRunY = Add-KvBlock -Parent $tabGraphics -Keys $gsKeys -Values $gsVals -X 14 -Y ($gRunY + 22) -KeyW 110 -ValW 320
        $gRunY += 10
    }
    # Gaming verdict (synthesis of GPU/CPU/memory/display), when a GPU was assessed.
    if ($null -ne $Report.Gaming) {
        $gm = $Report.Gaming
        $gmHdr = New-Object System.Windows.Forms.Label
        $gmHdr.Text = 'Gaming'
        $gmHdr.Location = New-Object System.Drawing.Point(14, $gRunY); $gmHdr.AutoSize = $true
        $gmHdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $tabGraphics.Controls.Add($gmHdr)
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
        $gy = Add-KvBlock -Parent $tabGraphics -Keys $gKeys -Values $gVals -X 14 -Y ($gRunY + 22) -KeyW 110 -ValW 440
        $gCap = New-Object System.Windows.Forms.Label
        $gCap.Text = "Gaming tiering is approximate / generation-level, not a benchmark.`r`nLaptop GPU variants (`"Max-Q`", `"Laptop`") are tiered one rank below the desktop card of the same name."
        $gCap.Location = New-Object System.Drawing.Point(14, ($gy + 6))
        $gCap.AutoSize = $true
        $gCap.ForeColor = [System.Drawing.Color]::Gray
        $tabGraphics.Controls.Add($gCap)
    }
    [void]$tabs.TabPages.Add($tabGraphics)
```

- [ ] **Step 4: Delete the separate Gaming tab block**

In `Show-SystemInfo.ps1`, delete the entire `# --- Gaming tab (synthesis; present whenever a GPU was assessed) ---` block — from that comment line through its closing `}` and the blank line, i.e. the `if ($null -ne $Report.Gaming) { ... [void]$tabs.TabPages.Add($tabGame) }` block (was lines 2386-2413). Its content now lives in the Graphics tab.

- [ ] **Step 5: Run both suites**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: `GUI smoke: all passed`, exit 0. (11 tabs; Graphics carries the GPU list + sensors + gaming verdict; desktop 8.)
Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: `457 passed, 0 failed` (unchanged — no pure functions touched).

- [ ] **Step 6: Off-screen render sanity check**

Run this (Windows PowerShell STA) to render the Graphics tab to a PNG and confirm nothing clips:
```powershell
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -Command "$env:SYSTEMINFO_NOMAIN='1'; . .\Show-SystemInfo.ps1; . .\tests\GuiSmoke.ps1 2>$null; $f=New-SystemForm $report; $f.Size=New-Object Drawing.Size(640,620); $tc=$f.Controls|?{$_ -is [Windows.Forms.TabControl]}|Select -First 1; $tc.SelectedTab=($tc.TabPages|?{$_.Text -eq 'Graphics'}); $f.Show(); [Windows.Forms.Application]::DoEvents(); $bmp=New-Object Drawing.Bitmap($f.Width,$f.Height); $f.DrawToBitmap($bmp,(New-Object Drawing.Rectangle(0,0,$f.Width,$f.Height))); $p=Join-Path $env:TEMP 'gfx.png'; $bmp.Save($p); $f.Dispose(); Write-Output $p"
```
(The `. .\tests\GuiSmoke.ps1 2>$null` dot-source reuses the smoke fixtures/`$report`; it exits 0 so it won't abort the line.) Read the PNG: the Graphics tab should show the GPU adapter table, the `GPU sensors (live…)` block, and the `Gaming` block (Overall / Limited by / … / caption) — all visible, no clipping. If the bottom clips, that's the AutoScroll case — confirm a scrollbar is present rather than lost content.

- [ ] **Step 7: Commit**

```bash
git add Show-SystemInfo.ps1 tests/GuiSmoke.ps1
git commit -m "Tab consolidation: Graphics tab merges GPU + sensors + Gaming (slice N)"
```

---

### Task 2: Power tab (merge Battery + Live) + Security rename

**Files:**
- Modify: `Show-SystemInfo.ps1` — replace the `# --- Battery tab ---` and `# --- Live tab ---` blocks (currently ~2415-2459, shifted by Task 1) with one `# --- Power tab ---` block; change the Firmware tab's `.Text` to `Security`.
- Modify: `tests/GuiSmoke.ps1` — retarget the Battery + Live checks to a `Power` tab; the Firmware lookups to `Security`; drop the count to 10.

> **Note:** the line numbers cited in this task are from the *original* file — Task 1 already shifted them. Locate every block by its content (the `$batTab`/`$liveTab`/`$fwTab` lookups), not by line number.

- [ ] **Step 1: Update GuiSmoke expectations (they must fail first)**

In `tests/GuiSmoke.ps1`:

(a) The count line (now `-eq 11` after Task 1) — replace with:
```powershell
    Check ($tabControl.TabPages.Count -eq 10) 'ten tabs'
```

(b) The tab-names `Check` (the Task-1 version listing `Battery`/`Live`/`Firmware & Security`) — replace with:
```powershell
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'Graphics') -and ($tabNames -contains 'Memory') -and ($tabNames -contains 'Storage') -and ($tabNames -contains 'Power') -and ($tabNames -contains 'Benchmark') -and ($tabNames -contains 'Network') -and ($tabNames -contains 'Security') -and ($tabNames -contains 'Upgrade')) 'Overview/CPU/Graphics/Memory/Storage/Power/Benchmark/Network/Security/Upgrade tabs'
```

(c) The Battery block (currently lines 104-109 — `$batTab = ... 'Battery'` and its three checks) AND the Live block (currently lines 115-119 — `$liveTab = ... 'Live'` and its two checks) — replace **both** with one consolidated Power block (delete the Live block lines; replace the Battery block lines with):
```powershell
    $pwrTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Power' } | Select-Object -First 1
    Check ($null -ne $pwrTab) 'has Power tab'
    $pwrText = (Get-AllText $pwrTab) -join "`n"
    Check ([bool]($pwrText -match 'Cycle count'))     'Power tab shows battery labels'
    Check ([bool]($pwrText -match '95,065 mWh'))      'Power tab shows battery design capacity'
    Check ([bool]($pwrText -match '45% worn'))        'Power tab shows battery wear'
    Check ([bool]($pwrText -match 'Commit charge'))   'Power tab shows live-load labels'
    Check ([bool]($pwrText -match 'Under pressure'))  'Power tab shows live-load status'
```
(Leave the two `$ovText -match 'Battery:'` / `'45% worn'` Overview checks between them — lines 112-113 — in place; the Overview is unchanged. If those two Overview lines currently sit between the Battery and Live blocks, move them to just after the new Power block so the Power block is contiguous.)

(d) The Firmware block (currently lines 138-143) — replace the tab lookup line:
```powershell
    $fwTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Firmware & Security' } | Select-Object -First 1
    Check ($null -ne $fwTab) 'has Firmware & Security tab'
```
with:
```powershell
    $fwTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Security' } | Select-Object -First 1
    Check ($null -ne $fwTab) 'has Security tab'
```
(The three content checks below it — `Windows 11 readiness`, `running Windows 11`, `Microsoft` — stay unchanged; that content is untouched.)

(e) Desktop fixture — the Firmware presence line:
```powershell
    Check ($names2 -contains 'Firmware & Security') 'desktop: Firmware & Security tab present'
```
becomes:
```powershell
    Check ($names2 -contains 'Security') 'desktop: Security tab present'
```
And the three desktop absence checks for Battery/Live/Network (currently lines 155-157) — replace the Battery and Live ones with a single Power-absence check (keep the Network one):
```powershell
    Check (-not ($names2 -contains 'Power'))   'desktop: no Power tab (no battery, no load)'
    Check (-not ($names2 -contains 'Network')) 'no-net: no Network tab'
```
Also update the desktop **count** check's label string (set to `8` in Task 1) so it no longer says "Firmware & Security" — its `Check` label should read `'desktop: eight tabs (Graphics + Benchmark + Security + Upgrade; no Power/Network)'` (the boolean `-eq 8` is unchanged; only the description text).

- [ ] **Step 2: Run GuiSmoke to verify the new checks fail**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: FAILs — `ten tabs` (still 11), the tab-names check (no `Power`/`Security` yet), `has Power tab` and its checks, `has Security tab`, `desktop: Security tab present`. Exit 1.

- [ ] **Step 3: Replace the Battery + Live blocks with the Power block**

In `Show-SystemInfo.ps1`, replace both the `# --- Battery tab (only when a battery exists) ---` block and the `# --- Live tab (only when live load data exists) ---` block (contiguous; the two `if` blocks) with:

```powershell
    # --- Power tab (battery + live memory load; present when either exists) ---
    if ($null -ne $Report.Battery -or $null -ne $Report.Load) {
        $tabPower = New-Object System.Windows.Forms.TabPage
        $tabPower.Text = 'Power'
        $tabPower.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
        $tabPower.AutoScroll = $true
        $pRunY = 10
        if ($null -ne $Report.Battery) {
            $bat = $Report.Battery
            $bHdr = New-Object System.Windows.Forms.Label
            $bHdr.Text = 'Battery'
            $bHdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $bHdr.Location = New-Object System.Drawing.Point(14, $pRunY); $bHdr.AutoSize = $true
            $tabPower.Controls.Add($bHdr)
            $batKeys = @('Charge:', 'Status:', 'Power source:', 'Health:', 'Design capacity:', 'Full-charge capacity:', 'Cycle count:', 'Chemistry:', 'Manufacturer:', 'Power plan:')
            $batVals = @(
                $(if ($null -ne $bat.ChargePercent) { "$($bat.ChargePercent)%" } else { 'Unknown' })
                $bat.Status
                $(if ($bat.IsOnAC -eq $true) { 'AC (plugged in)' } elseif ($bat.IsOnAC -eq $false) { 'Battery' } else { 'Unknown' })
                $(if ($null -ne $bat.WearPercent) { "$($bat.HealthPercent)% of design ($($bat.WearPercent)% worn)" } else { 'Unknown' })
                $(if ($null -ne $bat.DesignCapacityMWh) { '{0:N0} mWh' -f $bat.DesignCapacityMWh } else { 'Unknown' })
                $(if ($null -ne $bat.FullChargeCapacityMWh) { '{0:N0} mWh' -f $bat.FullChargeCapacityMWh } else { 'Unknown' })
                $(if ($null -ne $bat.CycleCount) { "$($bat.CycleCount)" } else { 'Not reported' })
                $(if ($bat.Chemistry) { $bat.Chemistry } else { 'Unknown' })
                $(if ($bat.Manufacturer) { $bat.Manufacturer } else { 'Unknown' })
                $(if ($bat.PowerPlan) { $bat.PowerPlan } else { 'Unknown' })
            )
            $pRunY = Add-KvBlock -Parent $tabPower -Keys $batKeys -Values $batVals -X 14 -Y ($pRunY + 22) -KeyW 150 -ValW 420
            $pRunY += 14
        }
        if ($null -ne $Report.Load) {
            $ld = $Report.Load
            $status = switch (Get-LoadStatus -Load $ld) { 'pressure' { 'Under pressure' } 'tight' { 'Getting tight' } default { 'OK' } }
            $lHdr = New-Object System.Windows.Forms.Label
            $lHdr.Text = 'Live load'
            $lHdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
            $lHdr.Location = New-Object System.Drawing.Point(14, $pRunY); $lHdr.AutoSize = $true
            $tabPower.Controls.Add($lHdr)
            $liveKeys = @('Total RAM:', 'Available:', 'Commit charge:', 'Paging (to disk):', 'Status:')
            $liveVals = @(
                $(if ($null -ne $ld.TotalPhysicalGB) { "$($ld.TotalPhysicalGB) GB" } else { 'Unknown' })
                $(if ($null -ne $ld.AvailableGB) { "$($ld.AvailableGB) GB" + $(if ($null -ne $ld.AvailablePercent) { " ($($ld.AvailablePercent)%)" } else { '' }) } else { 'Unknown' })
                $(if ($null -ne $ld.CommitPercent) { "{0} GB of {1} GB  ({2}%)" -f $ld.CommitUsedGB, $ld.CommitLimitGB, $ld.CommitPercent } else { 'Unknown' })
                $(if ($null -ne $ld.PageReadsPerSec) { "~{0:N0} hard reads/sec" -f $ld.PageReadsPerSec } else { 'Unknown' })
                $status
            )
            $ly = Add-KvBlock -Parent $tabPower -Keys $liveKeys -Values $liveVals -X 14 -Y ($pRunY + 22) -KeyW 150 -ValW 420
            $liveCaption = New-Object System.Windows.Forms.Label
            $liveCaption.Text = '(live values, as of when this window opened)'
            $liveCaption.Location = New-Object System.Drawing.Point(14, ($ly + 6))
            $liveCaption.AutoSize = $true
            $liveCaption.ForeColor = [System.Drawing.Color]::Gray
            $tabPower.Controls.Add($liveCaption)
        }
        [void]$tabs.TabPages.Add($tabPower)
    }
```

- [ ] **Step 4: Rename the Firmware tab to Security**

In `Show-SystemInfo.ps1`, in the `# --- Firmware & Security tab ---` block, replace:
```powershell
        $tabFw.Text = 'Firmware & Security'
```
with:
```powershell
        $tabFw.Text = 'Security'
```
(Only the tab label changes; the firmware/readiness content and the `$tabFw` variable name stay as-is.)

- [ ] **Step 5: Run both suites**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: `GUI smoke: all passed`, exit 0. (10 tabs; Power carries battery + live; Security present; desktop 8 with no Power tab.)
Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: `457 passed, 0 failed`.

- [ ] **Step 6: Off-screen render sanity check**

Run (Windows PowerShell STA), rendering the Power tab:
```powershell
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -Command "$env:SYSTEMINFO_NOMAIN='1'; . .\Show-SystemInfo.ps1; . .\tests\GuiSmoke.ps1 2>$null; $f=New-SystemForm $report; $f.Size=New-Object Drawing.Size(640,620); $tc=$f.Controls|?{$_ -is [Windows.Forms.TabControl]}|Select -First 1; $tc.SelectedTab=($tc.TabPages|?{$_.Text -eq 'Power'}); $f.Show(); [Windows.Forms.Application]::DoEvents(); $bmp=New-Object Drawing.Bitmap($f.Width,$f.Height); $f.DrawToBitmap($bmp,(New-Object Drawing.Rectangle(0,0,$f.Width,$f.Height))); $p=Join-Path $env:TEMP 'power.png'; $bmp.Save($p); $f.Dispose(); Write-Output $p"
```
Read the PNG: the Power tab shows a bold `Battery` header + its rows, then a bold `Live load` header + its rows + the live caption, all visible. Also confirm the tab strip now shows all 10 tabs on **one row with no `◄ ►` arrows**.

- [ ] **Step 7: Commit**

```bash
git add Show-SystemInfo.ps1 tests/GuiSmoke.ps1
git commit -m "Tab consolidation: Power tab merges Battery + Live; Security rename (slice N)"
```

---

### Task 3: End-to-end verification + finishing

**Files:** none modified (verification only).

- [ ] **Step 1: Both suites green**

Run: `pwsh -File tests/SystemInfo.Tests.ps1` → `457 passed, 0 failed`.
Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → `GUI smoke: all passed`, exit 0.

- [ ] **Step 2: Console byte-identity (the safety property)**

Confirm `-Console` output is unchanged by this GUI-only slice. Compare against `main`:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-SystemInfo.ps1 -Console > $env:TEMP\con_new.txt
git show main:Show-SystemInfo.ps1 > $env:TEMP\Show-main.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\Show-main.ps1 -Console > $env:TEMP\con_main.txt
Compare-Object (Get-Content $env:TEMP\con_new.txt) (Get-Content $env:TEMP\con_main.txt)
```
Expected: only live-value lines differ (available RAM %, paging reads/sec, Wi-Fi signal, GPU sensor readings, timestamps) — no structural/section differences. If any section header or label differs, stop and investigate.

- [ ] **Step 3: Real GUI launch (optional visual confirm)**

If you want to eyeball the real window: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-SystemInfo.ps1` — confirm 10 tabs, no scroll arrows, Graphics/Power/Security populated. Close the window.

- [ ] **Step 4: Report done**

No commit (verification only). The branch `feature/tab_consolidation` is ready for the finishing flow (verify → FF-merge to `main` → push), driven by superpowers:finishing-a-development-branch.
