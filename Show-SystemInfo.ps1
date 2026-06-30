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

function Get-GpuType {
    # Classify a GPU as Integrated / Discrete / Unknown from its name + vendor.
    param([string]$Name, [string]$Vendor)
    $n = "$Name"; $v = "$Vendor"
    if ($v -match 'NVIDIA' -or $n -match 'NVIDIA|GeForce|Quadro|Tesla|RTX|GTX') { return 'Discrete' }
    if ($n -match '\bArc\b') { return 'Discrete' }                       # Intel Arc
    if ($v -match 'Intel' -or $n -match 'Intel|UHD|Iris|HD Graphics')    { return 'Integrated' }
    if ($n -match 'Radeon RX|Radeon Pro|FirePro|Radeon VII')            { return 'Discrete' }
    if ($v -match 'AMD|Advanced Micro' -or $n -match 'Radeon|Vega')      { return 'Integrated' }
    return 'Unknown'
}

function New-GpuReport {
    # Build the Graphics section from raw per-GPU data (no CIM/registry here).
    param([object[]] $Gpus = @(), [object] $Now = $null)
    $nowDate = if ($Now -is [datetime]) { $Now } else { Get-Date }

    $list = @(foreach ($g in $Gpus) {
        $vramBytes = $null; $src = 'unknown'
        if ($null -ne $g.RegistryVramBytes -and [double]$g.RegistryVramBytes -gt 0) { $vramBytes = [double]$g.RegistryVramBytes; $src = 'registry' }
        elseif ($null -ne $g.AdapterRamBytes -and [double]$g.AdapterRamBytes -gt 0)  { $vramBytes = [double]$g.AdapterRamBytes;  $src = 'adapterRAM' }
        $vramGB = if ($null -ne $vramBytes) { [math]::Round($vramBytes / 1GB, 1) } else { $null }

        $type   = Get-GpuType -Name $g.Name -Vendor $g.Vendor
        $status = switch ([int]$g.Availability) { 3 { 'Active' } 8 { 'Idle' } default { 'Unknown' } }
        $res    = if ($g.ResH -and [int]$g.ResH -gt 0) { "$([int]$g.ResH)x$([int]$g.ResV)@$([int]$g.ResRefresh)" } else { '-' }
        $age    = if ($g.DriverDate -is [datetime]) { ($nowDate.Year - $g.DriverDate.Year) * 12 + ($nowDate.Month - $g.DriverDate.Month) } else { $null }

        [pscustomobject]@{
            Name            = "$($g.Name)".Trim()
            Vendor          = "$($g.Vendor)".Trim()
            Type            = $type
            VramGB          = $vramGB
            VramSource      = $src
            DriverVersion   = "$($g.DriverVersion)".Trim()
            DriverDate      = $g.DriverDate
            DriverAgeMonths = $age
            Status          = $status
            IsActive        = ([int]$g.Availability -eq 3)
            IsDiscrete      = ($type -eq 'Discrete')
            Resolution      = $res
        }
    })
    [pscustomobject]@{ Gpus = $list }
}

function Get-DiskKind {
    # Classify a disk as NVMe SSD / SATA SSD / HDD / Unknown. Detects NVMe from
    # the name too, since Intel RST exposes NVMe drives with BusType 'RAID'.
    param([string]$Name, [string]$MediaType, [string]$BusType)
    $isNvme = ($BusType -match 'NVMe') -or ($Name -match 'NVMe')
    $isSsd  = ($MediaType -match 'SSD') -or ("$MediaType" -eq '4')
    $isHdd  = ($MediaType -match 'HDD') -or ("$MediaType" -eq '3')
    if ($isSsd)  { return $(if ($isNvme) { 'NVMe SSD' } else { 'SATA SSD' }) }
    if ($isHdd)  { return 'HDD' }
    if ($isNvme) { return 'NVMe SSD' }
    return 'Unknown'
}

function New-StorageReport {
    # Build the Storage section from raw disk + volume data (no cmdlets here).
    param([object[]] $Disks = @(), [object[]] $Volumes = @())

    $diskList = @(foreach ($d in $Disks) {
        [pscustomobject]@{
            Name      = "$($d.Name)".Trim()
            Kind      = Get-DiskKind -Name $d.Name -MediaType $d.MediaType -BusType $d.BusType
            SizeGB    = if ($d.SizeBytes) { [math]::Round([double]$d.SizeBytes / 1GB, 0) } else { $null }
            Health    = if ([string]::IsNullOrWhiteSpace($d.Health)) { 'Unknown' } else { "$($d.Health)".Trim() }
            IsBoot    = [bool]$d.IsBoot
            MediaType = "$($d.MediaType)"
            Bus       = "$($d.BusType)"
        }
    })

    $volList = @(foreach ($v in $Volumes) {
        $pct = if ($v.SizeBytes -and [double]$v.SizeBytes -gt 0) { [math]::Round([double]$v.FreeBytes / [double]$v.SizeBytes * 100, 0) } else { $null }
        [pscustomobject]@{
            DriveLetter = "$($v.DriveLetter)".Trim()
            Label       = "$($v.Label)".Trim()
            FileSystem  = "$($v.FileSystem)".Trim()
            SizeGB      = if ($v.SizeBytes) { [math]::Round([double]$v.SizeBytes / 1GB, 1) } else { $null }
            FreeGB      = if ($v.FreeBytes) { [math]::Round([double]$v.FreeBytes / 1GB, 1) } else { $null }
            FreePercent = $pct
        }
    })

    [pscustomobject]@{ Disks = $diskList; Volumes = $volList }
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

function Get-GpuInsights {
    # GPU-only notes from the Graphics section.
    param([object] $Gpu)
    $notes = @()
    foreach ($g in $Gpu.Gpus) {
        if ($g.IsDiscrete -and -not $g.IsActive) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "$($g.Name) is present but idle; apps may default to the integrated GPU. For demanding work, select it in Windows Graphics settings or the vendor control panel." }
        }
    }
    foreach ($g in $Gpu.Gpus) {
        if ($null -ne $g.DriverAgeMonths -and [int]$g.DriverAgeMonths -gt 12) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "$($g.Name) driver is ~$($g.DriverAgeMonths) months old; consider updating." }
        }
    }
    return , @($notes)
}

function Get-StorageInsights {
    # Storage health/space notes from the Storage section.
    param([object] $Storage)
    $notes = @()
    foreach ($d in $Storage.Disks) {
        if ($d.IsBoot -and $d.Kind -eq 'HDD') {
            $notes += [pscustomobject]@{ Kind = 'warn'; Text = 'Windows is installed on a mechanical hard drive - the single biggest slowdown on an otherwise capable PC. Moving to an SSD would transform responsiveness.' }
        }
        if ($d.IsBoot -and $d.Kind -eq 'SATA SSD') {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "Boot drive ($($d.Name)) is a SATA SSD; an NVMe SSD is several times faster if your system has an M.2 NVMe slot." }
        }
        if (-not [string]::IsNullOrWhiteSpace($d.Health) -and $d.Health -ne 'Healthy' -and $d.Health -ne 'Unknown') {
            $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Disk $($d.Name) reports health '$($d.Health)' - back up your data and run a check (e.g. CrystalDiskInfo or the maker's tool)." }
        }
    }
    foreach ($v in $Storage.Volumes) {
        if ($null -ne $v.FreePercent -and ([double]$v.FreePercent -lt 10 -or [double]$v.FreeGB -lt 25)) {
            $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Drive $($v.DriveLetter): is low on space ($($v.FreeGB) GB free, $($v.FreePercent)%). Free up space - drives slow down and Windows struggles when nearly full." }
        }
    }
    return , @($notes)
}

function Get-SystemInsights {
    # Orchestrator: per-subsystem notes plus cross-subsystem bottleneck notes.
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null)
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
    if ($null -ne $Gpu) {
        $gpuNotes = Get-GpuInsights -Gpu $Gpu
        $notes += $gpuNotes
    }
    if ($null -ne $Storage) {
        $storageNotes = Get-StorageInsights -Storage $Storage
        $notes += $storageNotes
    }

    # Cross note: many cores starved by single-channel memory bandwidth.
    if ($Memory.PopulatedSlots -eq 1 -and $Memory.TotalSlots -ge 2 -and $null -ne $Cpu.Cores -and [int]$Cpu.Cores -ge 6) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "$($Cpu.Cores) cores share single-channel memory bandwidth; moving to dual-channel would noticeably help multi-core workloads." }
    }

    # Cross note: integrated graphics starved by single-channel memory.
    if ($null -ne $Gpu -and $Memory.PopulatedSlots -eq 1 -and $Memory.TotalSlots -ge 2 -and
        @($Gpu.Gpus | Where-Object { $_.Type -eq 'Integrated' }).Count -gt 0) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = 'Integrated graphics share system memory; single-channel RAM notably limits iGPU performance - dual-channel would help.' }
    }

    return , @(@($notes) | Where-Object { $null -ne $_ })
}

# =====================================================================
# System report composer (pure)
# =====================================================================

function New-SystemReport {
    # Compose the subsystem sections and run the insight engine.
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null)
    $insights = Get-SystemInsights -Cpu $Cpu -Memory $Memory -Gpu $Gpu -Storage $Storage
    [pscustomobject]@{
        Cpu      = $Cpu
        Memory   = $Memory
        Gpu      = $Gpu
        Storage  = $Storage
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

function Get-GpuVramMap {
    # Map GPU DriverDesc -> dedicated VRAM bytes from the registry. This is the
    # accurate source; Win32_VideoController.AdapterRAM is a 32-bit field capped
    # at ~4 GB. Read-only HKLM access, no admin needed.
    $map = @{}
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    try {
        Get-ChildItem $base -ErrorAction Stop | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            $sz = $p.'HardwareInformation.qwMemorySize'
            if ($p -and $p.DriverDesc -and $sz) {
                $bytes = if ($sz -is [byte[]]) { [System.BitConverter]::ToUInt64($sz, 0) } else { [int64]$sz }
                if ($bytes -gt 0) { $map["$($p.DriverDesc)"] = $bytes }
            }
        }
    } catch { }
    return $map
}

function Get-GpuInfo {
    $vramMap = Get-GpuVramMap
    Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        $regVram = if ($vramMap.ContainsKey("$($_.Name)")) { $vramMap["$($_.Name)"] } else { $null }
        [pscustomobject]@{
            Name              = $_.Name
            Vendor            = $_.AdapterCompatibility
            AdapterRamBytes   = $_.AdapterRAM
            RegistryVramBytes = $regVram
            DriverVersion     = $_.DriverVersion
            DriverDate        = $_.DriverDate
            Availability      = $_.Availability
            ResH              = $_.CurrentHorizontalResolution
            ResV              = $_.CurrentVerticalResolution
            ResRefresh        = $_.CurrentRefreshRate
        }
    }
}

function Get-StorageInfo {
    # Physical disks (+ which is the boot disk) and volumes, via the Storage
    # cmdlets. Wrapped so a missing module degrades gracefully.
    $disks = @(); $vols = @()
    try {
        $bootNums = @(Get-Disk -ErrorAction Stop | Where-Object { $_.IsBoot } | ForEach-Object { "$($_.Number)" })
        $disks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Name      = $_.FriendlyName
                MediaType = "$($_.MediaType)"
                BusType   = "$($_.BusType)"
                SizeBytes = $_.Size
                Health    = "$($_.HealthStatus)"
                IsBoot    = ($bootNums -contains "$($_.DeviceId)")
            }
        })
        $vols = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter } | ForEach-Object {
            [pscustomobject]@{
                DriveLetter = $_.DriveLetter
                Label       = $_.FileSystemLabel
                FileSystem  = $_.FileSystemType
                SizeBytes   = $_.Size
                FreeBytes   = $_.SizeRemaining
            }
        })
    } catch { }
    [pscustomobject]@{ Disks = $disks; Volumes = $vols }
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
    if ($Report.Gpu -and @($Report.Gpu.Gpus).Count -gt 0) {
        '  Graphics'
        '  --------'
        ($Report.Gpu.Gpus |
            Format-Table -AutoSize @{n='GPU';e={$_.Name}},
                                    @{n='Vendor';e={$_.Vendor}},
                                    @{n='Type';e={$_.Type}},
                                    @{n='VRAM';e={ if ($null -ne $_.VramGB) { "$($_.VramGB) GB" } else { 'Unknown' } }},
                                    @{n='Driver';e={$_.DriverVersion}},
                                    @{n='Status';e={$_.Status}} |
            Out-String).TrimEnd()
        ''
    }
    if ($Report.Storage -and (@($Report.Storage.Disks).Count -gt 0 -or @($Report.Storage.Volumes).Count -gt 0)) {
        '  Storage'
        '  -------'
        if (@($Report.Storage.Disks).Count -gt 0) {
            ($Report.Storage.Disks |
                Format-Table -AutoSize @{n='Disk';e={$_.Name}},
                                        @{n='Type';e={$_.Kind}},
                                        @{n='Size';e={ if ($null -ne $_.SizeGB) { "$($_.SizeGB) GB" } else { '?' } }},
                                        @{n='Health';e={$_.Health}},
                                        @{n='Boot';e={ if ($_.IsBoot) { 'Yes' } else { '' } }} |
                Out-String).TrimEnd()
        }
        if (@($Report.Storage.Volumes).Count -gt 0) {
            ($Report.Storage.Volumes |
                Format-Table -AutoSize @{n='Drive';e={"$($_.DriveLetter):"}},
                                        @{n='Label';e={$_.Label}},
                                        @{n='FS';e={$_.FileSystem}},
                                        @{n='Size';e={ if ($null -ne $_.SizeGB) { "$($_.SizeGB) GB" } else { '?' } }},
                                        @{n='Free';e={ if ($null -ne $_.FreeGB) { "$($_.FreeGB) GB" } else { '?' } }},
                                        @{n='Free%';e={ if ($null -ne $_.FreePercent) { "$($_.FreePercent)%" } else { '?' } }} |
                Out-String).TrimEnd()
        }
        ''
    }
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
    $gpu = $Report.Gpu
    $st  = $Report.Storage
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
    $ovTop.Height = 134
    $cpuLine = "$($cpu.Name)  -  $($cpu.Cores)C / $($cpu.Threads)T" + $(if ($cpu.Codename) { ", $($cpu.Codename)" } else { '' })
    $memLine = "$($mem.TotalInstalledGB) GB $($mem.TypeName)  -  $($mem.PopulatedSlots)/$($mem.TotalSlots) slots, max $maxCap"
    $gpuParts = @()
    if ($null -ne $gpu) { foreach ($g in $gpu.Gpus) { $vr = if ($null -ne $g.VramGB) { " ($($g.VramGB) GB)" } else { '' }; $gpuParts += "$($g.Name)$vr" } }
    $gpuLine = if ($gpuParts.Count) { $gpuParts -join '  +  ' } else { 'None detected' }
    $bootDisk = if ($null -ne $st) { @($st.Disks | Where-Object { $_.IsBoot }) | Select-Object -First 1 } else { $null }
    $sysVol   = if ($null -ne $st) { @($st.Volumes | Where-Object { $_.DriveLetter -eq 'C' }) | Select-Object -First 1 } else { $null }
    $storageLine = if ($bootDisk) {
        "$($bootDisk.SizeGB) GB $($bootDisk.Kind)" + $(if ($sysVol) { "  -  $($sysVol.FreeGB) GB free on $($sysVol.DriveLetter):" } else { '' })
    } elseif ($null -ne $st -and @($st.Disks).Count) { "$(@($st.Disks).Count) disk(s)" } else { 'Unknown' }
    $oy = Add-KvBlock -Parent $ovTop -Keys @('Processor:', 'Graphics:', 'Memory:', 'Storage:') -Values @($cpuLine, $gpuLine, $memLine, $storageLine) -X 4 -Y 6 -KeyW 90 -ValW 460
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

    # --- GPU tab ---
    $tabGpu = New-Object System.Windows.Forms.TabPage
    $tabGpu.Text = 'GPU'
    $tabGpu.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
    $glist = New-Object System.Windows.Forms.ListView
    $glist.View = 'Details'; $glist.FullRowSelect = $true; $glist.GridLines = $true; $glist.Dock = 'Fill'
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
    $tabGpu.Controls.Add($glist)
    # Let the GPU-name column (the primary identifier) absorb the slack width.
    $gFill = {
        $other = 0
        for ($idx = 1; $idx -lt $glist.Columns.Count; $idx++) { $other += $glist.Columns[$idx].Width }
        $f = $glist.ClientSize.Width - $other
        if ($f -gt 150) { $glist.Columns[0].Width = $f }
    }.GetNewClosure()
    $glist.Add_Resize($gFill)
    & $gFill
    [void]$tabs.TabPages.Add($tabGpu)

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

    # --- Storage tab (disks table on top, volumes table below) ---
    $tabStorage = New-Object System.Windows.Forms.TabPage
    $tabStorage.Text = 'Storage'
    $tabStorage.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)

    $diskPanel = New-Object System.Windows.Forms.Panel
    $diskPanel.Dock = 'Top'; $diskPanel.Height = 150
    $diskLbl = New-Object System.Windows.Forms.Label
    $diskLbl.Text = 'Disks'; $diskLbl.Dock = 'Top'; $diskLbl.Height = 18
    $diskList = New-Object System.Windows.Forms.ListView
    $diskList.View = 'Details'; $diskList.FullRowSelect = $true; $diskList.GridLines = $true; $diskList.Dock = 'Fill'
    [void]$diskList.Columns.Add('Disk', 230)
    [void]$diskList.Columns.Add('Type', 90)
    [void]$diskList.Columns.Add('Size', 80)
    [void]$diskList.Columns.Add('Health', 80)
    [void]$diskList.Columns.Add('Boot', 50)
    if ($null -ne $st) {
        foreach ($d in $st.Disks) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$d.Name)
            [void]$item.SubItems.Add([string]$d.Kind)
            [void]$item.SubItems.Add($(if ($null -ne $d.SizeGB) { "$($d.SizeGB) GB" } else { '?' }))
            [void]$item.SubItems.Add([string]$d.Health)
            [void]$item.SubItems.Add($(if ($d.IsBoot) { 'Yes' } else { '' }))
            [void]$diskList.Items.Add($item)
        }
    }
    $diskPanel.Controls.Add($diskList)
    $diskPanel.Controls.Add($diskLbl)
    $dFill = { $o = 0; for ($i = 1; $i -lt $diskList.Columns.Count; $i++) { $o += $diskList.Columns[$i].Width }; $f = $diskList.ClientSize.Width - $o; if ($f -gt 150) { $diskList.Columns[0].Width = $f } }.GetNewClosure()
    $diskList.Add_Resize($dFill); & $dFill

    $volLbl = New-Object System.Windows.Forms.Label
    $volLbl.Text = 'Volumes'; $volLbl.Dock = 'Top'; $volLbl.Height = 18
    $volList = New-Object System.Windows.Forms.ListView
    $volList.View = 'Details'; $volList.FullRowSelect = $true; $volList.GridLines = $true; $volList.Dock = 'Fill'
    [void]$volList.Columns.Add('Drive', 60)
    [void]$volList.Columns.Add('Label', 150)
    [void]$volList.Columns.Add('FS', 70)
    [void]$volList.Columns.Add('Size', 90)
    [void]$volList.Columns.Add('Free', 90)
    [void]$volList.Columns.Add('Free %', 60)
    if ($null -ne $st) {
        foreach ($v in $st.Volumes) {
            $item = New-Object System.Windows.Forms.ListViewItem("$($v.DriveLetter):")
            [void]$item.SubItems.Add([string]$v.Label)
            [void]$item.SubItems.Add([string]$v.FileSystem)
            [void]$item.SubItems.Add($(if ($null -ne $v.SizeGB) { "$($v.SizeGB) GB" } else { '?' }))
            [void]$item.SubItems.Add($(if ($null -ne $v.FreeGB) { "$($v.FreeGB) GB" } else { '?' }))
            [void]$item.SubItems.Add($(if ($null -ne $v.FreePercent) { "$($v.FreePercent)%" } else { '?' }))
            [void]$volList.Items.Add($item)
        }
    }
    $vFill = { $o = 0; for ($i = 0; $i -lt $volList.Columns.Count; $i++) { if ($i -ne 1) { $o += $volList.Columns[$i].Width } }; $f = $volList.ClientSize.Width - $o; if ($f -gt 100) { $volList.Columns[1].Width = $f } }.GetNewClosure()
    $volList.Add_Resize($vFill); & $vFill

    $tabStorage.Controls.Add($volList)    # Fill (innermost)
    $tabStorage.Controls.Add($volLbl)     # Top
    $tabStorage.Controls.Add($diskPanel)  # Top (outermost = very top)
    [void]$tabs.TabPages.Add($tabStorage)

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
        $gpuRaw  = @(Get-GpuInfo)
        $stRaw   = Get-StorageInfo
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

    $gpu = New-GpuReport -Gpus $gpuRaw -Now (Get-Date)
    $storage = New-StorageReport -Disks $stRaw.Disks -Volumes $stRaw.Volumes

    $report = New-SystemReport -Cpu $cpu -Memory $memory -Gpu $gpu -Storage $storage

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
