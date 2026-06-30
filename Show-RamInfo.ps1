<#
.SYNOPSIS
    Reports installed RAM (amount + speed) and what the motherboard supports
    (max capacity + slots), in a small GUI window or as console text.
.NOTES
    The motherboard's max supported *speed* is not stored in firmware anywhere,
    so it is reported as "not in firmware" alongside the detected board model.
#>
param([switch]$Console)

# --- Functions are added below via TDD ---

function ConvertTo-MemoryTypeName {
    # Decode an SMBIOS memory-type code (Win32_PhysicalMemory.SMBIOSMemoryType)
    # into a friendly name. Unknown codes show the raw number; null -> "Unknown".
    param($Code)
    if ($null -eq $Code) { return 'Unknown' }
    $map = @{
        18 = 'DDR'; 19 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'
        27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'
        34 = 'DDR5'; 35 = 'LPDDR5'
    }
    $key = [int]$Code
    if ($map.ContainsKey($key)) { return $map[$key] }
    return "Unknown ($key)"
}

function ConvertTo-VendorName {
    # Decode Win32_PhysicalMemory.Manufacturer. Modern firmware reports a JEDEC
    # hex code (e.g. "80AD00000000"); older/some report a friendly name already.
    # Known DRAM-maker codes are mapped; anything else is returned as-is.
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return 'Unknown' }
    $t = $Raw.Trim()
    if ($t -match '^[0-9A-Fa-f]+$') {
        $prefix = $t.Substring(0, [Math]::Min(4, $t.Length)).ToUpper()
        $map = @{ '80AD' = 'SK Hynix'; '80CE' = 'Samsung'; '802C' = 'Micron' }
        if ($map.ContainsKey($prefix)) { return $map[$prefix] }
        return $t   # unknown hex code: show it raw rather than guess
    }
    return $t       # already a human-readable name
}

function New-RamReport {
    # Pure composition: takes already-collected raw data (no CIM here) and
    # derives the summary the renderers display. Kept side-effect-free so it
    # is fully unit-testable.
    param(
        [object[]] $Modules = @(),
        [object]   $MaxCapacityBytes = $null,
        [int]      $TotalSlots = 0,
        [string]   $BoardMaker = '',
        [string]   $BoardModel = '',
        [string]   $BoardVersion = '',
        [string]   $CpuName = ''
    )

    $populated = @($Modules).Count

    $sum = ($Modules | Measure-Object -Property CapacityBytes -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }
    $totalGB = [math]::Round([double]$sum / 1GB, 1)

    $free = [math]::Max(0, $TotalSlots - $populated)

    $typeName = if ($populated -gt 0) { ConvertTo-MemoryTypeName $Modules[0].TypeCode } else { 'Unknown' }

    $maxGB = $null
    if ($null -ne $MaxCapacityBytes -and [uint64]$MaxCapacityBytes -gt 0) {
        $maxGB = [math]::Round([double][uint64]$MaxCapacityBytes / 1GB, 1)
    }

    $board = ("$BoardMaker".Trim() + ' ' + "$BoardModel".Trim()).Trim()
    if (-not [string]::IsNullOrWhiteSpace($BoardVersion)) {
        $board = "$board (rev $($BoardVersion.Trim()))"
    }
    if ([string]::IsNullOrWhiteSpace($board)) { $board = 'Unknown' }

    $displayModules = @(foreach ($m in $Modules) {
        $rated   = if ($null -ne $m.RatedSpeed   -and [int]$m.RatedSpeed   -gt 0) { [int]$m.RatedSpeed }   else { 'Unknown' }
        $current = if ($null -ne $m.CurrentSpeed -and [int]$m.CurrentSpeed -gt 0) { [int]$m.CurrentSpeed } else { 'Unknown' }
        $part    = if ([string]::IsNullOrWhiteSpace($m.PartNumber)) { 'Unknown' } else { "$($m.PartNumber)".Trim() }
        $slot    = if ([string]::IsNullOrWhiteSpace($m.Slot))       { 'Unknown' } else { "$($m.Slot)".Trim() }
        [pscustomobject]@{
            Slot    = $slot
            SizeGB  = [math]::Round([double]$m.CapacityBytes / 1GB, 1)
            Rated   = $rated
            Current = $current
            Vendor  = ConvertTo-VendorName $m.VendorRaw
            Part    = $part
        }
    })

    # CPU-derived max memory speed (the figure isn't in firmware)
    $cpuSpec = Get-CpuMemorySpec -Name $CpuName -MemoryType $typeName
    $cpuDisplay = Format-CpuName $CpuName

    # Insight inputs from the raw module data
    $ratedSpeeds = @($Modules | ForEach-Object { $_.RatedSpeed }   | Where-Object { $_ -and [int]$_ -gt 0 } | ForEach-Object { [int]$_ })
    $runningVals = @($Modules | ForEach-Object { $_.CurrentSpeed } | Where-Object { $_ -and [int]$_ -gt 0 } | ForEach-Object { [int]$_ })
    $running = if ($runningVals.Count -gt 0) { ($runningVals | Measure-Object -Maximum).Maximum } else { $null }

    $insights = Get-RamInsights -RunningSpeed $running `
                                -ModuleRatedSpeeds $ratedSpeeds `
                                -CpuMaxSpeed $cpuSpec.MaxSpeed `
                                -CpuName $cpuDisplay `
                                -PopulatedSlots $populated `
                                -TotalSlots $TotalSlots `
                                -InstalledGB $totalGB `
                                -MaxCapacityGB $maxGB

    [pscustomobject]@{
        TotalInstalledGB = $totalGB
        PopulatedSlots   = $populated
        TotalSlots       = $TotalSlots
        FreeSlots        = $free
        TypeName         = $typeName
        MaxCapacityGB    = $maxGB
        Board            = $board
        Modules          = $displayModules
        CpuName          = $cpuDisplay
        MaxSpeed         = $cpuSpec.MaxSpeed
        MaxSpeedLabel    = $cpuSpec.Label
        MaxSpeedKnown    = $cpuSpec.Known
        MaxSpeedSource   = $cpuSpec.Source
        Insights         = $insights
    }
}

# --- CPU max memory speed (offline lookup; the speed isn't in firmware) ---

function Format-CpuName {
    # Tidy a raw Win32_Processor.Name for display: drop (R)/(TM), the trailing
    # "CPU @ x.xxGHz", and core-count / "Processor" filler.
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $s = $Name
    $s = $s -replace '\((R|TM|tm|r)\)', ''
    $s = $s -replace '\s*@.*$', ''
    $s = $s -replace '\s+CPU\b', ''
    $s = $s -replace '\s+\w+-Core(\s+Processor)?', ''
    $s = $s -replace '\s+Processor\b', ''
    $s = $s -replace '\s{2,}', ' '
    return $s.Trim()
}

function New-CpuSpecResult {
    param($Speed, $MemoryType)
    $prefix = if ("$MemoryType" -match '^(DDR\d|LPDDR\d)') { $matches[1] } else { '' }
    $label  = if ($prefix) { "$prefix-$Speed" } else { "$Speed MT/s" }
    [pscustomobject]@{
        MaxSpeed = [int]$Speed
        Label    = $label
        Source   = 'JEDEC platform max (generation-level)'
        Known    = $true
    }
}

function Get-IntelGen {
    # Generation from an Intel Core model number. 5-digit -> first 2 digits.
    # 4-digit -> first 2 if it starts with '1' (10/11/12-series low-power like
    # 1065G7, 1255U), else first 1 digit (4790K, 8550U, 9700K).
    param([string]$Model)
    if ($Model.Length -eq 5) { return [int]$Model.Substring(0, 2) }
    if ($Model.Length -eq 4) {
        if ($Model.Substring(0, 1) -eq '1') { return [int]$Model.Substring(0, 2) }
        return [int]$Model.Substring(0, 1)
    }
    return 0
}

function Get-CpuMemorySpec {
    # Map a CPU name to its rated max memory speed (JEDEC, generation-level).
    # Returns { MaxSpeed; Label; Source; Known }. Unrecognized -> Known=$false.
    param([string]$Name, [string]$MemoryType = 'DDR4')

    $unknown = [pscustomobject]@{ MaxSpeed = $null; Label = $null; Source = $null; Known = $false }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $unknown }
    $n = $Name.Trim()
    $isDdr5 = "$MemoryType" -match 'DDR5'

    if ($n -match 'Intel') {
        if ($n -match 'Ultra\s+\d+\s+(\d{3})') {
            $series = [math]::Floor([int]$matches[1] / 100)
            $spd = if ($series -ge 2) { 6400 } else { 5600 }   # Arrow/Lunar vs Meteor
            return (New-CpuSpecResult $spd $MemoryType)
        }
        if ($n -match '(i[3579])-(\d{4,5})([A-Za-z0-9]*)') {
            $tier = $matches[1]; $model = $matches[2]; $suffix = $matches[3].ToUpper()
            $gen = Get-IntelGen $model
            $ddr4 = $null; $ddr5 = $null
            switch ($gen) {
                6  { $ddr4 = 2133 }
                7  { $ddr4 = 2400 }
                8  { $ddr4 = 2666 }
                9  { $ddr4 = 2666 }
                10 { if ($suffix -match 'H' -or $tier -eq 'i7' -or $tier -eq 'i9') { $ddr4 = 2933 } else { $ddr4 = 2666 } }
                11 { $ddr4 = 3200 }
                12 { $ddr4 = 3200; $ddr5 = 4800 }
                13 { $ddr4 = 3200; $ddr5 = 5600 }
                14 { $ddr4 = 3200; $ddr5 = 5600 }
                default { return $unknown }
            }
            $spd = if ($isDdr5 -and $ddr5) { $ddr5 } elseif (-not $isDdr5 -and $ddr4) { $ddr4 } elseif ($ddr5) { $ddr5 } else { $ddr4 }
            if (-not $spd) { return $unknown }
            return (New-CpuSpecResult $spd $MemoryType)
        }
        return $unknown
    }

    if ($n -match 'AMD|Ryzen') {
        if ($n -match 'Threadripper|EPYC') { return $unknown }
        if ($n -match 'Ryzen\s+\d+\s+(\d{4})') {
            $first = [int]"$($matches[1])".Substring(0, 1)
            $ddr4 = $null; $ddr5 = $null
            switch ($first) {
                1 { $ddr4 = 2667 }
                2 { $ddr4 = 2933 }
                3 { $ddr4 = 3200 }
                4 { $ddr4 = 3200 }
                5 { $ddr4 = 3200 }
                6 { $ddr5 = 4800 }
                7 { $ddr5 = 5200 }
                8 { $ddr5 = 5200 }
                9 { $ddr5 = 5600 }
                default { return $unknown }
            }
            $spd = if ($isDdr5 -and $ddr5) { $ddr5 } elseif (-not $isDdr5 -and $ddr4) { $ddr4 } elseif ($ddr5) { $ddr5 } else { $ddr4 }
            if (-not $spd) { return $unknown }
            return (New-CpuSpecResult $spd $MemoryType)
        }
        return $unknown
    }

    return $unknown
}

# --- Insights / bottlenecks (pure) ---

function Get-RamInsights {
    # Emits an ordered list of { Kind; Text } notes, only when they apply.
    param(
        [object] $RunningSpeed = $null,
        [int[]]  $ModuleRatedSpeeds = @(),
        [object] $CpuMaxSpeed = $null,
        [string] $CpuName = '',
        [int]    $PopulatedSlots = 0,
        [int]    $TotalSlots = 0,
        [double] $InstalledGB = 0,
        [object] $MaxCapacityGB = $null
    )
    $notes = @()

    # 1. Channel
    if ($PopulatedSlots -eq 1 -and $TotalSlots -ge 2) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Single-channel: only 1 of $TotalSlots slots populated. Adding a matched module would enable dual-channel (up to ~2x memory bandwidth)." }
    }

    # 2. Mixed module speeds
    $rated = @($ModuleRatedSpeeds | Where-Object { $_ -gt 0 })
    $distinct = @($rated | Sort-Object -Unique)
    if ($distinct.Count -gt 1) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Mixed module speeds ($($distinct -join ', ') MT/s) - all modules run at the slowest ($($distinct[0]))." }
    }

    # 3. Speed binding constraint
    $run = if ($null -ne $RunningSpeed -and [int]$RunningSpeed -gt 0) { [int]$RunningSpeed } else { $null }
    $ratedEff = if ($rated.Count -gt 0) { ($rated | Measure-Object -Minimum).Minimum } else { $null }
    $cap = if ($null -ne $CpuMaxSpeed -and [int]$CpuMaxSpeed -gt 0) { [int]$CpuMaxSpeed } else { $null }

    if ($null -ne $run -and $null -ne $ratedEff) {
        if ($null -ne $cap) {
            if ($run -ge $cap -and $ratedEff -gt $cap) {
                $notes += [pscustomobject]@{ Kind = 'ok'; Text = "Memory runs at $run MT/s - the maximum $CpuName supports. Modules are rated $ratedEff, so the CPU is the limiter (normal; faster RAM wouldn't run any faster here)." }
            } elseif ($run -lt $cap -and $run -lt $ratedEff) {
                $target = [math]::Min($cap, $ratedEff)
                $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Memory runs at $run MT/s, but the CPU ($cap) and modules ($ratedEff) both support faster. If your BIOS allows it, enabling XMP/EXPO could reach $target." }
            } elseif ($ratedEff -lt $cap -and $run -ge $ratedEff) {
                $notes += [pscustomobject]@{ Kind = 'info'; Text = "Memory runs at $run MT/s (the module rated max). $CpuName supports up to $cap, so faster modules would run faster." }
            } else {
                $notes += [pscustomobject]@{ Kind = 'ok'; Text = "Memory runs at $run MT/s - the maximum this CPU and these modules support." }
            }
        } else {
            if ($run -lt $ratedEff) {
                $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Memory runs at $run MT/s, below the module rating ($ratedEff). If your BIOS allows it, enabling XMP/EXPO could reach $ratedEff." }
            } else {
                $notes += [pscustomobject]@{ Kind = 'ok'; Text = "Memory runs at $run MT/s, matching the module rated speed." }
            }
        }
    }

    # 4. Capacity headroom
    if ($null -ne $MaxCapacityGB) {
        $maxc = [double]$MaxCapacityGB
        $free = [math]::Max(0, $TotalSlots - $PopulatedSlots)
        if ($free -gt 0) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "$free free slot(s) - you can add memory (supports up to $maxc GB total)." }
        } elseif ($InstalledGB -lt $maxc) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "All slots full at $InstalledGB GB; max is $maxc GB - adding more means replacing modules with larger ones." }
        } else {
            $notes += [pscustomobject]@{ Kind = 'ok'; Text = "At maximum capacity ($maxc GB)." }
        }
    }

    return , @($notes)
}

# --- Collectors (thin CIM wrappers; verified via the -Console integration run) ---

function Get-RamModules {
    # Normalized per-stick data from Win32_PhysicalMemory.
    Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Slot          = $_.DeviceLocator
            CapacityBytes = $_.Capacity
            RatedSpeed    = $_.Speed
            CurrentSpeed  = $_.ConfiguredClockSpeed
            VendorRaw     = $_.Manufacturer
            PartNumber    = $_.PartNumber
            TypeCode      = $_.SMBIOSMemoryType
        }
    }
}

function Get-RamArrayInfo {
    # Max capacity + slot count from Win32_PhysicalMemoryArray (values are in KB).
    $a = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction Stop | Select-Object -First 1
    $maxKB = if ($a.MaxCapacityEx -and $a.MaxCapacityEx -gt 0) { $a.MaxCapacityEx } else { $a.MaxCapacity }
    [pscustomobject]@{
        MaxCapacityBytes = if ($maxKB) { [uint64]$maxKB * 1024 } else { $null }
        TotalSlots       = [int]$a.MemoryDevices
    }
}

function Get-MotherboardInfo {
    $b = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
    [pscustomobject]@{
        Maker   = $b.Manufacturer
        Model   = $b.Product
        Version = $b.Version
    }
}

function Get-CpuInfo {
    $c = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    [pscustomobject]@{ Name = $c.Name }
}

# --- Renderers ---

function Write-RamConsole {
    # Emits the report as plain text to the pipeline (not Write-Host), so it is
    # both the -Console output and the source for the GUI's Copy button.
    param($Report)
    $r = $Report
    $maxCap   = if ($null -ne $r.MaxCapacityGB) { "$($r.MaxCapacityGB) GB" } else { 'Unknown' }
    $maxSpeed = if ($r.MaxSpeedKnown) { $r.MaxSpeedLabel } else { 'Unknown (CPU not recognized - check CPU/board spec)' }

    ''
    '  RAM Information'
    '  ==============='
    ''
    '  Total installed : {0} GB  ({1})'               -f $r.TotalInstalledGB, $r.TypeName
    '  Slots           : {0} used of {1}  ({2} free)' -f $r.PopulatedSlots, $r.TotalSlots, $r.FreeSlots
    '  Max capacity    : {0}  (per firmware)'         -f $maxCap
    '  Max speed (CPU) : {0}'                         -f $maxSpeed
    '  Processor       : {0}'                         -f $r.CpuName
    '  Motherboard     : {0}'                         -f $r.Board
    ''
    '  Modules:'
    ($r.Modules |
        Format-Table -AutoSize @{n='Slot';e={$_.Slot}},
                                @{n='Size(GB)';e={'{0:0.#}' -f $_.SizeGB}},
                                @{n='Rated';e={$_.Rated}},
                                @{n='Current';e={$_.Current}},
                                @{n='Maker';e={$_.Vendor}},
                                @{n='Part #';e={$_.Part}} |
        Out-String).TrimEnd()
    ''
    if (@($r.Insights).Count -gt 0) {
        '  Notes:'
        foreach ($note in $r.Insights) { "    - $($note.Text)" }
        ''
    }
}

function New-RamForm {
    # Builds and returns the WinForms window WITHOUT showing it, so it can be
    # smoke-tested headlessly. Requires an STA host for later ShowDialog/Clipboard.
    param($Report)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $r = $Report
    $maxCap   = if ($null -ne $r.MaxCapacityGB) { "$($r.MaxCapacityGB) GB" } else { 'Unknown' }
    $maxSpeed = if ($r.MaxSpeedKnown) { $r.MaxSpeedLabel } else { 'Unknown - see CPU/board spec' }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'RAM Info'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(620, 600)
    $form.MinimumSize = New-Object System.Drawing.Size(560, 560)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    # Two-column key/value layout: a fixed-x value column aligns in any font,
    # unlike space-padding inside one proportional-font label.
    $summaryKeys = New-Object System.Windows.Forms.Label
    $summaryKeys.Text = "Total installed:`r`nMemory type:`r`nSlots:`r`nMax capacity:`r`nMax speed (CPU):`r`nProcessor:`r`nMotherboard:"
    $summaryKeys.Location = New-Object System.Drawing.Point(12, 12)
    $summaryKeys.Size = New-Object System.Drawing.Size(134, 124)
    $summaryKeys.Anchor = 'Top,Left'
    $form.Controls.Add($summaryKeys)

    $summaryValues = New-Object System.Windows.Forms.Label
    $summaryValues.Text = @(
        "$($r.TotalInstalledGB) GB"
        $r.TypeName
        "$($r.PopulatedSlots) used of $($r.TotalSlots)   ($($r.FreeSlots) free)"
        "$maxCap   (per firmware)"
        $maxSpeed
        $r.CpuName
        $r.Board
    ) -join "`r`n"
    $summaryValues.Location = New-Object System.Drawing.Point(150, 12)
    $summaryValues.Size = New-Object System.Drawing.Size(446, 124)
    $summaryValues.Anchor = 'Top,Left,Right'
    $form.Controls.Add($summaryValues)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.Location = New-Object System.Drawing.Point(12, 144)
    $list.Size = New-Object System.Drawing.Size(584, 200)
    $list.Anchor = 'Top,Bottom,Left,Right'
    [void]$list.Columns.Add('Slot', 70)
    [void]$list.Columns.Add('Size (GB)', 70)
    [void]$list.Columns.Add('Rated', 65)
    [void]$list.Columns.Add('Current', 65)
    [void]$list.Columns.Add('Maker', 100)
    [void]$list.Columns.Add('Part #', 188)
    foreach ($m in $r.Modules) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$m.Slot)
        [void]$item.SubItems.Add([string]$m.SizeGB)
        [void]$item.SubItems.Add([string]$m.Rated)
        [void]$item.SubItems.Add([string]$m.Current)
        [void]$item.SubItems.Add([string]$m.Vendor)
        [void]$item.SubItems.Add([string]$m.Part)
        [void]$list.Items.Add($item)
    }
    $form.Controls.Add($list)

    # Make the last column (Part #) fill the remaining width, tracking resizes.
    $fillLastColumn = {
        $other = 0
        for ($idx = 0; $idx -lt ($list.Columns.Count - 1); $idx++) { $other += $list.Columns[$idx].Width }
        $fill = $list.ClientSize.Width - $other
        if ($fill -gt 120) { $list.Columns[$list.Columns.Count - 1].Width = $fill }
    }.GetNewClosure()
    $list.Add_Resize($fillLastColumn)
    & $fillLastColumn

    $notesHeader = New-Object System.Windows.Forms.Label
    $notesHeader.Text = 'Notes:'
    $notesHeader.Location = New-Object System.Drawing.Point(12, 352)
    $notesHeader.Size = New-Object System.Drawing.Size(200, 18)
    $notesHeader.Anchor = 'Bottom,Left'
    $form.Controls.Add($notesHeader)

    $notesBox = New-Object System.Windows.Forms.TextBox
    $notesBox.Multiline = $true
    $notesBox.ReadOnly = $true
    $notesBox.ScrollBars = 'Vertical'
    $notesBox.WordWrap = $true
    $notesBox.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248)
    $notesBox.Location = New-Object System.Drawing.Point(12, 372)
    $notesBox.Size = New-Object System.Drawing.Size(584, 132)
    $notesBox.Anchor = 'Bottom,Left,Right'
    $notesBox.Text = if (@($r.Insights).Count -gt 0) {
        (@($r.Insights) | ForEach-Object { "- $($_.Text)" }) -join "`r`n`r`n"
    } else { '(no notes)' }
    $form.Controls.Add($notesBox)

    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = 'Copy'
    $btnCopy.Size = New-Object System.Drawing.Size(90, 30)
    $btnCopy.Location = New-Object System.Drawing.Point(402, 516)
    $btnCopy.Anchor = 'Bottom,Right'
    $copyText = (Write-RamConsole $r | Out-String).Trim()
    $btnCopy.Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText($copyText); $btnCopy.Text = 'Copied!' }
        catch { $btnCopy.Text = 'Copy failed' }
    }.GetNewClosure())
    $form.Controls.Add($btnCopy)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Size = New-Object System.Drawing.Size(90, 30)
    $btnClose.Location = New-Object System.Drawing.Point(502, 516)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)
    $form.AcceptButton = $btnClose

    return $form
}

function Show-RamWindow {
    param($Report)
    $form = New-RamForm $Report
    [void]$form.ShowDialog()
    $form.Dispose()
}

# --- Main ---

function Invoke-RamInfo {
    param([switch]$Console)

    try {
        $modules = @(Get-RamModules)
        $array   = Get-RamArrayInfo
        $board   = Get-MotherboardInfo
        $cpu     = Get-CpuInfo
    } catch {
        $err = "Couldn't read memory info from Windows (CIM/WMI): $($_.Exception.Message)"
        if ($Console) { Write-Output $err; return }
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($err, 'RAM Info')
        } catch { Write-Output $err }
        return
    }

    $report = New-RamReport -Modules $modules `
                            -MaxCapacityBytes $array.MaxCapacityBytes `
                            -TotalSlots $array.TotalSlots `
                            -BoardMaker $board.Maker `
                            -BoardModel $board.Model `
                            -BoardVersion $board.Version `
                            -CpuName $cpu.Name

    if ($Console) { Write-RamConsole $report; return }

    try {
        Show-RamWindow $report
    } catch {
        Write-Output "(GUI unavailable - showing text. $($_.Exception.Message))"
        Write-RamConsole $report
    }
}

if (-not $env:RAMINFO_NOMAIN) {
    Invoke-RamInfo -Console:$Console
}
