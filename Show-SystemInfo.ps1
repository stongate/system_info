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
            ResWidth        = if ($g.ResH -and [int]$g.ResH -gt 0) { [int]$g.ResH } else { $null }
            ResHeight       = if ($g.ResV -and [int]$g.ResV -gt 0) { [int]$g.ResV } else { $null }
            RefreshHz       = if ($g.ResRefresh -and [int]$g.ResRefresh -gt 0) { [int]$g.ResRefresh } else { $null }
        }
    })
    [pscustomobject]@{ Gpus = $list }
}

function Get-GpuGamingTier {
    # Coarse, best-effort gaming tier for a GPU name (generation-level; refreshed
    # from 2026 GPU hierarchies). Ordered highest-rank-first; first match wins.
    # Returns { Rank (5..1 or $null); Label }. The precise value is the limiters,
    # not this bucket.
    param([string] $Name)
    $out = [pscustomobject]@{ Rank = $null; Label = 'Unrecognized' }
    if ([string]::IsNullOrWhiteSpace($Name)) { return $out }
    $rules = @(
        @{ r = 'RTX\s*(5090|5080|4090|4080)\b'; k = 5 }
        @{ r = 'RX\s*(9070\s*XT|7900\s*XTX)'; k = 5 }
        @{ r = 'RTX\s*(5070|4070|3090|3080)\b'; k = 4 }
        @{ r = 'RX\s*(9070|7900|7800|6900|6800)\b'; k = 4 }
        @{ r = 'RTX\s*(5060|4060|3070|3060|2080|2070|2060)\b'; k = 3 }
        @{ r = 'RX\s*(9060|7700|7600|6750|6700|6650|6600)\b'; k = 3 }
        @{ r = 'Arc\s*(B580|A770|A750)\b'; k = 3 }
        @{ r = 'RTX\s*(5050|3050)\b'; k = 2 }
        @{ r = 'GTX\s*(1660|1650|1080|1070|1060)\b'; k = 2 }
        @{ r = 'RX\s*(5700|5600|590|580)\b'; k = 2 }
        @{ r = 'Arc\s*(B570|A580|A380)\b'; k = 2 }
        @{ r = 'GTX\s*(1050|1030)\b|\bMX\d'; k = 1 }
        @{ r = 'RX\s*(570|560|550)\b|Vega'; k = 1 }
        @{ r = 'Iris|UHD|HD\s*Graphics|Radeon.*Graphics'; k = 1 }
    )
    $labels = @{
        5 = '4K ultra / max settings'
        4 = '1440p ultra / entry 4K'
        3 = '1080p high / 1440p mainstream'
        2 = '1080p mainstream / esports'
        1 = 'esports / light 1080p (integrated-class)'
    }
    foreach ($rule in $rules) {
        if ($Name -match $rule.r) {
            $out.Rank = $rule.k
            $out.Label = $labels[$rule.k]
            return $out
        }
    }
    return $out
}

function New-GamingReport {
    # Synthesize a gaming-capability verdict + named limiters from the already-
    # built subsystem sections (pure; no I/O). Picks the gaming GPU (first
    # discrete, else first) and the display (first GPU reporting a refresh).
    param([object] $Gpu, [object] $Cpu, [object] $Memory, [object] $Storage)
    $gpus = @($Gpu.Gpus)
    $gamingGpu = @($gpus | Where-Object { $_.IsDiscrete }) | Select-Object -First 1
    if (-not $gamingGpu) { $gamingGpu = $gpus | Select-Object -First 1 }
    $display = @($gpus | Where-Object { $null -ne $_.RefreshHz }) | Select-Object -First 1

    $tier       = if ($gamingGpu) { Get-GpuGamingTier -Name $gamingGpu.Name } else { [pscustomobject]@{ Rank = $null; Label = 'Unrecognized' } }
    $vram       = if ($gamingGpu) { $gamingGpu.VramGB } else { $null }
    $isDiscrete = if ($gamingGpu) { [bool]$gamingGpu.IsDiscrete } else { $false }
    $cores      = if ($Cpu) { $Cpu.Cores } else { $null }
    $ramGB      = if ($Memory) { $Memory.TotalInstalledGB } else { $null }
    $dual       = if ($Memory) { [int]$Memory.PopulatedSlots -ge 2 } else { $false }
    $refresh    = if ($display) { $display.RefreshHz } else { $null }
    $dispW      = if ($display) { $display.ResWidth } else { $null }
    $dispH      = if ($display) { $display.ResHeight } else { $null }
    $bootKind   = $null
    if ($Storage) { $bd = @($Storage.Disks | Where-Object { $_.IsBoot }) | Select-Object -First 1; if ($bd) { $bootKind = $bd.Kind } }

    $verdict = if ($null -ne $tier.Rank) { $tier.Label } else { 'Unrecognized GPU (not in our tier list)' }

    $limiters = @()
    if (-not $isDiscrete) { $limiters += 'no discrete GPU' }
    elseif ($null -ne $vram -and [double]$vram -lt 8) { $limiters += "$vram GB VRAM" }
    if ($null -ne $ramGB -and [double]$ramGB -lt 16) { $limiters += "$ramGB GB RAM" }
    if (-not $dual) { $limiters += 'single-channel RAM' }
    if ($null -ne $refresh -and [int]$refresh -le 60) { $limiters += "$refresh Hz display" }
    if ($bootKind -eq 'HDD') { $limiters += 'HDD boot drive' }

    [pscustomobject]@{
        GpuName     = if ($gamingGpu) { $gamingGpu.Name } else { $null }
        Rank        = $tier.Rank
        TierLabel   = $tier.Label
        Verdict     = $verdict
        VramGB      = $vram
        IsDiscrete  = $isDiscrete
        Cores       = $cores
        RamGB       = $ramGB
        DualChannel = $dual
        DisplayW    = $dispW
        DisplayH    = $dispH
        RefreshHz   = $refresh
        BootKind    = $bootKind
        Limiters    = $limiters
    }
}

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

function ConvertFrom-BatteryReportXml {
    # Pure parse of `powercfg /batteryreport /xml` text. Reads the first
    # Batteries/Battery node specifically: a bare //DesignCapacity also matches
    # the RuntimeEstimates node, whose InnerText is '95065PT4H33M44S...'.
    param([string] $Xml)
    $out = [pscustomobject]@{
        DesignCapacityMWh = $null; FullChargeCapacityMWh = $null; CycleCount = $null
        Chemistry = $null; Manufacturer = $null; SerialNumber = $null
    }
    if ([string]::IsNullOrWhiteSpace($Xml)) { return $out }
    try { $doc = [xml]$Xml } catch { return $out }
    if ($null -eq $doc.DocumentElement) { return $out }
    $ns = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
    $ns.AddNamespace('b', $doc.DocumentElement.NamespaceURI)
    $batt = $doc.SelectSingleNode('//b:Batteries/b:Battery', $ns)
    if ($null -eq $batt) { return $out }

    function _txt($node, $nsm, $name) {
        $n = $node.SelectSingleNode("b:$name", $nsm)
        if ($n -and -not [string]::IsNullOrWhiteSpace($n.InnerText)) { return $n.InnerText.Trim() }
        return $null
    }
    function _int($node, $nsm, $name) {
        $t = _txt $node $nsm $name
        $v = 0
        if ($null -ne $t -and [int]::TryParse($t, [ref]$v)) { return $v }
        return $null
    }
    $out.DesignCapacityMWh     = _int $batt $ns 'DesignCapacity'
    $out.FullChargeCapacityMWh = _int $batt $ns 'FullChargeCapacity'
    $out.CycleCount            = _int $batt $ns 'CycleCount'
    $out.Chemistry             = _txt $batt $ns 'Chemistry'
    $out.Manufacturer          = _txt $batt $ns 'Manufacturer'
    $out.SerialNumber          = _txt $batt $ns 'SerialNumber'
    return $out
}

function ConvertFrom-ActiveScheme {
    # Pure parse of `powercfg /getactivescheme` output, e.g.
    #   'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)'
    param([string] $Text)
    $out = [pscustomobject]@{ Guid = $null; Name = $null }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $out }
    $g = [regex]::Match($Text, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if ($g.Success) { $out.Guid = $g.Value }
    $n = [regex]::Match($Text, '\(([^)]*)\)')
    if ($n.Success) { $out.Name = $n.Groups[1].Value.Trim() }
    return $out
}

function ConvertTo-BatteryChemistry {
    # Friendly name for a battery-report chemistry code; unknown codes pass through.
    param([string] $Code)
    if ([string]::IsNullOrWhiteSpace($Code)) { return 'Unknown' }
    switch ($Code.Trim().ToUpperInvariant()) {
        'LIP'  { 'Lithium Polymer' }
        'LI-P' { 'Lithium Polymer' }
        'LION' { 'Lithium-ion' }
        'LI-I' { 'Lithium-ion' }
        'LI'   { 'Lithium-ion' }
        'NIMH' { 'Nickel-Metal Hydride' }
        'NICD' { 'Nickel-Cadmium' }
        'PBAC' { 'Lead Acid' }
        default { $Code.Trim() }
    }
}

function New-BatteryReport {
    # Build the Battery section (pure). Non-deterministic/live values are params.
    param(
        $ChargePercent = $null,
        $IsOnAC = $null,
        $IsCharging = $null,
        $DesignCapacityMWh = $null,
        $FullChargeCapacityMWh = $null,
        $CycleCount = $null,
        [string] $Chemistry = '',
        [string] $Manufacturer = '',
        [string] $PowerPlan = '',
        [string] $PowerPlanGuid = ''
    )
    $design = if ($DesignCapacityMWh) { [double]$DesignCapacityMWh } else { $null }
    $full   = if ($FullChargeCapacityMWh) { [double]$FullChargeCapacityMWh } else { $null }

    $wear = $null; $health = $null
    if ($null -ne $design -and $design -gt 0 -and $null -ne $full) {
        $w = [int][math]::Round(($design - $full) / $design * 100, 0)
        if ($w -lt 0) { $w = 0 } elseif ($w -gt 100) { $w = 100 }
        $wear = $w
        $health = 100 - $w
    }

    $charge = if ($null -ne $ChargePercent -and "$ChargePercent" -ne '') { [int]$ChargePercent } else { $null }
    $status =
        if ($IsOnAC -eq $false) { 'On battery (discharging)' }
        elseif ($IsOnAC -eq $true) {
            if ($IsCharging -eq $true) { 'Charging' }
            elseif ($null -ne $charge -and $charge -ge 99) { 'Fully charged (on AC)' }
            else { 'On AC (not charging)' }
        } else { 'Unknown' }

    $cycles = if ($CycleCount -and [int]$CycleCount -gt 0) { [int]$CycleCount } else { $null }

    [pscustomobject]@{
        ChargePercent         = $charge
        IsOnAC                = $(if ($IsOnAC -eq $true) { $true } elseif ($IsOnAC -eq $false) { $false } else { $null })
        Status                = $status
        DesignCapacityMWh     = $(if ($null -ne $design) { [int]$design } else { $null })
        FullChargeCapacityMWh = $(if ($null -ne $full) { [int]$full } else { $null })
        WearPercent           = $wear
        HealthPercent         = $health
        CycleCount            = $cycles
        Chemistry             = ConvertTo-BatteryChemistry $Chemistry
        Manufacturer          = "$Manufacturer".Trim()
        PowerPlan             = "$PowerPlan".Trim()
        PowerPlanGuid         = "$PowerPlanGuid".Trim()
    }
}

function New-LoadReport {
    # Build the Live/Load section (pure) from raw live memory counters.
    param(
        $TotalPhysicalBytes = $null,
        $AvailableBytes = $null,
        $CommittedBytes = $null,
        $CommitLimitBytes = $null,
        $PercentCommitted = $null,
        $PageReadsPerSec = $null
    )
    $toGB = { param($b) if ($b) { [math]::Round([double]$b / 1GB, 1) } else { $null } }

    $availPct = if ($TotalPhysicalBytes -and [double]$TotalPhysicalBytes -gt 0 -and $null -ne $AvailableBytes) {
        [int][math]::Round([double]$AvailableBytes / [double]$TotalPhysicalBytes * 100, 0)
    } else { $null }

    $commitPct =
        if ($null -ne $PercentCommitted -and "$PercentCommitted" -ne '') { [int]$PercentCommitted }
        elseif ($CommitLimitBytes -and [double]$CommitLimitBytes -gt 0 -and $null -ne $CommittedBytes) {
            [int][math]::Round([double]$CommittedBytes / [double]$CommitLimitBytes * 100, 0)
        } else { $null }

    [pscustomobject]@{
        TotalPhysicalGB  = & $toGB $TotalPhysicalBytes
        AvailableGB      = & $toGB $AvailableBytes
        AvailablePercent = $availPct
        CommitUsedGB     = & $toGB $CommittedBytes
        CommitLimitGB    = & $toGB $CommitLimitBytes
        CommitPercent    = $commitPct
        PageReadsPerSec  = if ($null -ne $PageReadsPerSec -and "$PageReadsPerSec" -ne '') { [int]$PageReadsPerSec } else { $null }
    }
}

function ConvertFrom-NetshWlan {
    # Pure parse of `netsh wlan show interfaces` text (first connected interface).
    # English-label regex; missing labels -> $null (best-effort on other locales).
    param([string] $Text)
    $out = [pscustomobject]@{ State = $null; Band = $null; RadioType = $null; SignalPercent = $null; ReceiveMbps = $null; TransmitMbps = $null }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $out }

    function _m($text, $pat) {
        $r = [regex]::Match($text, $pat)
        if ($r.Success) { return $r.Groups[1].Value.Trim() }
        return $null
    }
    function _num($text, $pat) {
        $t = _m $text $pat
        if ($null -ne $t) { return [int][math]::Round([double]$t) }
        return $null
    }
    $out.State        = _m   $Text 'State\s*:\s*(.+)'
    $out.Band         = _m   $Text 'Band\s*:\s*(.+)'
    $out.RadioType    = _m   $Text 'Radio type\s*:\s*(.+)'
    $out.SignalPercent = _num $Text 'Signal\s*:\s*(\d+)'
    $out.ReceiveMbps  = _num $Text 'Receive rate \(Mbps\)\s*:\s*([\d.]+)'
    $out.TransmitMbps = _num $Text 'Transmit rate \(Mbps\)\s*:\s*([\d.]+)'
    return $out
}

function ConvertTo-MaxLinkMbps {
    # Highest link speed (Mbps) from an Ethernet 'Speed & Duplex' valid-values
    # list, e.g. '1.0 Gbps Full Duplex' -> 1000. $null if none parse.
    param([string[]] $ValidValues = @())
    $best = $null
    foreach ($v in $ValidValues) {
        $mbps = $null
        $g = [regex]::Match($v, '([\d.]+)\s*Gbps')
        $mb = [regex]::Match($v, '([\d.]+)\s*Mbps')
        if ($g.Success) { $mbps = [int][math]::Round([double]$g.Groups[1].Value * 1000) }
        elseif ($mb.Success) { $mbps = [int][math]::Round([double]$mb.Groups[1].Value) }
        if ($null -ne $mbps -and ($null -eq $best -or $mbps -gt $best)) { $best = $mbps }
    }
    return $best
}

function ConvertTo-WifiStandard {
    # Friendly Wi-Fi generation for a netsh radio type; unknown -> raw value.
    param([string] $RadioType)
    if ([string]::IsNullOrWhiteSpace($RadioType)) { return $null }
    $r = $RadioType.Trim()
    switch -Regex ($r) {
        '802\.11be' { "Wi-Fi 7 ($r)"; break }
        '802\.11ax' { "Wi-Fi 6 ($r)"; break }
        '802\.11ac' { "Wi-Fi 5 ($r)"; break }
        '802\.11n'  { "Wi-Fi 4 ($r)"; break }
        default     { $r }
    }
}

function New-NetworkReport {
    # Build the Network section (pure) from raw adapter data (no cmdlets here).
    param([object[]] $Adapters = @())
    $list = @(foreach ($a in $Adapters) {
        $pmt = "$($a.PhysicalMediaType)"
        $type = if ($pmt -match '802\.11') { 'Wi-Fi' } elseif ($pmt -match '802\.3') { 'Ethernet' } else { 'Other' }
        $link = if ($a.SpeedBps) { [int][math]::Round([double]$a.SpeedBps / 1e6) } else { $null }
        $wlan = $a.Wlan
        [pscustomobject]@{
            Name             = "$($a.Name)".Trim()
            Type             = $type
            LinkMbps         = $link
            SignalPercent    = if ($wlan) { $wlan.SignalPercent } else { $null }
            Band             = if ($wlan) { $wlan.Band } else { $null }
            RadioType        = if ($wlan) { $wlan.RadioType } else { $null }
            Standard         = if ($wlan) { ConvertTo-WifiStandard $wlan.RadioType } else { $null }
            MaxSupportedMbps = $a.MaxSupportedMbps
        }
    })
    [pscustomobject]@{ Adapters = $list }
}

function ConvertFrom-NvidiaSmiCsv {
    # Pure parse of one `nvidia-smi --query-gpu=... --format=csv,noheader,nounits`
    # line: name,temp,util,clock,maxclock,power,pstate,sw_thermal,hw_thermal.
    param([string] $Line)
    $out = [pscustomobject]@{ Name = $null; TempC = $null; UtilPercent = $null; ClockMHz = $null; MaxClockMHz = $null; PowerW = $null; PState = $null; SwThermal = $null; HwThermal = $null }
    if ([string]::IsNullOrWhiteSpace($Line)) { return $out }
    $f = @($Line -split ',' | ForEach-Object { $_.Trim() })
    if ($f.Count -lt 9) { return $out }

    function _str($s) { if ([string]::IsNullOrWhiteSpace($s) -or $s -eq '[N/A]') { return $null } return $s }
    function _int($s) { $v = 0; if ($s -and $s -ne '[N/A]' -and [int]::TryParse($s, [ref]$v)) { return $v } return $null }
    function _dbl($s) { $v = 0.0; if ($s -and $s -ne '[N/A]' -and [double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v } return $null }

    $out.Name        = _str $f[0]
    $out.TempC       = _int $f[1]
    $out.UtilPercent = _int $f[2]
    $out.ClockMHz    = _int $f[3]
    $out.MaxClockMHz = _int $f[4]
    $out.PowerW      = _dbl $f[5]
    $out.PState      = _str $f[6]
    $out.SwThermal   = _str $f[7]
    $out.HwThermal   = _str $f[8]
    return $out
}

function New-GpuSensorReport {
    # Build the GpuSensor section (pure) from parsed nvidia-smi fields.
    param($Name = $null, $TempC = $null, $UtilPercent = $null, $ClockMHz = $null, $MaxClockMHz = $null, $PowerW = $null, $PState = $null, $SwThermal = $null, $HwThermal = $null)
    [pscustomobject]@{
        Name            = if ($Name) { "$Name".Trim() } else { $null }
        TempC           = $TempC
        UtilPercent     = $UtilPercent
        ClockMHz        = $ClockMHz
        MaxClockMHz     = $MaxClockMHz
        PowerW          = $PowerW
        PState          = $PState
        ThermalThrottle = ("$SwThermal" -eq 'Active' -or "$HwThermal" -eq 'Active')
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

function Get-BatteryInsights {
    # Battery wear + power-plan notes from the Battery section.
    param([object] $Battery)
    $notes = @()
    if ($null -eq $Battery) { return , @($notes) }

    $wear = $Battery.WearPercent
    if ($null -ne $wear) {
        $health = $Battery.HealthPercent
        if ([int]$wear -ge 35) {
            $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Battery is significantly worn - it holds about $health% of its original design capacity (about $wear% lost). Runtime is much shorter than when new; consider replacing it." }
        } elseif ([int]$wear -ge 20) {
            $notes += [pscustomobject]@{ Kind = 'info'; Text = "Battery shows noticeable wear - it holds about $health% of its design capacity (about $wear% lost)." }
        }
    }

    $guid = "$($Battery.PowerPlanGuid)".Trim()
    $plan = "$($Battery.PowerPlan)".Trim()
    if ($guid -eq 'a1841308-3541-4fab-bc81-f71556f20b4a' -or $plan -match 'saver') {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Active power plan is 'Power saver', which caps CPU speed to save energy. Switch to Balanced or High performance for full performance." }
    }
    return , @($notes)
}

function Get-LoadStatus {
    # Pure memory-pressure tier from the Load section: 'ok' | 'tight' | 'pressure'.
    # Single source of truth for the thresholds (used by insights + renderers).
    # Levels drive the tier; paging only escalates a already-tight state.
    param([object] $Load)
    if ($null -eq $Load) { return 'ok' }
    $avail = $Load.AvailablePercent
    $commit = $Load.CommitPercent
    $reads = if ($null -ne $Load.PageReadsPerSec) { [int]$Load.PageReadsPerSec } else { 0 }

    $availLow       = ($null -ne $avail -and [int]$avail -lt 10)
    $availTight     = ($null -ne $avail -and [int]$avail -lt 20)
    $commitHigh     = ($null -ne $commit -and [int]$commit -ge 90)
    $commitElevated = ($null -ne $commit -and [int]$commit -ge 80)
    $paging         = ($reads -gt 100)

    if ($availLow -or $commitHigh -or ($availTight -and $paging)) { 'pressure' }
    elseif ($availTight -or $commitElevated) { 'tight' }
    else { 'ok' }
}

function Get-LoadInsights {
    # Live memory-pressure notes from the Load section, keyed off Get-LoadStatus.
    param([object] $Load)
    $notes = @()
    if ($null -eq $Load) { return , @($notes) }
    $avail = $Load.AvailablePercent
    $commit = $Load.CommitPercent
    if ($null -eq $avail -and $null -eq $commit) { return , @($notes) }
    $reads = if ($null -ne $Load.PageReadsPerSec) { [int]$Load.PageReadsPerSec } else { 0 }

    $status = Get-LoadStatus -Load $Load
    $detail = "$($Load.AvailableGB) GB available ($avail%), commit at $commit%"

    if ($status -eq 'pressure') {
        $pageClause = if ($reads -gt 100) { ", paging to disk (~{0:N0}/sec)" -f $reads } else { '' }
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Low on memory right now: $detail$pageClause. Close apps or add RAM - the system is slowing from memory pressure." }
    } elseif ($status -eq 'tight') {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "Memory is getting tight right now: $detail. Heavy multitasking may start to slow down." }
    }
    return , @($notes)
}

function Get-NetworkInsights {
    # Honest network notes: Ethernet linked below capability, and Wi-Fi band /
    # signal / standard. No "Wi-Fi vs theoretical PHY max" (always cries wolf).
    param([object] $Network)
    $notes = @()
    if ($null -eq $Network) { return , @($notes) }
    foreach ($a in $Network.Adapters) {
        if ($a.Type -eq 'Ethernet' -and $a.LinkMbps -and [int]$a.LinkMbps -gt 0 -and
            $null -ne $a.MaxSupportedMbps -and [int]$a.LinkMbps -lt [int]$a.MaxSupportedMbps) {
            $notes += [pscustomobject]@{ Kind = 'warn'; Text = "Ethernet is linked at $($a.LinkMbps) Mbps but the adapter supports $($a.MaxSupportedMbps) Mbps - usually a bad cable, a slow switch/port, or a duplex mismatch." }
        }
        if ($a.Type -eq 'Wi-Fi') {
            if ("$($a.Band)" -match '2\.4') {
                $notes += [pscustomobject]@{ Kind = 'info'; Text = "Wi-Fi is on the slower 2.4 GHz band; the 5 GHz (or 6 GHz) band is much faster when you're in range." }
            }
            if ($null -ne $a.SignalPercent -and [int]$a.SignalPercent -lt 40) {
                $notes += [pscustomobject]@{ Kind = 'info'; Text = "Weak Wi-Fi signal ($($a.SignalPercent)%); the link rate drops with signal - move closer to the router or reduce interference." }
            }
            if ("$($a.RadioType)" -match '802\.11(a|b|g|n)$') {
                $notes += [pscustomobject]@{ Kind = 'info'; Text = "Wi-Fi is $($a.RadioType); 802.11ac/ax is several times faster if your router supports it." }
            }
        }
    }
    return , @($notes)
}

function Get-GpuSensorInsights {
    # GPU thermal notes from live nvidia-smi data. The throttle flag is
    # authoritative; the temperature threshold is a supplementary heuristic.
    param([object] $GpuSensor)
    $notes = @()
    if ($null -eq $GpuSensor) { return , @($notes) }
    $temp = $GpuSensor.TempC
    if ($GpuSensor.ThermalThrottle -eq $true) {
        $t = if ($null -ne $temp) { "$($temp)$([char]176)C" } else { 'hot' }
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = "The GPU is thermally throttling right now ($t) - it's hot enough that it's reducing clocks. Improve airflow/cooling (clean the fans, raise the laptop, or check the thermal paste)." }
    } elseif ($null -ne $temp -and [int]$temp -ge 87) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "GPU is running hot ($($temp)$([char]176)C), near the throttle point; keep an eye on cooling." }
    }
    return , @($notes)
}

function Get-GamingInsights {
    # Gaming-specific notes from the Gaming section. Single-channel/HDD-boot/XMP
    # already have notes elsewhere, so they are not duplicated here.
    param([object] $Gaming)
    $notes = @()
    if ($null -eq $Gaming) { return , @($notes) }
    if ($Gaming.IsDiscrete -eq $false) {
        $notes += [pscustomobject]@{ Kind = 'warn'; Text = 'No discrete GPU - gaming is limited to esports and older titles at low settings.' }
    } elseif ($null -ne $Gaming.VramGB -and [double]$Gaming.VramGB -lt 8) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "$($Gaming.VramGB) GB of VRAM limits texture quality in modern AAA games at high settings (8 GB+ is the comfortable minimum today)." }
    }
    if ($null -ne $Gaming.RefreshHz -and [int]$Gaming.RefreshHz -le 60 -and $null -ne $Gaming.Rank -and [int]$Gaming.Rank -ge 3) {
        $notes += [pscustomobject]@{ Kind = 'info'; Text = "Your GPU can likely push past 60 fps, but the $($Gaming.RefreshHz) Hz display caps what you see - a high-refresh panel would show more." }
    }
    return , @($notes)
}

function Get-SystemInsights {
    # Orchestrator: per-subsystem notes plus cross-subsystem bottleneck notes.
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null, [object] $Battery = $null, [object] $Load = $null, [object] $Network = $null, [object] $GpuSensor = $null, [object] $Gaming = $null)
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
    if ($null -ne $Battery) {
        $batteryNotes = Get-BatteryInsights -Battery $Battery
        $notes += $batteryNotes
    }
    if ($null -ne $Load) {
        $loadNotes = Get-LoadInsights -Load $Load
        $notes += $loadNotes
    }
    if ($null -ne $Network) {
        $networkNotes = Get-NetworkInsights -Network $Network
        $notes += $networkNotes
    }
    if ($null -ne $GpuSensor) {
        $gpuSensorNotes = Get-GpuSensorInsights -GpuSensor $GpuSensor
        $notes += $gpuSensorNotes
    }
    if ($null -ne $Gaming) {
        $gamingNotes = Get-GamingInsights -Gaming $Gaming
        $notes += $gamingNotes
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
    param([object] $Cpu, [object] $Memory, [object] $Gpu = $null, [object] $Storage = $null, [object] $Battery = $null, [object] $Load = $null, [object] $Network = $null, [object] $GpuSensor = $null)
    # Gaming is a synthesis of the sections above (computed here, not passed in).
    $gaming = if ($null -ne $Gpu) { New-GamingReport -Gpu $Gpu -Cpu $Cpu -Memory $Memory -Storage $Storage } else { $null }
    # Upgrade Advisor is a synthesis too (computed here; emits no notes, so it is
    # NOT passed to Get-SystemInsights).
    $upgrade = New-UpgradeReport -Cpu $Cpu -Memory $Memory -Gpu $Gpu -Storage $Storage -Battery $Battery
    $insights = Get-SystemInsights -Cpu $Cpu -Memory $Memory -Gpu $Gpu -Storage $Storage -Battery $Battery -Load $Load -Network $Network -GpuSensor $GpuSensor -Gaming $gaming
    [pscustomobject]@{
        Cpu       = $Cpu
        Memory    = $Memory
        Gpu       = $Gpu
        Storage   = $Storage
        Battery   = $Battery
        Load      = $Load
        Network   = $Network
        GpuSensor = $GpuSensor
        Gaming    = $gaming
        Upgrade   = $upgrade
        Insights  = $insights
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

function Get-BatteryInfo {
    # Live battery + active-power-plan data, normalized for New-BatteryReport.
    # Returns $null on a desktop (no battery). Self-guarding (never throws);
    # verified via the -Console run rather than unit tests.
    $w32 = $null
    try { $w32 = Get-CimInstance Win32_Battery -ErrorAction Stop | Select-Object -First 1 } catch { }
    if ($null -eq $w32) { return $null }   # no battery instance -> desktop / AC only

    $charge = if ($null -ne $w32.EstimatedChargeRemaining) { [int]$w32.EstimatedChargeRemaining } else { $null }

    # On-AC / charging from root\wmi BatteryStatus (reliable booleans); fall back
    # to the Win32_Battery.BatteryStatus enum.
    $isOnAC = $null; $isCharging = $null
    try {
        $bs = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        if ($bs) {
            $isOnAC = [bool]$bs.PowerOnline
            $isCharging = [bool]$bs.Charging
            if ($null -eq $charge -and $bs.RemainingCapacity) {
                $fcc = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($fcc.FullChargedCapacity -gt 0) { $charge = [int][math]::Round([double]$bs.RemainingCapacity / [double]$fcc.FullChargedCapacity * 100, 0) }
            }
        }
    } catch { }
    if ($null -eq $isOnAC) {
        switch ([int]$w32.BatteryStatus) {
            1 { $isOnAC = $false; $isCharging = $false }
            { $_ -in 6, 7, 8, 9 } { $isOnAC = $true; $isCharging = $true }
            default { $isOnAC = $true; $isCharging = $false }
        }
    }

    # Design/full capacity, cycles, chemistry, maker via the powercfg report.
    $design = $null; $full = $null; $cycles = $null; $chem = $null; $maker = $null
    try {
        $tmp = Join-Path $env:TEMP ("battrep_{0}.xml" -f [guid]::NewGuid().ToString('N'))
        $null = powercfg /batteryreport /output $tmp /xml 2>$null
        if (Test-Path $tmp) {
            $rep = ConvertFrom-BatteryReportXml -Xml (Get-Content $tmp -Raw -ErrorAction SilentlyContinue)
            $design = $rep.DesignCapacityMWh; $full = $rep.FullChargeCapacityMWh
            $cycles = $rep.CycleCount; $chem = $rep.Chemistry; $maker = $rep.Manufacturer
            Remove-Item $tmp -ErrorAction SilentlyContinue
        }
    } catch { }
    if ($null -eq $full) {
        try {
            $fcc = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($fcc.FullChargedCapacity -gt 0) { $full = [int]$fcc.FullChargedCapacity }
        } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($maker)) { $maker = "$($w32.Name)".Trim() }

    $planName = $null; $planGuid = $null
    try {
        $s = ConvertFrom-ActiveScheme -Text (powercfg /getactivescheme 2>$null | Out-String)
        $planName = $s.Name; $planGuid = $s.Guid
    } catch { }

    [pscustomobject]@{
        ChargePercent = $charge; IsOnAC = $isOnAC; IsCharging = $isCharging
        DesignCapacityMWh = $design; FullChargeCapacityMWh = $full; CycleCount = $cycles
        Chemistry = $chem; Manufacturer = $maker; PowerPlan = $planName; PowerPlanGuid = $planGuid
    }
}

function Get-LoadInfo {
    # Live memory-pressure snapshot, normalized for New-LoadReport. Self-guarding;
    # returns $null only if the memory counter is entirely unavailable. Verified
    # via the -Console run rather than unit tests.
    try {
        $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop | Select-Object -First 1
    } catch { return $null }
    if ($null -eq $m) { return $null }
    $total = $null
    try { $total = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory } catch { }

    [pscustomobject]@{
        TotalPhysicalBytes = $total
        AvailableBytes     = $m.AvailableBytes
        CommittedBytes     = $m.CommittedBytes
        CommitLimitBytes   = $m.CommitLimit
        PercentCommitted   = $m.PercentCommittedBytesInUse
        PageReadsPerSec    = $m.PageReadsPerSec
    }
}

function Get-NetworkInfo {
    # Active adapters (link + Wi-Fi health), normalized for New-NetworkReport.
    # Self-guarding; verified via the -Console run. Wi-Fi details come from netsh
    # (best-effort / localized); Ethernet max from the Speed & Duplex advanced prop.
    $adapters = @()
    try {
        $wlanText = $null
        $ups = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        foreach ($n in $ups) {
            $pmt = "$($n.PhysicalMediaType)"
            $wlan = $null; $maxMbps = $null
            if ($pmt -match '802\.11') {
                if ($null -eq $wlanText) { $wlanText = (netsh wlan show interfaces 2>$null | Out-String) }
                $wlan = ConvertFrom-NetshWlan -Text $wlanText
            } elseif ($pmt -match '802\.3') {
                try {
                    $sd = Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction Stop | Where-Object { $_.DisplayName -match 'Speed.*Duplex' } | Select-Object -First 1
                    if ($sd) { $maxMbps = ConvertTo-MaxLinkMbps -ValidValues @($sd.ValidDisplayValues) }
                } catch { }
            }
            $adapters += [pscustomobject]@{
                Name = $n.Name; PhysicalMediaType = $pmt; SpeedBps = $n.Speed; Wlan = $wlan; MaxSupportedMbps = $maxMbps
            }
        }
    } catch { }
    [pscustomobject]@{ Adapters = $adapters }
}

function Get-GpuSensorInfo {
    # Live NVIDIA GPU sensors via nvidia-smi (first GPU). Returns $null unless
    # nvidia-smi resolves and the query succeeds. Self-guarding; verified via -Console.
    if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { return $null }
    try {
        $q = 'name,temperature.gpu,utilization.gpu,clocks.gr,clocks.max.gr,power.draw,pstate,clocks_throttle_reasons.sw_thermal_slowdown,clocks_throttle_reasons.hw_thermal_slowdown'
        $out = & nvidia-smi "--query-gpu=$q" '--format=csv,noheader,nounits' 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $line = @($out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0]
        if ([string]::IsNullOrWhiteSpace($line)) { return $null }
        $parsed = ConvertFrom-NvidiaSmiCsv -Line $line
        if ($null -eq $parsed.Name) { return $null }
        return $parsed
    } catch { return $null }
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
    '  Note: speeds are MT/s (data rate); the DRAM bus clock is half - e.g. 3200 MT/s = 1600 MHz'
    "        (that's CPU-Z's 'DRAM Frequency'; Task Manager labels MT/s as 'MHz')."
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
    if ($Report.Battery) {
        $bat = $Report.Battery
        $chgStr  = if ($null -ne $bat.ChargePercent) { "$($bat.ChargePercent)%" } else { 'Unknown' }
        $wearStr = if ($null -ne $bat.WearPercent) { "$($bat.HealthPercent)% of design ($($bat.WearPercent)% worn)" } else { 'Unknown' }
        $desStr  = if ($null -ne $bat.DesignCapacityMWh) { '{0:N0} mWh' -f $bat.DesignCapacityMWh } else { 'Unknown' }
        $fulStr  = if ($null -ne $bat.FullChargeCapacityMWh) { '{0:N0} mWh' -f $bat.FullChargeCapacityMWh } else { 'Unknown' }
        $cycStr  = if ($null -ne $bat.CycleCount) { "$($bat.CycleCount)" } else { 'Not reported' }
        '  Battery'
        '  -------'
        '  Charge           : {0}  ({1})' -f $chgStr, $bat.Status
        '  Health           : {0}' -f $wearStr
        '  Design capacity  : {0}' -f $desStr
        '  Full charge      : {0}' -f $fulStr
        '  Cycle count      : {0}' -f $cycStr
        '  Chemistry        : {0}' -f $bat.Chemistry
        '  Power plan       : {0}' -f $bat.PowerPlan
        ''
    }
    if ($Report.Load) {
        $ld = $Report.Load
        $status = switch (Get-LoadStatus -Load $ld) { 'pressure' { 'Under pressure' } 'tight' { 'Getting tight' } default { 'OK' } }
        $avail = if ($null -ne $ld.AvailableGB) { "$($ld.AvailableGB) GB" + $(if ($null -ne $ld.AvailablePercent) { " ($($ld.AvailablePercent)%)" } else { '' }) } else { 'Unknown' }
        $commit = if ($null -ne $ld.CommitPercent) { "{0} GB of {1} GB  ({2}%)" -f $ld.CommitUsedGB, $ld.CommitLimitGB, $ld.CommitPercent } else { 'Unknown' }
        $paging = if ($null -ne $ld.PageReadsPerSec) { "~{0:N0} hard reads/sec" -f $ld.PageReadsPerSec } else { 'Unknown' }
        '  Live / Load'
        '  -----------'
        '  Total RAM        : {0}' -f $(if ($null -ne $ld.TotalPhysicalGB) { "$($ld.TotalPhysicalGB) GB" } else { 'Unknown' })
        '  Available        : {0}' -f $avail
        '  Commit charge    : {0}' -f $commit
        '  Paging (to disk) : {0}' -f $paging
        '  Status           : {0}' -f $status
        '  (live values, as of when this ran)'
        ''
    }
    if ($Report.Network -and @($Report.Network.Adapters).Count -gt 0) {
        '  Network'
        '  -------'
        ($Report.Network.Adapters |
            Format-Table -AutoSize @{n='Adapter';e={$_.Name}},
                                    @{n='Type';e={$_.Type}},
                                    @{n='Link';e={ if ($null -ne $_.LinkMbps) { "$($_.LinkMbps) Mbps" } else { '?' } }},
                                    @{n='Signal';e={ if ($null -ne $_.SignalPercent) { "$($_.SignalPercent)%" } else { '' } }},
                                    @{n='Band';e={ $_.Band }},
                                    @{n='Standard';e={ $_.Standard }} |
            Out-String).TrimEnd()
        ''
    }
    if ($Report.GpuSensor) {
        $gsr = $Report.GpuSensor
        $gt  = if ($null -ne $gsr.TempC) { "$($gsr.TempC)$([char]176)C" } else { 'Unknown' }
        $gu  = if ($null -ne $gsr.UtilPercent) { "$($gsr.UtilPercent)%" } else { 'Unknown' }
        $gclk = if ($null -ne $gsr.ClockMHz) { "$($gsr.ClockMHz)" + $(if ($null -ne $gsr.MaxClockMHz) { " / $($gsr.MaxClockMHz)" } else { '' }) + ' MHz' } else { 'Unknown' }
        $gpw = if ($null -ne $gsr.PowerW) { '{0:N1} W' -f $gsr.PowerW } else { 'Unknown' }
        '  GPU sensors'
        '  -----------'
        '  GPU              : {0}' -f $(if ($gsr.Name) { $gsr.Name } else { 'Unknown' })
        '  Temperature      : {0}' -f $gt
        '  Utilization      : {0}' -f $gu
        '  Core clock       : {0}' -f $gclk
        '  Power draw       : {0}' -f $gpw
        '  Performance state: {0}' -f $(if ($gsr.PState) { $gsr.PState } else { 'Unknown' })
        if ($gsr.ThermalThrottle) { '  Thermal throttle : YES (reducing clocks)' }
        '  (live, via nvidia-smi)'
        ''
    }
    if ($Report.Gaming) {
        $gm = $Report.Gaming
        $lim = if (@($gm.Limiters).Count -gt 0) { ($gm.Limiters -join ', ') } else { 'none - well balanced' }
        $dispStr = if ($null -ne $gm.RefreshHz) { "$($gm.DisplayW)x$($gm.DisplayH) @ $($gm.RefreshHz) Hz" } else { 'Unknown' }
        '  Gaming'
        '  ------'
        '  Overall          : {0}' -f $gm.Verdict
        '  Limited by       : {0}' -f $lim
        '  GPU              : {0}' -f $(if ($gm.GpuName) { $gm.GpuName } else { 'Unknown' })
        '  VRAM             : {0}' -f $(if ($null -ne $gm.VramGB) { "$($gm.VramGB) GB" } else { 'Unknown' })
        '  CPU              : {0}' -f $(if ($null -ne $gm.Cores) { "$($gm.Cores) cores" } else { 'Unknown' })
        '  Memory           : {0}' -f $(if ($null -ne $gm.RamGB) { "$($gm.RamGB) GB $(if ($gm.DualChannel) { 'dual-channel' } else { 'single-channel' })" } else { 'Unknown' })
        '  Display          : {0}' -f $dispStr
        '  (tiering is approximate / generation-level)'
        ''
    }
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
    $ovTop.Height = 194
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
    $batteryLine = if ($null -ne $Report.Battery) {
        $b = $Report.Battery
        $segs = @("$($b.ChargePercent)%", $b.Status)
        if ($null -ne $b.WearPercent) { $segs += "$($b.WearPercent)% worn" }
        if ($b.PowerPlan) { $segs += $b.PowerPlan }
        ($segs -join '  -  ')
    } else { 'none (AC only)' }
    $networkLine = if ($null -ne $Report.Network -and @($Report.Network.Adapters).Count -gt 0) {
        $primary = @($Report.Network.Adapters | Where-Object { $_.LinkMbps }) | Select-Object -First 1
        if (-not $primary) { $primary = $Report.Network.Adapters[0] }
        $det = @()
        if ($primary.Band) { $det += $primary.Band }
        if ($primary.Standard) { $det += $primary.Standard }
        if ($null -ne $primary.SignalPercent) { $det += "$($primary.SignalPercent)%" }
        "$($primary.Type)  -  $($primary.LinkMbps) Mbps" + $(if ($det.Count) { " ($($det -join ', '))" } else { '' })
    } else { 'No active connection' }
    $gamingLine = if ($null -ne $Report.Gaming) {
        $g = $Report.Gaming
        "$($g.Verdict)" + $(if (@($g.Limiters).Count -gt 0) { " (limited by $($g.Limiters -join ', '))" } else { '' })
    } else { 'Unknown' }
    $oy = Add-KvBlock -Parent $ovTop -Keys @('Processor:', 'Graphics:', 'Memory:', 'Storage:', 'Battery:', 'Network:', 'Gaming:') -Values @($cpuLine, $gpuLine, $memLine, $storageLine, $batteryLine, $networkLine, $gamingLine) -X 4 -Y 6 -KeyW 90 -ValW 460
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
    # Live GPU sensor panel (nvidia-smi), docked below the adapter list.
    if ($null -ne $Report.GpuSensor) {
        $gsr = $Report.GpuSensor
        $gsPanel = New-Object System.Windows.Forms.Panel
        $gsPanel.Dock = 'Bottom'; $gsPanel.Height = 132
        $gsHdr = New-Object System.Windows.Forms.Label
        $gsHdr.Text = 'GPU sensors (live, via nvidia-smi)'
        $gsHdr.Location = New-Object System.Drawing.Point(4, 2); $gsHdr.AutoSize = $true
        $gsHdr.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
        $gsPanel.Controls.Add($gsHdr)
        $gsKeys = @('Temperature:', 'Utilization:', 'Core clock:', 'Power draw:', 'Perf. state:')
        $gsVals = @(
            $(if ($null -ne $gsr.TempC) { "$($gsr.TempC)$([char]176)C" } else { 'Unknown' })
            $(if ($null -ne $gsr.UtilPercent) { "$($gsr.UtilPercent)%" } else { 'Unknown' })
            $(if ($null -ne $gsr.ClockMHz) { "$($gsr.ClockMHz)$(if ($null -ne $gsr.MaxClockMHz) { " / $($gsr.MaxClockMHz)" }) MHz" } else { 'Unknown' })
            $(if ($null -ne $gsr.PowerW) { '{0:N1} W' -f $gsr.PowerW } else { 'Unknown' })
            $(if ($gsr.PState) { $gsr.PState } else { 'Unknown' })
        )
        if ($gsr.ThermalThrottle) { $gsKeys += 'Thermal:'; $gsVals += 'THROTTLING (reducing clocks)' }
        [void](Add-KvBlock -Parent $gsPanel -Keys $gsKeys -Values $gsVals -X 4 -Y 24 -KeyW 110 -ValW 320)
        $tabGpu.Controls.Add($gsPanel)
    }
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
    $memFoot = New-Object System.Windows.Forms.Label
    $memFoot.Text = "MT/s = data rate; the DRAM clock is half (3200 MT/s = 1600 MHz, i.e. CPU-Z's 'DRAM Frequency')."
    $memFoot.Location = New-Object System.Drawing.Point(14, ($my + 2))
    $memFoot.AutoSize = $true
    $memFoot.ForeColor = [System.Drawing.Color]::Gray
    $memFoot.Anchor = 'Top,Left'
    $tabMem.Controls.Add($memFoot)
    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'; $list.FullRowSelect = $true; $list.GridLines = $true
    $list.Location = New-Object System.Drawing.Point(14, ($my + 44))
    $list.Size = New-Object System.Drawing.Size(572, (430 - $my - 40))
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

    # --- Gaming tab (synthesis; present whenever a GPU was assessed) ---
    if ($null -ne $Report.Gaming) {
        $gm = $Report.Gaming
        $tabGame = New-Object System.Windows.Forms.TabPage
        $tabGame.Text = 'Gaming'
        $lim = if (@($gm.Limiters).Count -gt 0) { ($gm.Limiters -join ', ') } else { 'none - well balanced' }
        $disp = if ($null -ne $gm.RefreshHz) { "$($gm.DisplayW)x$($gm.DisplayH) @ $($gm.RefreshHz) Hz" } else { 'Unknown' }
        $gKeys = @('Overall:', 'Limited by:', 'GPU:', 'VRAM:', 'CPU:', 'Memory:', 'Display:')
        $gVals = @(
            $gm.Verdict
            $lim
            $(if ($gm.GpuName) { $gm.GpuName } else { 'Unknown' })
            $(if ($null -ne $gm.VramGB) { "$($gm.VramGB) GB" } else { 'Unknown' })
            $(if ($null -ne $gm.Cores) { "$($gm.Cores) cores" } else { 'Unknown' })
            $(if ($null -ne $gm.RamGB) { "$($gm.RamGB) GB $(if ($gm.DualChannel) { 'dual-channel' } else { 'single-channel' })" } else { 'Unknown' })
            $disp
        )
        $gy = Add-KvBlock -Parent $tabGame -Keys $gKeys -Values $gVals -KeyW 110 -ValW 440
        $gCap = New-Object System.Windows.Forms.Label
        $gCap.Text = 'Gaming tiering is approximate / generation-level, not a benchmark.'
        $gCap.Location = New-Object System.Drawing.Point(14, ($gy + 6))
        $gCap.AutoSize = $true
        $gCap.ForeColor = [System.Drawing.Color]::Gray
        $tabGame.Controls.Add($gCap)
        [void]$tabs.TabPages.Add($tabGame)
    }

    # --- Battery tab (only when a battery exists) ---
    if ($null -ne $Report.Battery) {
        $bat = $Report.Battery
        $tabBattery = New-Object System.Windows.Forms.TabPage
        $tabBattery.Text = 'Battery'
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
        [void](Add-KvBlock -Parent $tabBattery -Keys $batKeys -Values $batVals -KeyW 150 -ValW 420)
        [void]$tabs.TabPages.Add($tabBattery)
    }

    # --- Live tab (only when live load data exists) ---
    if ($null -ne $Report.Load) {
        $ld = $Report.Load
        $status = switch (Get-LoadStatus -Load $ld) { 'pressure' { 'Under pressure' } 'tight' { 'Getting tight' } default { 'OK' } }
        $tabLive = New-Object System.Windows.Forms.TabPage
        $tabLive.Text = 'Live'
        $liveKeys = @('Total RAM:', 'Available:', 'Commit charge:', 'Paging (to disk):', 'Status:')
        $liveVals = @(
            $(if ($null -ne $ld.TotalPhysicalGB) { "$($ld.TotalPhysicalGB) GB" } else { 'Unknown' })
            $(if ($null -ne $ld.AvailableGB) { "$($ld.AvailableGB) GB" + $(if ($null -ne $ld.AvailablePercent) { " ($($ld.AvailablePercent)%)" } else { '' }) } else { 'Unknown' })
            $(if ($null -ne $ld.CommitPercent) { "{0} GB of {1} GB  ({2}%)" -f $ld.CommitUsedGB, $ld.CommitLimitGB, $ld.CommitPercent } else { 'Unknown' })
            $(if ($null -ne $ld.PageReadsPerSec) { "~{0:N0} hard reads/sec" -f $ld.PageReadsPerSec } else { 'Unknown' })
            $status
        )
        $ly = Add-KvBlock -Parent $tabLive -Keys $liveKeys -Values $liveVals -KeyW 150 -ValW 420
        $liveCaption = New-Object System.Windows.Forms.Label
        $liveCaption.Text = '(live values, as of when this window opened)'
        $liveCaption.Location = New-Object System.Drawing.Point(14, ($ly + 6))
        $liveCaption.AutoSize = $true
        $liveCaption.ForeColor = [System.Drawing.Color]::Gray
        $tabLive.Controls.Add($liveCaption)
        [void]$tabs.TabPages.Add($tabLive)
    }

    # --- Network tab (only when at least one adapter is up) ---
    if ($null -ne $Report.Network -and @($Report.Network.Adapters).Count -gt 0) {
        $tabNet = New-Object System.Windows.Forms.TabPage
        $tabNet.Text = 'Network'
        $tabNet.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 8)
        $netList = New-Object System.Windows.Forms.ListView
        $netList.View = 'Details'; $netList.FullRowSelect = $true; $netList.GridLines = $true; $netList.Dock = 'Fill'
        [void]$netList.Columns.Add('Adapter', 150)
        [void]$netList.Columns.Add('Type', 80)
        [void]$netList.Columns.Add('Link', 90)
        [void]$netList.Columns.Add('Signal', 60)
        [void]$netList.Columns.Add('Band', 70)
        [void]$netList.Columns.Add('Standard', 150)
        foreach ($a in $Report.Network.Adapters) {
            $item = New-Object System.Windows.Forms.ListViewItem([string]$a.Name)
            [void]$item.SubItems.Add([string]$a.Type)
            [void]$item.SubItems.Add($(if ($null -ne $a.LinkMbps) { "$($a.LinkMbps) Mbps" } else { '?' }))
            [void]$item.SubItems.Add($(if ($null -ne $a.SignalPercent) { "$($a.SignalPercent)%" } else { '' }))
            [void]$item.SubItems.Add([string]$a.Band)
            [void]$item.SubItems.Add([string]$a.Standard)
            [void]$netList.Items.Add($item)
        }
        $tabNet.Controls.Add($netList)
        $nFill = { $o = 0; for ($i = 1; $i -lt $netList.Columns.Count; $i++) { $o += $netList.Columns[$i].Width }; $f = $netList.ClientSize.Width - $o; if ($f -gt 120) { $netList.Columns[0].Width = $f } }.GetNewClosure()
        $netList.Add_Resize($nFill); & $nFill
        [void]$tabs.TabPages.Add($tabNet)
    }

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
        $batRaw  = Get-BatteryInfo
        $loadRaw = Get-LoadInfo
        $netRaw  = Get-NetworkInfo
        $gsRaw   = Get-GpuSensorInfo
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
    $battery = if ($null -ne $batRaw) {
        New-BatteryReport -ChargePercent $batRaw.ChargePercent -IsOnAC $batRaw.IsOnAC -IsCharging $batRaw.IsCharging `
                          -DesignCapacityMWh $batRaw.DesignCapacityMWh -FullChargeCapacityMWh $batRaw.FullChargeCapacityMWh `
                          -CycleCount $batRaw.CycleCount -Chemistry $batRaw.Chemistry -Manufacturer $batRaw.Manufacturer `
                          -PowerPlan $batRaw.PowerPlan -PowerPlanGuid $batRaw.PowerPlanGuid
    } else { $null }
    $load = if ($null -ne $loadRaw) {
        New-LoadReport -TotalPhysicalBytes $loadRaw.TotalPhysicalBytes -AvailableBytes $loadRaw.AvailableBytes `
                       -CommittedBytes $loadRaw.CommittedBytes -CommitLimitBytes $loadRaw.CommitLimitBytes `
                       -PercentCommitted $loadRaw.PercentCommitted -PageReadsPerSec $loadRaw.PageReadsPerSec
    } else { $null }
    $network = New-NetworkReport -Adapters $netRaw.Adapters
    $gpuSensor = if ($null -ne $gsRaw) {
        New-GpuSensorReport -Name $gsRaw.Name -TempC $gsRaw.TempC -UtilPercent $gsRaw.UtilPercent -ClockMHz $gsRaw.ClockMHz `
                            -MaxClockMHz $gsRaw.MaxClockMHz -PowerW $gsRaw.PowerW -PState $gsRaw.PState `
                            -SwThermal $gsRaw.SwThermal -HwThermal $gsRaw.HwThermal
    } else { $null }

    $report = New-SystemReport -Cpu $cpu -Memory $memory -Gpu $gpu -Storage $storage -Battery $battery -Load $load -Network $network -GpuSensor $gpuSensor

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
