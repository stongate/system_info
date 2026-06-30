<#
.SYNOPSIS
    Reports system information (processor + memory) and cross-subsystem
    bottleneck notes, in a small tabbed GUI window or as console text.
.NOTES
    Built as a per-subsystem architecture (CPU, Memory today; GPU/Storage later):
    thin CIM collectors -> pure section builders -> a system report -> renderers.
    Some derived facts (CPU max memory speed, codename) aren't in firmware and
    come from a generation-level offline lookup.
#>
param([switch]$Console)

# =====================================================================
# Decoders / parsing (pure)
# =====================================================================

function ConvertTo-MemoryTypeName {
    # SMBIOS memory-type code (Win32_PhysicalMemory.SMBIOSMemoryType) -> name.
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
    # Win32_PhysicalMemory.Manufacturer -> friendly DRAM-maker name.
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return 'Unknown' }
    $t = $Raw.Trim()
    if ($t -match '^[0-9A-Fa-f]+$') {
        $prefix = $t.Substring(0, [Math]::Min(4, $t.Length)).ToUpper()
        $map = @{ '80AD' = 'SK Hynix'; '80CE' = 'Samsung'; '802C' = 'Micron' }
        if ($map.ContainsKey($prefix)) { return $map[$prefix] }
        return $t
    }
    return $t
}

function Format-CpuName {
    # Tidy a raw Win32_Processor.Name for display.
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

function Get-IntelGen {
    # Generation from an Intel Core model number.
    param([string]$Model)
    if ($Model.Length -eq 5) { return [int]$Model.Substring(0, 2) }
    if ($Model.Length -eq 4) {
        if ($Model.Substring(0, 1) -eq '1') { return [int]$Model.Substring(0, 2) }
        return [int]$Model.Substring(0, 1)
    }
    return 0
}

function New-CpuSpec {
    # Build the derived-CPU-spec object (memory speed + codename/generation).
    param($Vendor, $Generation, $GenerationLabel, $Codename, $Speed, $MemoryType)
    $prefix = if ("$MemoryType" -match '^(DDR\d|LPDDR\d)') { $matches[1] } else { '' }
    $label  = if ($prefix) { "$prefix-$Speed" } else { "$Speed MT/s" }
    [pscustomobject]@{
        Vendor          = $Vendor
        Generation      = $Generation
        GenerationLabel = $GenerationLabel
        Codename        = $Codename
        MaxSpeed        = [int]$Speed
        Label           = $label
        Source          = 'JEDEC platform max (generation-level)'
        Known           = $true
    }
}

function Get-CpuSpec {
    # Map a CPU name to derived facts: vendor, generation, codename, and rated
    # max memory speed (JEDEC, generation-level). Unrecognized -> Known=$false.
    param([string]$Name, [string]$MemoryType = 'DDR4')

    $unknown = [pscustomobject]@{
        Vendor = 'Unknown'; Generation = $null; GenerationLabel = $null; Codename = $null
        MaxSpeed = $null; Label = $null; Source = $null; Known = $false
    }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $unknown }
    $n = $Name.Trim()
    $isDdr5 = "$MemoryType" -match 'DDR5'

    if ($n -match 'Intel') {
        if ($n -match 'Ultra\s+\d+\s+(\d{3})') {
            $series = [math]::Floor([int]$matches[1] / 100)
            $spd  = if ($series -ge 2) { 6400 } else { 5600 }
            $code = if ($series -ge 2) { 'Arrow Lake' } else { 'Meteor Lake' }
            $lbl  = if ($series -ge 2) { 'Core Ultra (Series 2)' } else { 'Core Ultra (Series 1)' }
            return (New-CpuSpec 'Intel' $null $lbl $code $spd $MemoryType)
        }
        if ($n -match '(i[3579])-(\d{4,5})([A-Za-z0-9]*)') {
            $tier = $matches[1]; $model = $matches[2]; $suffix = $matches[3].ToUpper()
            $gen = Get-IntelGen $model
            $ddr4 = $null; $ddr5 = $null; $code = $null
            switch ($gen) {
                6  { $ddr4 = 2133; $code = 'Skylake' }
                7  { $ddr4 = 2400; $code = 'Kaby Lake' }
                8  { $ddr4 = 2666; $code = 'Coffee Lake' }
                9  { $ddr4 = 2666; $code = 'Coffee Lake' }
                10 {
                    $code = if ($suffix -match 'G') { 'Ice Lake' } else { 'Comet Lake' }
                    if ($suffix -match 'H' -or $tier -eq 'i7' -or $tier -eq 'i9') { $ddr4 = 2933 } else { $ddr4 = 2666 }
                }
                11 { $ddr4 = 3200; $code = if ($suffix -match 'G|U') { 'Tiger Lake' } else { 'Rocket Lake' } }
                12 { $ddr4 = 3200; $ddr5 = 4800; $code = 'Alder Lake' }
                13 { $ddr4 = 3200; $ddr5 = 5600; $code = 'Raptor Lake' }
                14 { $ddr4 = 3200; $ddr5 = 5600; $code = 'Raptor Lake Refresh' }
                default { return $unknown }
            }
            $spd = if ($isDdr5 -and $ddr5) { $ddr5 } elseif (-not $isDdr5 -and $ddr4) { $ddr4 } elseif ($ddr5) { $ddr5 } else { $ddr4 }
            if (-not $spd) { return $unknown }
            return (New-CpuSpec 'Intel' $gen "${gen}th Gen" $code $spd $MemoryType)
        }
        return $unknown
    }

    if ($n -match 'AMD|Ryzen') {
        if ($n -match 'Threadripper|EPYC') { return $unknown }
        if ($n -match 'Ryzen\s+\d+\s+(\d{4})') {
            $first = [int]"$($matches[1])".Substring(0, 1)
            $ddr4 = $null; $ddr5 = $null; $code = $null
            switch ($first) {
                1 { $ddr4 = 2667; $code = 'Zen' }
                2 { $ddr4 = 2933; $code = 'Zen+' }
                3 { $ddr4 = 3200; $code = 'Zen 2' }
                4 { $ddr4 = 3200; $code = 'Zen 2' }
                5 { $ddr4 = 3200; $code = 'Zen 3' }
                6 { $ddr5 = 4800; $code = 'Zen 3+' }
                7 { $ddr5 = 5200; $code = 'Zen 4' }
                8 { $ddr5 = 5200; $code = 'Zen 4' }
                9 { $ddr5 = 5600; $code = 'Zen 5' }
                default { return $unknown }
            }
            $spd = if ($isDdr5 -and $ddr5) { $ddr5 } elseif (-not $isDdr5 -and $ddr4) { $ddr4 } elseif ($ddr5) { $ddr5 } else { $ddr4 }
            if (-not $spd) { return $unknown }
            return (New-CpuSpec 'AMD' ($first * 1000) "Ryzen ${first}000" $code $spd $MemoryType)
        }
        return $unknown
    }

    return $unknown
}

# =====================================================================
# Subsystem report builders (pure)
# =====================================================================

function New-CpuReport {
    # Build the CPU section from raw collected fields (no CIM here).
    param(
        [string] $Name = '',
        [object] $Cores = $null,
        [object] $Threads = $null,
        [object] $MaxClockMHz = $null,
        [object] $L2CacheKB = $null,
        [object] $L3CacheKB = $null,
        [string] $Socket = '',
        [object] $AddressWidth = $null,
        [object] $VirtualizationEnabled = $null,
        [string] $MemoryType = 'DDR4'
    )
    $spec    = Get-CpuSpec -Name $Name -MemoryType $MemoryType
    $display = Format-CpuName $Name
    $baseGHz = if ($null -ne $MaxClockMHz -and [double]$MaxClockMHz -gt 0) { [math]::Round([double]$MaxClockMHz / 1000, 2) } else { $null }
    $l2 = if ($null -ne $L2CacheKB -and [double]$L2CacheKB -gt 0) { [math]::Round([double]$L2CacheKB / 1024, 1) } else { $null }
    $l3 = if ($null -ne $L3CacheKB -and [double]$L3CacheKB -gt 0) { [math]::Round([double]$L3CacheKB / 1024, 1) } else { $null }

    [pscustomobject]@{
        Name                  = if ($display) { $display } else { 'Unknown' }
        Vendor                = $spec.Vendor
        Cores                 = if ($null -ne $Cores)   { [int]$Cores }   else { $null }
        Threads               = if ($null -ne $Threads) { [int]$Threads } else { $null }
        BaseClockGHz          = $baseGHz
        L2CacheMB             = $l2
        L3CacheMB             = $l3
        Socket                = if ([string]::IsNullOrWhiteSpace($Socket)) { 'Unknown' } else { $Socket.Trim() }
        Is64Bit               = ($null -ne $AddressWidth -and [int]$AddressWidth -eq 64)
        VirtualizationEnabled = $VirtualizationEnabled
        Codename              = $spec.Codename
        GenerationLabel       = $spec.GenerationLabel
        MaxMemSpeed           = $spec.MaxSpeed
        MaxMemLabel           = $spec.Label
        MaxMemKnown           = $spec.Known
    }
}

function New-MemoryReport {
    # Build the Memory section from raw module/array/board data (no CIM here).
    param(
        [object[]] $Modules = @(),
        [object]   $MaxCapacityBytes = $null,
        [int]      $TotalSlots = 0,
        [string]   $BoardMaker = '',
        [string]   $BoardModel = '',
        [string]   $BoardVersion = ''
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
    if (-not [string]::IsNullOrWhiteSpace($BoardVersion)) { $board = "$board (rev $($BoardVersion.Trim()))" }
    if ([string]::IsNullOrWhiteSpace($board)) { $board = 'Unknown' }

    $displayModules = @(foreach ($m in $Modules) {
        $rated   = if ($null -ne $m.RatedSpeed   -and [int]$m.RatedSpeed   -gt 0) { [int]$m.RatedSpeed }   else { 'Unknown' }
        $current = if ($null -ne $m.CurrentSpeed -and [int]$m.CurrentSpeed -gt 0) { [int]$m.CurrentSpeed } else { 'Unknown' }
        $part    = if ([string]::IsNullOrWhiteSpace($m.PartNumber)) { 'Unknown' } else { "$($m.PartNumber)".Trim() }
        $slot    = if ([string]::IsNullOrWhiteSpace($m.Slot))       { 'Unknown' } else { "$($m.Slot)".Trim() }
        [pscustomobject]@{
            Slot = $slot; SizeGB = [math]::Round([double]$m.CapacityBytes / 1GB, 1)
            Rated = $rated; Current = $current; Vendor = ConvertTo-VendorName $m.VendorRaw; Part = $part
        }
    })

    $ratedSpeeds = @($Modules | ForEach-Object { $_.RatedSpeed }   | Where-Object { $_ -and [int]$_ -gt 0 } | ForEach-Object { [int]$_ })
    $runningVals = @($Modules | ForEach-Object { $_.CurrentSpeed } | Where-Object { $_ -and [int]$_ -gt 0 } | ForEach-Object { [int]$_ })
    $running = if ($runningVals.Count -gt 0) { ($runningVals | Measure-Object -Maximum).Maximum } else { $null }

    [pscustomobject]@{
        TotalInstalledGB = $totalGB
        PopulatedSlots   = $populated
        TotalSlots       = $TotalSlots
        FreeSlots        = $free
        TypeName         = $typeName
        MaxCapacityGB    = $maxGB
        Board            = $board
        Modules          = $displayModules
        RunningSpeed     = $running
        RatedSpeeds      = $ratedSpeeds
    }
}

# =====================================================================
# Insights / bottlenecks (pure)
# =====================================================================

function Get-MemoryInsights {
    # Memory + CPU-memory-speed notes. Emits { Kind; Text } only when applicable.
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

    if ($PopulatedSlots -eq 1 -and $TotalSlots -ge 2) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Single-channel: only 1 of $TotalSlots slots populated. Adding a matched module would enable dual-channel (up to ~2x memory bandwidth)." }
    }

    $rated = @($ModuleRatedSpeeds | Where-Object { $_ -gt 0 })
    $distinct = @($rated | Sort-Object -Unique)
    if ($distinct.Count -gt 1) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Mixed module speeds ($($distinct -join ', ') MT/s) - all modules run at the slowest ($($distinct[0]))." }
    }

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

    if ($null -ne $MaxCapacityGB) {
        $maxc = [double]$MaxCapacityGB
        $freeSlots = [math]::Max(0, $TotalSlots - $PopulatedSlots)
        if ($freeSlots -gt 0) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "$freeSlots free slot(s) - you can add memory (supports up to $maxc GB total)." }
        } elseif ($InstalledGB -lt $maxc) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "All slots full at $InstalledGB GB; max is $maxc GB - adding more means replacing modules with larger ones." }
        } else {
            $notes += [pscustomobject]@{ Kind = 'ok'; Text = "At maximum capacity ($maxc GB)." }
        }
    }

    return , @($notes)
}

function Get-CpuInsights {
    # CPU-only notes. Takes the CPU section object.
    param([object] $Cpu)
    $notes = @()
    if ($null -ne $Cpu -and $Cpu.VirtualizationEnabled -eq $false) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = 'Virtualization (VT-x/AMD-V) appears disabled in BIOS. Enable it for Hyper-V, WSL2, Docker, or VM software. (This firmware flag can be unreliable.)' }
    }
    return , @($notes)
}

function Get-SystemInsights {
    # Orchestrator: per-subsystem notes plus cross-subsystem bottleneck notes.
    param([object] $Cpu, [object] $Memory)
    # Assign sub-results first (their ,@() returns unwrap to clean arrays), then
    # concatenate with +=. Wrapping the calls in @() here would nest each result
    # as a single sub-array element, merging multiple notes into one.
    $memNotes = Get-MemoryInsights -RunningSpeed $Memory.RunningSpeed `
                                   -ModuleRatedSpeeds $Memory.RatedSpeeds `
                                   -CpuMaxSpeed $Cpu.MaxMemSpeed `
                                   -CpuName $Cpu.Name `
                                   -PopulatedSlots $Memory.PopulatedSlots `
                                   -TotalSlots $Memory.TotalSlots `
                                   -InstalledGB $Memory.TotalInstalledGB `
                                   -MaxCapacityGB $Memory.MaxCapacityGB
    $cpuNotes = Get-CpuInsights -Cpu $Cpu

    $notes = @()
    $notes += $memNotes
    $notes += $cpuNotes

    # Cross note: many cores starved by single-channel memory bandwidth.
    if ($Memory.PopulatedSlots -eq 1 -and $Memory.TotalSlots -ge 2 -and $null -ne $Cpu.Cores -and [int]$Cpu.Cores -ge 6) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "$($Cpu.Cores) cores share single-channel memory bandwidth; moving to dual-channel would noticeably help multi-core workloads." }
    }

    return , @(@($notes) | Where-Object { $null -ne $_ })
}

# =====================================================================
# System report composer (pure)
# =====================================================================

function New-SystemReport {
    # Compose the CPU + Memory sections and run the insight engine.
    param([object] $Cpu, [object] $Memory)
    $insights = Get-SystemInsights -Cpu $Cpu -Memory $Memory
    [pscustomobject]@{
        Cpu      = $Cpu
        Memory   = $Memory
        Insights = $insights
    }
}

# =====================================================================
# Collectors (thin CIM wrappers; verified via the -Console run)
# =====================================================================

function Get-RamModules {
    Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Slot = $_.DeviceLocator; CapacityBytes = $_.Capacity; RatedSpeed = $_.Speed
            CurrentSpeed = $_.ConfiguredClockSpeed; VendorRaw = $_.Manufacturer
            PartNumber = $_.PartNumber; TypeCode = $_.SMBIOSMemoryType
        }
    }
}

function Get-RamArrayInfo {
    $a = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction Stop | Select-Object -First 1
    $maxKB = if ($a.MaxCapacityEx -and $a.MaxCapacityEx -gt 0) { $a.MaxCapacityEx } else { $a.MaxCapacity }
    [pscustomobject]@{
        MaxCapacityBytes = if ($maxKB) { [uint64]$maxKB * 1024 } else { $null }
        TotalSlots       = [int]$a.MemoryDevices
    }
}

function Get-MotherboardInfo {
    $b = Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
    [pscustomobject]@{ Maker = $b.Manufacturer; Model = $b.Product; Version = $b.Version }
}

function Get-CpuInfo {
    $c = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    [pscustomobject]@{
        Name = $c.Name
        Cores = $c.NumberOfCores
        Threads = $c.NumberOfLogicalProcessors
        MaxClockMHz = $c.MaxClockSpeed
        L2CacheKB = $c.L2CacheSize
        L3CacheKB = $c.L3CacheSize
        Socket = $c.SocketDesignation
        AddressWidth = $c.AddressWidth
        VirtualizationEnabled = $c.VirtualizationFirmwareEnabled
    }
}

# =====================================================================
# Renderers
# =====================================================================

function Write-SystemConsole {
    # Plain-text report (pipeline output); also the source for the Copy button.
    param($Report)
    $cpu = $Report.Cpu
    $mem = $Report.Memory
    $maxCap   = if ($null -ne $mem.MaxCapacityGB) { "$($mem.MaxCapacityGB) GB" } else { 'Unknown' }
    $maxSpeed = if ($cpu.MaxMemKnown) { $cpu.MaxMemLabel } else { 'Unknown (CPU not recognized)' }
    $virt = if ($cpu.VirtualizationEnabled -eq $true) { 'Enabled' } elseif ($cpu.VirtualizationEnabled -eq $false) { 'Disabled' } else { 'Unknown' }
    $base = if ($null -ne $cpu.BaseClockGHz) { "$($cpu.BaseClockGHz) GHz" } else { 'Unknown' }
    $arch = if ($cpu.Codename) {
        if ($cpu.GenerationLabel) { "$($cpu.Codename) ($($cpu.GenerationLabel))" } else { "$($cpu.Codename)" }
    } else { 'Unknown' }
    $cache = '{0} MB L2 / {1} MB L3' -f ($(if ($null -ne $cpu.L2CacheMB) { $cpu.L2CacheMB } else { '?' })), ($(if ($null -ne $cpu.L3CacheMB) { $cpu.L3CacheMB } else { '?' }))

    ''
    '  System Information'
    '  =================='
    ''
    '  Processor'
    '  ---------'
    '  Name             : {0}' -f $cpu.Name
    '  Cores / Threads  : {0} / {1}' -f $cpu.Cores, $cpu.Threads
    '  Base clock       : {0}' -f $base
    '  Cache            : {0}' -f $cache
    '  Architecture     : {0}' -f $arch
    '  Socket           : {0}' -f $cpu.Socket
    '  64-bit           : {0}' -f $(if ($cpu.Is64Bit) { 'Yes' } else { 'No' })
    '  Virtualization   : {0}' -f $virt
    '  Max memory speed : {0}' -f $maxSpeed
    ''
    '  Memory'
    '  ------'
    '  Total installed  : {0} GB  ({1})' -f $mem.TotalInstalledGB, $mem.TypeName
    '  Slots            : {0} used of {1}  ({2} free)' -f $mem.PopulatedSlots, $mem.TotalSlots, $mem.FreeSlots
    '  Max capacity     : {0}  (per firmware)' -f $maxCap
    '  Motherboard      : {0}' -f $mem.Board
    ''
    ($mem.Modules |
        Format-Table -AutoSize @{n='Slot';e={$_.Slot}},
                                @{n='Size(GB)';e={'{0:0.#}' -f $_.SizeGB}},
                                @{n='Rated';e={$_.Rated}},
                                @{n='Current';e={$_.Current}},
                                @{n='Maker';e={$_.Vendor}},
                                @{n='Part #';e={$_.Part}} |
        Out-String).TrimEnd()
    ''
    if (@($Report.Insights).Count -gt 0) {
        '  Notes'
        '  -----'
        foreach ($note in $Report.Insights) { "    - $($note.Text)" }
        ''
    }
}

function Add-KvBlock {
    # Add a two-column key/value label pair to a parent control; returns next Y.
    param($Parent, [string[]]$Keys, [string[]]$Values, [int]$X = 14, [int]$Y = 14, [int]$KeyW = 150, [int]$ValW = 404)
    $lblK = New-Object System.Windows.Forms.Label
    $lblK.Text = ($Keys -join "`r`n")
    $lblK.Location = New-Object System.Drawing.Point($X, $Y)
    $lblK.Size = New-Object System.Drawing.Size($KeyW, ($Keys.Count * 20 + 4))
    $lblK.Anchor = 'Top,Left'
    $Parent.Controls.Add($lblK)
    $lblV = New-Object System.Windows.Forms.Label
    $lblV.Text = ($Values -join "`r`n")
    $lblV.Location = New-Object System.Drawing.Point(($X + $KeyW), $Y)
    $lblV.Size = New-Object System.Drawing.Size($ValW, ($Values.Count * 20 + 4))
    $lblV.Anchor = 'Top,Left,Right'
    $Parent.Controls.Add($lblV)
    return ($Y + $Keys.Count * 20 + 8)
}

function New-SystemForm {
    # Tabbed WinForms window (Overview / CPU / Memory). Returns the form without
    # showing it, so it can be smoke-tested headlessly.
    param($Report)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $cpu = $Report.Cpu
    $mem = $Report.Memory
    $maxCap   = if ($null -ne $mem.MaxCapacityGB) { "$($mem.MaxCapacityGB) GB" } else { 'Unknown' }
    $maxSpeed = if ($cpu.MaxMemKnown) { $cpu.MaxMemLabel } else { 'Unknown - see CPU/board spec' }
    $virt = if ($cpu.VirtualizationEnabled -eq $true) { 'Enabled' } elseif ($cpu.VirtualizationEnabled -eq $false) { 'Disabled' } else { 'Unknown' }
    $arch = if ($cpu.Codename) {
        if ($cpu.GenerationLabel) { "$($cpu.Codename) ($($cpu.GenerationLabel))" } else { "$($cpu.Codename)" }
    } else { 'Unknown' }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'System Info'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(640, 620)
    $form.MinimumSize = New-Object System.Drawing.Size(560, 560)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(8, 8)
    $tabs.Size = New-Object System.Drawing.Size(616, 520)
    $tabs.Anchor = 'Top,Bottom,Left,Right'

    # --- Overview tab ---
    # Dock layout (header panel on top, notes filling the rest) so the notes box
    # always matches the tab width and word-wraps instead of overflowing.
    $tabOverview = New-Object System.Windows.Forms.TabPage
    $tabOverview.Text = 'Overview'
    $tabOverview.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)

    $ovTop = New-Object System.Windows.Forms.Panel
    $ovTop.Dock = 'Top'
    $ovTop.Height = 92
    $cpuLine = "$($cpu.Name)  -  $($cpu.Cores)C / $($cpu.Threads)T" + $(if ($cpu.Codename) { ", $($cpu.Codename)" } else { '' })
    $memLine = "$($mem.TotalInstalledGB) GB $($mem.TypeName)  -  $($mem.PopulatedSlots)/$($mem.TotalSlots) slots, max $maxCap"
    $oy = Add-KvBlock -Parent $ovTop -Keys @('Processor:', 'Memory:') -Values @($cpuLine, $memLine) -X 4 -Y 6 -KeyW 90 -ValW 460
    $notesHeader = New-Object System.Windows.Forms.Label
    $notesHeader.Text = 'Notes / Bottlenecks:'
    $notesHeader.Location = New-Object System.Drawing.Point(4, ($oy + 2))
    $notesHeader.AutoSize = $true
    $ovTop.Controls.Add($notesHeader)

    $notesBox = New-Object System.Windows.Forms.TextBox
    $notesBox.Multiline = $true; $notesBox.ReadOnly = $true; $notesBox.ScrollBars = 'Vertical'; $notesBox.WordWrap = $true
    $notesBox.BorderStyle = 'FixedSingle'
    $notesBox.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248)
    $notesBox.Dock = 'Fill'
    $notesBox.Text = if (@($Report.Insights).Count -gt 0) {
        (@($Report.Insights) | ForEach-Object { "- $($_.Text)" }) -join "`r`n`r`n"
    } else { '(no notes)' }

    $tabOverview.Controls.Add($notesBox)   # Fill added first so Top reserves its space
    $tabOverview.Controls.Add($ovTop)
    [void]$tabs.TabPages.Add($tabOverview)

    # --- CPU tab ---
    $tabCpu = New-Object System.Windows.Forms.TabPage
    $tabCpu.Text = 'CPU'
    $cpuKeys = @('Name:', 'Vendor:', 'Cores / Threads:', 'Base clock:', 'Cache:', 'Architecture:', 'Socket:', '64-bit:', 'Virtualization:', 'Max memory speed:')
    $cpuVals = @(
        $cpu.Name
        $cpu.Vendor
        "$($cpu.Cores) / $($cpu.Threads)"
        $(if ($null -ne $cpu.BaseClockGHz) { "$($cpu.BaseClockGHz) GHz" } else { 'Unknown' })
        "$(if ($null -ne $cpu.L2CacheMB) { $cpu.L2CacheMB } else { '?' }) MB L2 / $(if ($null -ne $cpu.L3CacheMB) { $cpu.L3CacheMB } else { '?' }) MB L3"
        $arch
        $cpu.Socket
        $(if ($cpu.Is64Bit) { 'Yes' } else { 'No' })
        $virt
        $maxSpeed
    )
    [void](Add-KvBlock -Parent $tabCpu -Keys $cpuKeys -Values $cpuVals -KeyW 150 -ValW 420)
    [void]$tabs.TabPages.Add($tabCpu)

    # --- Memory tab ---
    $tabMem = New-Object System.Windows.Forms.TabPage
    $tabMem.Text = 'Memory'
    $memKeys = @('Total installed:', 'Memory type:', 'Slots:', 'Max capacity:', 'Motherboard:')
    $memVals = @(
        "$($mem.TotalInstalledGB) GB"
        $mem.TypeName
        "$($mem.PopulatedSlots) used of $($mem.TotalSlots)  ($($mem.FreeSlots) free)"
        "$maxCap  (per firmware)"
        $mem.Board
    )
    $my = Add-KvBlock -Parent $tabMem -Keys $memKeys -Values $memVals -KeyW 130 -ValW 440
    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'; $list.FullRowSelect = $true; $list.GridLines = $true
    $list.Location = New-Object System.Drawing.Point(14, ($my + 4))
    $list.Size = New-Object System.Drawing.Size(572, (430 - $my))
    $list.Anchor = 'Top,Bottom,Left,Right'
    [void]$list.Columns.Add('Slot', 70)
    [void]$list.Columns.Add('Size (GB)', 70)
    [void]$list.Columns.Add('Rated', 65)
    [void]$list.Columns.Add('Current', 65)
    [void]$list.Columns.Add('Maker', 100)
    [void]$list.Columns.Add('Part #', 188)
    foreach ($m in $mem.Modules) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$m.Slot)
        [void]$item.SubItems.Add([string]$m.SizeGB)
        [void]$item.SubItems.Add([string]$m.Rated)
        [void]$item.SubItems.Add([string]$m.Current)
        [void]$item.SubItems.Add([string]$m.Vendor)
        [void]$item.SubItems.Add([string]$m.Part)
        [void]$list.Items.Add($item)
    }
    $tabMem.Controls.Add($list)
    $fillLastColumn = {
        $other = 0
        for ($idx = 0; $idx -lt ($list.Columns.Count - 1); $idx++) { $other += $list.Columns[$idx].Width }
        $fill = $list.ClientSize.Width - $other
        if ($fill -gt 120) { $list.Columns[$list.Columns.Count - 1].Width = $fill }
    }.GetNewClosure()
    $list.Add_Resize($fillLastColumn)
    & $fillLastColumn
    [void]$tabs.TabPages.Add($tabMem)

    $form.Controls.Add($tabs)

    # --- Buttons (below tabs, always visible) ---
    $btnCopy = New-Object System.Windows.Forms.Button
    $btnCopy.Text = 'Copy'
    $btnCopy.Size = New-Object System.Drawing.Size(90, 30)
    $btnCopy.Location = New-Object System.Drawing.Point(434, 540)
    $btnCopy.Anchor = 'Bottom,Right'
    $copyText = (Write-SystemConsole $Report | Out-String).Trim()
    $btnCopy.Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText($copyText); $btnCopy.Text = 'Copied!' }
        catch { $btnCopy.Text = 'Copy failed' }
    }.GetNewClosure())
    $form.Controls.Add($btnCopy)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Close'
    $btnClose.Size = New-Object System.Drawing.Size(90, 30)
    $btnClose.Location = New-Object System.Drawing.Point(534, 540)
    $btnClose.Anchor = 'Bottom,Right'
    $btnClose.Add_Click({ $form.Close() })
    $form.Controls.Add($btnClose)
    $form.AcceptButton = $btnClose

    return $form
}

function Show-SystemWindow {
    param($Report)
    $form = New-SystemForm $Report
    [void]$form.ShowDialog()
    $form.Dispose()
}

# =====================================================================
# Main
# =====================================================================

function Invoke-SystemInfo {
    param([switch]$Console)

    try {
        $modules = @(Get-RamModules)
        $array   = Get-RamArrayInfo
        $board   = Get-MotherboardInfo
        $cpuRaw  = Get-CpuInfo
    } catch {
        $err = "Couldn't read system info from Windows (CIM/WMI): $($_.Exception.Message)"
        if ($Console) { Write-Output $err; return }
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($err, 'System Info')
        } catch { Write-Output $err }
        return
    }

    $memory = New-MemoryReport -Modules $modules `
                               -MaxCapacityBytes $array.MaxCapacityBytes `
                               -TotalSlots $array.TotalSlots `
                               -BoardMaker $board.Maker `
                               -BoardModel $board.Model `
                               -BoardVersion $board.Version

    $cpu = New-CpuReport -Name $cpuRaw.Name `
                         -Cores $cpuRaw.Cores `
                         -Threads $cpuRaw.Threads `
                         -MaxClockMHz $cpuRaw.MaxClockMHz `
                         -L2CacheKB $cpuRaw.L2CacheKB `
                         -L3CacheKB $cpuRaw.L3CacheKB `
                         -Socket $cpuRaw.Socket `
                         -AddressWidth $cpuRaw.AddressWidth `
                         -VirtualizationEnabled $cpuRaw.VirtualizationEnabled `
                         -MemoryType $memory.TypeName

    $report = New-SystemReport -Cpu $cpu -Memory $memory

    if ($Console) { Write-SystemConsole $report; return }

    try {
        Show-SystemWindow $report
    } catch {
        Write-Output "(GUI unavailable - showing text. $($_.Exception.Message))"
        Write-SystemConsole $report
    }
}

if (-not $env:SYSTEMINFO_NOMAIN) {
    Invoke-SystemInfo -Console:$Console
}
