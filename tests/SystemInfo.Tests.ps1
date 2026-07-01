# Zero-dependency test harness for Show-SystemInfo.ps1
# Run:  pwsh -File tests\SystemInfo.Tests.ps1
$ErrorActionPreference = 'Continue'
$env:SYSTEMINFO_NOMAIN = '1'          # don't run the GUI/main on dot-source
. "$PSScriptRoot\..\Show-SystemInfo.ps1"

$script:Pass = 0
$script:Fail = 0

function Assert-Equal($Expected, $Actual, $Name) {
    if ("$Expected" -eq "$Actual") {
        $script:Pass++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } else {
        $script:Fail++
        Write-Host "  FAIL  $Name -- expected [$Expected] got [$Actual]" -ForegroundColor Red
    }
}
function It($Name, [scriptblock]$Body) {
    try { & $Body }
    catch {
        $script:Fail++
        Write-Host "  FAIL  $Name -- $($_.Exception.Message)" -ForegroundColor Red
    }
}
function HasNote($ins, $sub) { [bool](@($ins) | Where-Object { $_.Text -match [regex]::Escape($sub) }) }

# Shared fixtures
$mods = @(
    [pscustomobject]@{ Slot='DIMM A'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
    [pscustomobject]@{ Slot='DIMM B'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
)
$cpuDev = New-CpuReport -Name 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' -Cores 8 -Threads 16 -MaxClockMHz 2304 `
                        -L2CacheKB 2048 -L3CacheKB 16384 -Socket 'CPU 1' -AddressWidth 64 -VirtualizationEnabled $false -MemoryType 'DDR4'

Write-Host "`nConvertTo-MemoryTypeName" -ForegroundColor Cyan
It 'type 26 -> DDR4'   { Assert-Equal 'DDR4'         (ConvertTo-MemoryTypeName 26)    'type 26' }
It 'type 34 -> DDR5'   { Assert-Equal 'DDR5'         (ConvertTo-MemoryTypeName 34)    'type 34' }
It 'type 24 -> DDR3'   { Assert-Equal 'DDR3'         (ConvertTo-MemoryTypeName 24)    'type 24' }
It 'type 30 -> LPDDR4' { Assert-Equal 'LPDDR4'       (ConvertTo-MemoryTypeName 30)    'type 30' }
It 'unknown code'      { Assert-Equal 'Unknown (99)' (ConvertTo-MemoryTypeName 99)    'type 99' }
It 'null code'         { Assert-Equal 'Unknown'      (ConvertTo-MemoryTypeName $null) 'type null' }

Write-Host "`nConvertTo-VendorName" -ForegroundColor Cyan
It 'SK Hynix code'   { Assert-Equal 'SK Hynix' (ConvertTo-VendorName '80AD00000000')     'code 80AD' }
It 'Samsung code'    { Assert-Equal 'Samsung'  (ConvertTo-VendorName '80CE000000000000') 'code 80CE' }
It 'Micron code'     { Assert-Equal 'Micron'   (ConvertTo-VendorName '802C00000000')     'code 802C' }
It 'friendly name'   { Assert-Equal 'Corsair'  (ConvertTo-VendorName 'Corsair')          'passthrough' }
It 'unknown hex raw' { Assert-Equal '1234'     (ConvertTo-VendorName '1234')             'raw fallback' }
It 'empty -> Unknown'{ Assert-Equal 'Unknown'  (ConvertTo-VendorName '')                 'empty' }
It 'null -> Unknown' { Assert-Equal 'Unknown'  (ConvertTo-VendorName $null)              'null' }

Write-Host "`nGet-CpuSpec (memory speed)" -ForegroundColor Cyan
function SpecSpeed($name, $type) { (Get-CpuSpec -Name $name -MemoryType $type).MaxSpeed }
function SpecKnown($name)        { (Get-CpuSpec -Name $name -MemoryType 'DDR4').Known }
function SpecLabel($name, $type) { (Get-CpuSpec -Name $name -MemoryType $type).Label }
It 'i7-10875H'     { Assert-Equal 2933 (SpecSpeed 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' 'DDR4') 'gen10 H' }
It 'i5-10400'      { Assert-Equal 2666 (SpecSpeed 'Intel(R) Core(TM) i5-10400 CPU @ 2.90GHz' 'DDR4') 'gen10 i5' }
It 'i9-10900K'     { Assert-Equal 2933 (SpecSpeed 'Intel(R) Core(TM) i9-10900K' 'DDR4') 'gen10 i9' }
It 'i7-1065G7'     { Assert-Equal 2933 (SpecSpeed 'Intel(R) Core(TM) i7-1065G7 CPU @ 1.30GHz' 'DDR4') 'gen10 4-digit' }
It 'i7-1255U'      { Assert-Equal 3200 (SpecSpeed 'Intel(R) Core(TM) i7-1255U' 'DDR4') 'gen12 4-digit' }
It 'i7-12700H DDR5'{ Assert-Equal 4800 (SpecSpeed '12th Gen Intel(R) Core(TM) i7-12700H' 'DDR5') 'gen12 DDR5' }
It 'i7-12700H DDR4'{ Assert-Equal 3200 (SpecSpeed '12th Gen Intel(R) Core(TM) i7-12700H' 'DDR4') 'gen12 DDR4' }
It 'i9-13900K'     { Assert-Equal 5600 (SpecSpeed 'Intel(R) Core(TM) i9-13900K' 'DDR5') 'gen13 DDR5' }
It 'i7-11700K'     { Assert-Equal 3200 (SpecSpeed 'Intel(R) Core(TM) i7-11700K' 'DDR4') 'gen11' }
It 'i7-6700K'      { Assert-Equal 2133 (SpecSpeed 'Intel(R) Core(TM) i7-6700K CPU @ 4.00GHz' 'DDR4') 'gen6' }
It 'i7-8550U'      { Assert-Equal 2666 (SpecSpeed 'Intel(R) Core(TM) i7-8550U CPU @ 1.80GHz' 'DDR4') 'gen8' }
It 'i5-9400F'      { Assert-Equal 2666 (SpecSpeed 'Intel(R) Core(TM) i5-9400F CPU @ 2.90GHz' 'DDR4') 'gen9' }
It 'Ultra 7 155H'  { Assert-Equal 5600 (SpecSpeed 'Intel(R) Core(TM) Ultra 7 155H' 'DDR5') 'ultra S1' }
It 'Ultra 9 285K'  { Assert-Equal 6400 (SpecSpeed 'Intel(R) Core(TM) Ultra 9 285K' 'DDR5') 'ultra S2' }
It 'i7-4790K old'  { Assert-Equal $false (SpecKnown 'Intel(R) Core(TM) i7-4790K CPU @ 4.00GHz') 'gen4 below table' }
It 'Ryzen 5800X'   { Assert-Equal 3200 (SpecSpeed 'AMD Ryzen 7 5800X 8-Core Processor' 'DDR4') 'zen3' }
It 'Ryzen 3600'    { Assert-Equal 3200 (SpecSpeed 'AMD Ryzen 5 3600 6-Core Processor' 'DDR4') 'zen2' }
It 'Ryzen 2700X'   { Assert-Equal 2933 (SpecSpeed 'AMD Ryzen 7 2700X Eight-Core Processor' 'DDR4') 'zen+' }
It 'Ryzen 1600'    { Assert-Equal 2667 (SpecSpeed 'AMD Ryzen 5 1600 Six-Core Processor' 'DDR4') 'zen1' }
It 'Ryzen 7950X'   { Assert-Equal 5200 (SpecSpeed 'AMD Ryzen 9 7950X 16-Core Processor' 'DDR5') 'zen4' }
It 'Ryzen 9950X'   { Assert-Equal 5600 (SpecSpeed 'AMD Ryzen 9 9950X 16-Core Processor' 'DDR5') 'zen5' }
It 'Ryzen 6900HS'  { Assert-Equal 4800 (SpecSpeed 'AMD Ryzen 9 6900HS Creator Edition' 'DDR5') 'zen3+' }
It 'Xeon unknown'    { Assert-Equal $false (SpecKnown 'Intel(R) Xeon(R) W-2245 CPU @ 3.90GHz') 'xeon' }
It 'Threadripper'    { Assert-Equal $false (SpecKnown 'AMD Ryzen Threadripper 3960X 24-Core Processor') 'tr' }
It 'Pentium unknown' { Assert-Equal $false (SpecKnown 'Intel(R) Pentium(R) Gold G6400 CPU @ 4.00GHz') 'pentium' }
It 'empty unknown'   { Assert-Equal $false (SpecKnown '') 'empty' }
It 'label ddr4'    { Assert-Equal 'DDR4-2933' (SpecLabel 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' 'DDR4') 'label4' }
It 'label ddr5'    { Assert-Equal 'DDR5-4800' (SpecLabel '12th Gen Intel(R) Core(TM) i7-12700H' 'DDR5') 'label5' }

Write-Host "`nGet-CpuSpec (codename / generation)" -ForegroundColor Cyan
function SpecCode($name) { (Get-CpuSpec -Name $name -MemoryType 'DDR4').Codename }
function SpecGen($name)  { (Get-CpuSpec -Name $name -MemoryType 'DDR4').GenerationLabel }
It 'codename comet'  { Assert-Equal 'Comet Lake'  (SpecCode 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz') 'comet' }
It 'codename ice'    { Assert-Equal 'Ice Lake'    (SpecCode 'Intel(R) Core(TM) i7-1065G7 CPU @ 1.30GHz') 'ice' }
It 'codename raptor' { Assert-Equal 'Raptor Lake' (SpecCode 'Intel(R) Core(TM) i9-13900K') 'raptor' }
It 'codename zen3'   { Assert-Equal 'Zen 3'       (SpecCode 'AMD Ryzen 7 5800X 8-Core Processor') 'zen3' }
It 'codename zen4'   { Assert-Equal 'Zen 4'       (SpecCode 'AMD Ryzen 9 7950X 16-Core Processor') 'zen4' }
It 'codename meteor' { Assert-Equal 'Meteor Lake' (SpecCode 'Intel(R) Core(TM) Ultra 7 155H') 'meteor' }
It 'gen intel 10th'  { Assert-Equal '10th Gen'    (SpecGen 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz') 'intel gen' }
It 'gen amd 5000'    { Assert-Equal 'Ryzen 5000'  (SpecGen 'AMD Ryzen 7 5800X 8-Core Processor') 'amd gen' }

Write-Host "`nFormat-CpuName" -ForegroundColor Cyan
It 'intel clean'   { Assert-Equal 'Intel Core i7-10875H' (Format-CpuName 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz') 'intel' }
It 'amd clean'     { Assert-Equal 'AMD Ryzen 7 5800X'     (Format-CpuName 'AMD Ryzen 7 5800X 8-Core Processor') 'amd' }
It 'cpuname empty' { Assert-Equal '' (Format-CpuName '') 'empty' }

Write-Host "`nNew-MemoryReport" -ForegroundColor Cyan
$mem = New-MemoryReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03'
It 'mem total'      { Assert-Equal 16   $mem.TotalInstalledGB 'sum' }
It 'mem populated'  { Assert-Equal 2    $mem.PopulatedSlots   'count' }
It 'mem free'       { Assert-Equal 0    $mem.FreeSlots        'free' }
It 'mem type'       { Assert-Equal DDR4 $mem.TypeName         'type' }
It 'mem maxcap'     { Assert-Equal 64   $mem.MaxCapacityGB    'maxcap' }
It 'mem board'      { Assert-Equal 'Dell 0CXCCY (rev A03)' $mem.Board 'board' }
It 'mem size'       { Assert-Equal 8    $mem.Modules[0].SizeGB 'size' }
It 'mem vendor'     { Assert-Equal 'SK Hynix' $mem.Modules[0].Vendor 'vendor' }
It 'mem running'    { Assert-Equal 2933 $mem.RunningSpeed     'running' }
$mem4 = New-MemoryReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 4 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03'
It 'mem free 4-2'   { Assert-Equal 2 $mem4.FreeSlots 'two free' }
$memEmpty = New-MemoryReport -Modules @() -MaxCapacityBytes 68719476736 -TotalSlots 2
It 'mem empty total'{ Assert-Equal 0 $memEmpty.TotalInstalledGB 'empty' }
It 'mem empty type' { Assert-Equal 'Unknown' $memEmpty.TypeName 'empty type' }

Write-Host "`nNew-CpuReport" -ForegroundColor Cyan
It 'cpu name'     { Assert-Equal 'Intel Core i7-10875H' $cpuDev.Name 'name' }
It 'cpu vendor'   { Assert-Equal 'Intel' $cpuDev.Vendor 'vendor' }
It 'cpu cores'    { Assert-Equal 8  $cpuDev.Cores   'cores' }
It 'cpu threads'  { Assert-Equal 16 $cpuDev.Threads 'threads' }
It 'cpu base'     { Assert-Equal 2.3 $cpuDev.BaseClockGHz 'base' }
It 'cpu l2'       { Assert-Equal 2  $cpuDev.L2CacheMB 'l2' }
It 'cpu l3'       { Assert-Equal 16 $cpuDev.L3CacheMB 'l3' }
It 'cpu codename' { Assert-Equal 'Comet Lake' $cpuDev.Codename 'codename' }
It 'cpu gen'      { Assert-Equal '10th Gen' $cpuDev.GenerationLabel 'gen' }
It 'cpu maxmem'   { Assert-Equal 'DDR4-2933' $cpuDev.MaxMemLabel 'maxmem' }
It 'cpu 64bit'    { Assert-Equal $true $cpuDev.Is64Bit 'x64' }
It 'cpu virt'     { Assert-Equal $false $cpuDev.VirtualizationEnabled 'virt' }
It 'cpu socket'   { Assert-Equal 'CPU 1' $cpuDev.Socket 'socket' }
$cpuUnknown = New-CpuReport -Name 'Mystery Chip 9000' -Cores 4 -Threads 4 -MaxClockMHz 3000 -AddressWidth 64
It 'cpu unknown maxmem' { Assert-Equal $false $cpuUnknown.MaxMemKnown 'unknown' }
It 'cpu unknown codename' { Assert-Equal $null $cpuUnknown.Codename 'no codename' }

Write-Host "`nGet-MemoryInsights" -ForegroundColor Cyan
$i = Get-MemoryInsights -RunningSpeed 2933 -ModuleRatedSpeeds @(3200,3200) -CpuMaxSpeed 2933 -CpuName 'i7-10875H' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'cpu-capped note'   { Assert-Equal $true  (HasNote $i 'CPU is the limiter') 'limiter' }
It 'no single-channel' { Assert-Equal $false (HasNote $i 'Single-channel')      'dual' }
It 'capacity replace'  { Assert-Equal $true  (HasNote $i 'replacing modules')   'full' }
$sc = Get-MemoryInsights -RunningSpeed 3200 -ModuleRatedSpeeds @(3200) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 1 -TotalSlots 2 -InstalledGB 8 -MaxCapacityGB 64
It 'single-channel warn' { Assert-Equal $true (HasNote $sc 'Single-channel') 'one stick' }
$cfg = Get-MemoryInsights -RunningSpeed 2133 -ModuleRatedSpeeds @(3200,3200) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'config xmp warn'    { Assert-Equal $true (HasNote $cfg 'XMP') 'xmp' }
$ml = Get-MemoryInsights -RunningSpeed 2666 -ModuleRatedSpeeds @(2666,2666) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'module-limited info'{ Assert-Equal $true (HasNote $ml 'faster modules') 'modules' }
$uk = Get-MemoryInsights -RunningSpeed 2133 -ModuleRatedSpeeds @(3200) -CpuMaxSpeed $null -CpuName 'x' -PopulatedSlots 1 -TotalSlots 1 -InstalledGB 8 -MaxCapacityGB 16
It 'unknown cpu xmp'    { Assert-Equal $true (HasNote $uk 'XMP') 'below rating' }

Write-Host "`nGet-CpuInsights" -ForegroundColor Cyan
It 'virt disabled note' { Assert-Equal $true  (HasNote (Get-CpuInsights -Cpu $cpuDev) 'disabled') 'virt off' }
$cpuVirtOn = New-CpuReport -Name 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' -Cores 8 -Threads 16 -AddressWidth 64 -VirtualizationEnabled $true -MemoryType 'DDR4'
It 'virt enabled none'  { Assert-Equal $false (HasNote (Get-CpuInsights -Cpu $cpuVirtOn) 'disabled') 'virt on' }
$cpuVirtNull = New-CpuReport -Name 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' -Cores 8 -Threads 16 -AddressWidth 64 -MemoryType 'DDR4'
It 'virt null none'     { Assert-Equal $false (HasNote (Get-CpuInsights -Cpu $cpuVirtNull) 'disabled') 'virt unknown' }

Write-Host "`nGet-SystemInsights" -ForegroundColor Cyan
$memDual = New-MemoryReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY'
$sysDual = Get-SystemInsights -Cpu $cpuDev -Memory $memDual
It 'sys has limiter'   { Assert-Equal $true  (HasNote $sysDual 'CPU is the limiter') 'mem note' }
It 'sys has virt'      { Assert-Equal $true  (HasNote $sysDual 'Virtualization')      'cpu note' }
It 'sys no cores note' { Assert-Equal $false (HasNote $sysDual 'cores share single-channel') 'dual' }
$mod1 = @([pscustomobject]@{ Slot='DIMM A'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=3200; VendorRaw='80AD00000000'; PartNumber='X'; TypeCode=26 })
$memSingle = New-MemoryReport -Modules $mod1 -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY'
$sysSingle = Get-SystemInsights -Cpu $cpuDev -Memory $memSingle
It 'sys single-channel' { Assert-Equal $true (HasNote $sysSingle 'Single-channel') 'single' }
It 'sys cores note'     { Assert-Equal $true (HasNote $sysSingle 'cores share single-channel') 'cross' }
# Regression: iterate like the renderer (no @() flattening) - each note must be
# its own element with a string Text, not a nested sub-array.
$flatCount = 0; $allStrings = $true
foreach ($x in $sysDual) { $flatCount++; if ($x.Text -isnot [string]) { $allStrings = $false } }
It 'sys notes flat (count)'   { Assert-Equal 3 $flatCount 'cpu-limiter + capacity + virtualization' }
It 'sys notes flat (scalar)' { Assert-Equal $true $allStrings 'each Text is a string' }

Write-Host "`nNew-SystemReport" -ForegroundColor Cyan
$rep = New-SystemReport -Cpu $cpuDev -Memory $memDual
It 'report cpu'      { Assert-Equal 'Intel Core i7-10875H' $rep.Cpu.Name 'cpu' }
It 'report mem'      { Assert-Equal 16 $rep.Memory.TotalInstalledGB 'mem' }
It 'report insights' { Assert-Equal $true (@($rep.Insights).Count -gt 0) 'insights' }

Write-Host "`nGet-GpuType" -ForegroundColor Cyan
function GpuType($name, $vendor) { Get-GpuType -Name $name -Vendor $vendor }
It 'gpu nvidia disc' { Assert-Equal 'Discrete'   (GpuType 'NVIDIA GeForce RTX 2060 with Max-Q Design' 'NVIDIA') 'nv' }
It 'gpu intel integ' { Assert-Equal 'Integrated' (GpuType 'Intel(R) UHD Graphics' 'Intel Corporation') 'intel' }
It 'gpu arc disc'    { Assert-Equal 'Discrete'   (GpuType 'Intel(R) Arc(TM) A770 Graphics' 'Intel Corporation') 'arc' }
It 'gpu radeon rx'   { Assert-Equal 'Discrete'   (GpuType 'AMD Radeon RX 6800 XT' 'Advanced Micro Devices, Inc.') 'rx' }
It 'gpu amd apu'     { Assert-Equal 'Integrated' (GpuType 'AMD Radeon(TM) Graphics' 'Advanced Micro Devices, Inc.') 'apu' }
It 'gpu gtx disc'    { Assert-Equal 'Discrete'   (GpuType 'NVIDIA GeForce GTX 1650' 'NVIDIA') 'gtx' }
It 'gpu unknown'     { Assert-Equal 'Unknown'    (GpuType 'Microsoft Basic Display Adapter' '') 'basic' }

Write-Host "`nNew-GpuReport" -ForegroundColor Cyan
$rawGpus = @(
    [pscustomobject]@{ Name='NVIDIA GeForce RTX 2060 with Max-Q Design'; Vendor='NVIDIA'; AdapterRamBytes=4293918720; RegistryVramBytes=6442450944; DriverVersion='32.0.15.8180'; DriverDate=[datetime]'2025-10-28'; Availability=8; ResH=0; ResV=0; ResRefresh=0 }
    [pscustomobject]@{ Name='Intel(R) UHD Graphics'; Vendor='Intel Corporation'; AdapterRamBytes=1073741824; RegistryVramBytes=$null; DriverVersion='31.0.101.2130'; DriverDate=[datetime]'2024-08-12'; Availability=3; ResH=1920; ResV=1200; ResRefresh=59 }
)
$now = [datetime]'2026-06-30'
$gpu = New-GpuReport -Gpus $rawGpus -Now $now
$nv = $gpu.Gpus[0]; $intel = $gpu.Gpus[1]
It 'gpu count'         { Assert-Equal 2 $gpu.Gpus.Count 'two gpus' }
It 'gpu nv vram reg'   { Assert-Equal 6 $nv.VramGB 'registry 6GB' }
It 'gpu nv vram src'   { Assert-Equal 'registry' $nv.VramSource 'src' }
It 'gpu nv type'       { Assert-Equal 'Discrete' $nv.Type 'disc' }
It 'gpu nv status'     { Assert-Equal 'Idle' $nv.Status 'idle' }
It 'gpu nv inactive'   { Assert-Equal $false $nv.IsActive 'inactive' }
It 'gpu nv res dash'   { Assert-Equal '-' $nv.Resolution 'no res' }
It 'gpu nv age'        { Assert-Equal 8 $nv.DriverAgeMonths 'nv age' }
It 'gpu intel vram'    { Assert-Equal 1 $intel.VramGB 'adapterRAM 1GB' }
It 'gpu intel vramsrc' { Assert-Equal 'adapterRAM' $intel.VramSource 'fallback' }
It 'gpu intel type'    { Assert-Equal 'Integrated' $intel.Type 'integ' }
It 'gpu intel status'  { Assert-Equal 'Active' $intel.Status 'active' }
It 'gpu intel res'     { Assert-Equal '1920x1200@59' $intel.Resolution 'res' }
It 'gpu intel age'     { Assert-Equal 22 $intel.DriverAgeMonths 'age' }

Write-Host "`nGet-GpuInsights" -ForegroundColor Cyan
$gi = Get-GpuInsights -Gpu $gpu
It 'gpu inactive note' { Assert-Equal $true (HasNote $gi 'present but idle') 'inactive disc' }
It 'gpu old driver'    { Assert-Equal $true (HasNote $gi 'months old') 'old drv' }
$rawActive = @([pscustomobject]@{ Name='NVIDIA GeForce RTX 4090'; Vendor='NVIDIA'; AdapterRamBytes=4293918720; RegistryVramBytes=25769803776; DriverVersion='x'; DriverDate=[datetime]'2026-05-01'; Availability=3; ResH=3840; ResV=2160; ResRefresh=144 })
$giActive = Get-GpuInsights -Gpu (New-GpuReport -Gpus $rawActive -Now $now)
It 'gpu active no note' { Assert-Equal $false (HasNote $giActive 'present but idle') 'active disc' }
It 'gpu recent no note' { Assert-Equal $false (HasNote $giActive 'months old') 'recent drv' }

Write-Host "`nGet-SystemInsights (GPU cross note)" -ForegroundColor Cyan
$sysGpuSingle = Get-SystemInsights -Cpu $cpuDev -Memory $memSingle -Gpu $gpu
It 'igpu single-channel cross' { Assert-Equal $true  (HasNote $sysGpuSingle 'single-channel RAM notably limits') 'cross fires' }
$sysGpuDual = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu
It 'igpu no cross dual'        { Assert-Equal $false (HasNote $sysGpuDual 'single-channel RAM notably limits') 'no cross dual' }
$repGpu = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu
It 'report has gpu'           { Assert-Equal 2 $repGpu.Gpu.Gpus.Count 'gpu in report' }

Write-Host "`nGet-DiskKind" -ForegroundColor Cyan
function DiskKind($n, $m, $b) { Get-DiskKind -Name $n -MediaType $m -BusType $b }
It 'disk nvme bus'    { Assert-Equal 'NVMe SSD' (DiskKind 'Samsung SSD 980' 'SSD' 'NVMe') 'nvme bus' }
It 'disk nvme name'   { Assert-Equal 'NVMe SSD' (DiskKind 'NVMe PC611 NVMe SK hynix 512GB' 'SSD' 'RAID') 'nvme over raid' }
It 'disk sata ssd'    { Assert-Equal 'SATA SSD' (DiskKind 'Crucial MX500' 'SSD' 'SATA') 'sata ssd' }
It 'disk hdd'         { Assert-Equal 'HDD'      (DiskKind 'WDC WD10EZEX' 'HDD' 'SATA') 'hdd' }
It 'disk mediatype 4' { Assert-Equal 'SATA SSD' (DiskKind 'X' '4' 'SATA') 'num ssd' }
It 'disk unknown'     { Assert-Equal 'Unknown'  (DiskKind 'Some Disk' 'Unspecified' 'SATA') 'unknown' }

Write-Host "`nNew-StorageReport" -ForegroundColor Cyan
$rawDisks = @([pscustomobject]@{ Name='NVMe PC611 NVMe SK hynix 512GB'; MediaType='SSD'; BusType='RAID'; SizeBytes=549755813888; Health='Healthy'; IsBoot=$true })
$rawVols  = @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=515396075520; FreeBytes=103079215104 })
$st = New-StorageReport -Disks $rawDisks -Volumes $rawVols
$d0 = $st.Disks[0]; $v0 = $st.Volumes[0]
It 'storage disk count' { Assert-Equal 1 $st.Disks.Count 'disks' }
It 'storage disk kind'  { Assert-Equal 'NVMe SSD' $d0.Kind 'kind' }
It 'storage disk boot'  { Assert-Equal $true $d0.IsBoot 'boot' }
It 'storage disk size'  { Assert-Equal 512 $d0.SizeGB 'size' }
It 'storage vol letter' { Assert-Equal 'C' $v0.DriveLetter 'letter' }
It 'storage vol size'   { Assert-Equal 480 $v0.SizeGB 'vol size' }
It 'storage vol free'   { Assert-Equal 96 $v0.FreeGB 'free' }
It 'storage vol pct'    { Assert-Equal 20 $v0.FreePercent 'pct' }

Write-Host "`nGet-StorageInsights" -ForegroundColor Cyan
$giHealthy = Get-StorageInsights -Storage $st
It 'storage no notes' { Assert-Equal 0 (@($giHealthy).Count) 'healthy nvme ample' }
$stHdd = New-StorageReport -Disks @([pscustomobject]@{ Name='WDC WD10EZEX'; MediaType='HDD'; BusType='SATA'; SizeBytes=1000204886016; Health='Healthy'; IsBoot=$true }) -Volumes @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=515396075520; FreeBytes=103079215104 })
It 'storage boot hdd'  { Assert-Equal $true (HasNote (Get-StorageInsights -Storage $stHdd) 'mechanical hard drive') 'boot hdd' }
$stLow = New-StorageReport -Disks @([pscustomobject]@{ Name='NVMe X'; MediaType='SSD'; BusType='NVMe'; SizeBytes=549755813888; Health='Healthy'; IsBoot=$true }) -Volumes @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=515396075520; FreeBytes=21474836480 })
It 'storage low space' { Assert-Equal $true (HasNote (Get-StorageInsights -Storage $stLow) 'low on space') 'low space' }
$stSick = New-StorageReport -Disks @([pscustomobject]@{ Name='NVMe X'; MediaType='SSD'; BusType='NVMe'; SizeBytes=549755813888; Health='Warning'; IsBoot=$true }) -Volumes @()
It 'storage unhealthy' { Assert-Equal $true (HasNote (Get-StorageInsights -Storage $stSick) "reports health 'Warning'") 'health' }
$stSata = New-StorageReport -Disks @([pscustomobject]@{ Name='Crucial MX500'; MediaType='SSD'; BusType='SATA'; SizeBytes=549755813888; Health='Healthy'; IsBoot=$true }) -Volumes @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=515396075520; FreeBytes=103079215104 })
It 'storage sata hint' { Assert-Equal $true (HasNote (Get-StorageInsights -Storage $stSata) 'NVMe SSD is several times faster') 'sata hint' }

Write-Host "`nSystem report (Storage wiring)" -ForegroundColor Cyan
$sysStorage = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $stHdd
It 'sys has storage note' { Assert-Equal $true (HasNote $sysStorage 'mechanical hard drive') 'storage in sys' }
$repFull = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st
It 'report has storage'   { Assert-Equal 1 $repFull.Storage.Disks.Count 'storage in report' }

# =====================================================================
# Battery / power (slice D)
# =====================================================================

Write-Host "`nConvertFrom-BatteryReportXml" -ForegroundColor Cyan
# Faithful compact fixture: the RuntimeEstimates/DesignCapacity element wraps
# <Capacity> + runtime text, so a naive //DesignCapacity yields '95065PT4H33M44S'.
# The parser must scope to Batteries/Battery.
$battXml = @'
<?xml version="1.0" encoding="utf-8"?>
<BatteryReport xmlns="http://schemas.microsoft.com/battery/2012">
  <Batteries>
    <Battery>
      <Id>DELL 01RR3YM</Id>
      <Manufacturer>SMP</Manufacturer>
      <SerialNumber>1857</SerialNumber>
      <ManufactureDate></ManufactureDate>
      <Chemistry>LiP</Chemistry>
      <LongTerm>1</LongTerm>
      <RelativeCapacity>0</RelativeCapacity>
      <DesignCapacity>95065</DesignCapacity>
      <FullChargeCapacity>52166</FullChargeCapacity>
      <CycleCount>0</CycleCount>
    </Battery>
  </Batteries>
  <RuntimeEstimates>
    <DesignCapacity>
      <Capacity>95065</Capacity>
      <ActiveRuntime>PT4H33M44S</ActiveRuntime>
    </DesignCapacity>
    <FullChargeCapacity>
      <Capacity>52166</Capacity>
      <ActiveRuntime>PT2H30M12S</ActiveRuntime>
    </FullChargeCapacity>
  </RuntimeEstimates>
</BatteryReport>
'@
$bp = ConvertFrom-BatteryReportXml -Xml $battXml
It 'batt xml design'  { Assert-Equal 95065 $bp.DesignCapacityMWh 'design cap (not the runtime-estimate node)' }
It 'batt xml full'    { Assert-Equal 52166 $bp.FullChargeCapacityMWh 'full cap' }
It 'batt xml cycles'  { Assert-Equal 0     $bp.CycleCount 'cycles' }
It 'batt xml chem'    { Assert-Equal 'LiP' $bp.Chemistry 'chemistry' }
It 'batt xml maker'   { Assert-Equal 'SMP' $bp.Manufacturer 'manufacturer' }
It 'batt xml empty'   { Assert-Equal $null (ConvertFrom-BatteryReportXml -Xml '').DesignCapacityMWh 'empty -> null' }
It 'batt xml garbage' { Assert-Equal $null (ConvertFrom-BatteryReportXml -Xml 'not xml').FullChargeCapacityMWh 'garbage -> null' }

Write-Host "`nConvertFrom-ActiveScheme" -ForegroundColor Cyan
$schBal = ConvertFrom-ActiveScheme -Text 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)'
It 'scheme bal guid'  { Assert-Equal '381b4222-f694-41f0-9685-ff5bb260df2e' $schBal.Guid 'balanced guid' }
It 'scheme bal name'  { Assert-Equal 'Balanced' $schBal.Name 'balanced name' }
$schSaver = ConvertFrom-ActiveScheme -Text 'Power Scheme GUID: a1841308-3541-4fab-bc81-f71556f20b4a  (Power saver)'
It 'scheme saver guid' { Assert-Equal 'a1841308-3541-4fab-bc81-f71556f20b4a' $schSaver.Guid 'saver guid' }
It 'scheme saver name' { Assert-Equal 'Power saver' $schSaver.Name 'saver name' }
It 'scheme empty'      { Assert-Equal $null (ConvertFrom-ActiveScheme -Text '').Guid 'empty -> null' }

Write-Host "`nNew-BatteryReport" -ForegroundColor Cyan
$batDev = New-BatteryReport -ChargePercent 100 -IsOnAC $true -IsCharging $false `
    -DesignCapacityMWh 95065 -FullChargeCapacityMWh 52166 -CycleCount 0 `
    -Chemistry 'LiP' -Manufacturer 'SMP' -PowerPlan 'Balanced' -PowerPlanGuid '381b4222-f694-41f0-9685-ff5bb260df2e'
It 'batt wear 45'      { Assert-Equal 45 $batDev.WearPercent 'wear (95065->52166)' }
It 'batt health 55'    { Assert-Equal 55 $batDev.HealthPercent 'health = 100-wear' }
It 'batt status full'  { Assert-Equal 'Fully charged (on AC)' $batDev.Status 'on AC, not charging, 100%' }
It 'batt cycles null'  { Assert-Equal $null $batDev.CycleCount 'cycle 0 -> null (not reported)' }
It 'batt chem friendly'{ Assert-Equal 'Lithium Polymer' $batDev.Chemistry 'LiP -> friendly' }
It 'batt design kept'  { Assert-Equal 95065 $batDev.DesignCapacityMWh 'design mWh' }

$batNoDes = New-BatteryReport -ChargePercent 80 -IsOnAC $true -IsCharging $true -DesignCapacityMWh $null `
    -FullChargeCapacityMWh 52166 -CycleCount 120 -Chemistry 'Li-I' -PowerPlan 'Balanced' -PowerPlanGuid 'x'
It 'batt wear null'    { Assert-Equal $null $batNoDes.WearPercent 'no design -> null wear' }
It 'batt cycles kept'  { Assert-Equal 120 $batNoDes.CycleCount 'cycle 120 kept' }
It 'batt status charge'{ Assert-Equal 'Charging' $batNoDes.Status 'on AC + charging' }
It 'batt chem li-ion'  { Assert-Equal 'Lithium-ion' $batNoDes.Chemistry 'Li-I -> friendly' }

$batDis = New-BatteryReport -ChargePercent 63 -IsOnAC $false -IsCharging $false -DesignCapacityMWh 95065 -FullChargeCapacityMWh 52166 -PowerPlan 'Balanced' -PowerPlanGuid 'x'
It 'batt status disch' { Assert-Equal 'On battery (discharging)' $batDis.Status 'not on AC' }
$batAc = New-BatteryReport -ChargePercent 70 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 95065 -FullChargeCapacityMWh 90000 -PowerPlan 'Balanced' -PowerPlanGuid 'x'
It 'batt status ac'    { Assert-Equal 'On AC (not charging)' $batAc.Status 'on AC, not charging, 70%' }

Write-Host "`nGet-BatteryInsights" -ForegroundColor Cyan
$niWear = Get-BatteryInsights -Battery $batDev    # wear 45, Balanced
It 'batt wear warn text' { Assert-Equal $true (HasNote $niWear 'significantly worn') 'wear 45 -> warn' }
It 'batt wear warn kind' { Assert-Equal 'warn' (@($niWear | Where-Object { $_.Text -match 'significantly worn' })[0].Kind) 'warn kind' }
It 'batt wear one note'  { Assert-Equal 1 (@($niWear).Count) 'only wear note (Balanced -> no power note)' }

$bat25 = New-BatteryReport -ChargePercent 100 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 100000 -FullChargeCapacityMWh 75000 -PowerPlan 'Balanced' -PowerPlanGuid '381b4222-f694-41f0-9685-ff5bb260df2e'
$ni25 = Get-BatteryInsights -Battery $bat25
It 'batt wear info text' { Assert-Equal $true (HasNote $ni25 'noticeable wear') 'wear 25 -> info' }
It 'batt wear info kind' { Assert-Equal 'info' (@($ni25 | Where-Object { $_.Text -match 'noticeable wear' })[0].Kind) 'info kind' }

$bat10 = New-BatteryReport -ChargePercent 100 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 100000 -FullChargeCapacityMWh 90000 -PowerPlan 'Balanced' -PowerPlanGuid '381b4222-f694-41f0-9685-ff5bb260df2e'
$ni10 = Get-BatteryInsights -Battery $bat10
It 'batt wear none'      { Assert-Equal 0 (@($ni10).Count) 'wear 10 + Balanced -> no notes' }

$batSaverGuid = New-BatteryReport -ChargePercent 90 -IsOnAC $false -IsCharging $false -DesignCapacityMWh 100000 -FullChargeCapacityMWh 96000 -PowerPlan 'Energiesparmodus' -PowerPlanGuid 'a1841308-3541-4fab-bc81-f71556f20b4a'
It 'batt saver by guid'  { Assert-Equal $true (HasNote (Get-BatteryInsights -Battery $batSaverGuid) 'Power saver') 'saver GUID (localized name)' }
$batSaverName = New-BatteryReport -ChargePercent 90 -IsOnAC $false -IsCharging $false -DesignCapacityMWh 100000 -FullChargeCapacityMWh 96000 -PowerPlan 'Power saver' -PowerPlanGuid 'some-other-guid'
It 'batt saver by name'  { Assert-Equal $true (HasNote (Get-BatteryInsights -Battery $batSaverName) 'Power saver') 'saver by name' }

Write-Host "`nSystem report (Battery wiring)" -ForegroundColor Cyan
$sysBat = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Battery $batDev
It 'sys has battery note' { Assert-Equal $true (HasNote $sysBat 'significantly worn') 'battery note in sys insights' }
$sysNoBat = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Battery $null
It 'sys null battery ok'  { Assert-Equal $false (HasNote $sysNoBat 'worn') 'null battery -> no battery note, no error' }
$repBat = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Battery $batDev
It 'report has battery'   { Assert-Equal 'Fully charged (on AC)' $repBat.Battery.Status 'battery section in report' }
It 'report battery note'  { Assert-Equal $true (HasNote $repBat.Insights 'significantly worn') 'battery note flows to report' }
$repNoBat = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st
It 'report null battery'  { Assert-Equal $null $repNoBat.Battery 'no battery -> null section' }

Write-Host "`nWrite-SystemConsole (Battery)" -ForegroundColor Cyan
$conBat = (Write-SystemConsole $repBat | Out-String)
It 'console battery sect'  { Assert-Equal $true  ([bool]($conBat -match 'Cycle count')) 'battery section present (section-unique label)' }
It 'console battery status'{ Assert-Equal $true  ([bool]($conBat -match 'Fully charged')) 'status shown' }
It 'console battery wear'  { Assert-Equal $true  ([bool]($conBat -match '45% worn')) 'wear shown' }
$conNoBat = (Write-SystemConsole $repNoBat | Out-String)
It 'console no battery'    { Assert-Equal $false ([bool]($conNoBat -match 'Cycle count')) 'no battery -> no section' }

Write-Host "`n$script:Pass passed, $script:Fail failed`n"
if ($script:Fail) { exit 1 } else { exit 0 }
