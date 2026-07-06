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

# =====================================================================
# Live / Load — memory pressure (slice E)
# =====================================================================

Write-Host "`nNew-LoadReport" -ForegroundColor Cyan
$ld = New-LoadReport -TotalPhysicalBytes 17179869184 -AvailableBytes 2367782912 -CommittedBytes (46379*1MB) -CommitLimitBytes (54512*1MB) -PercentCommitted 85 -PageReadsPerSec 2016
It 'load avail pct'       { Assert-Equal 14   $ld.AvailablePercent 'available % (2.2/16 GB)' }
It 'load avail gb'        { Assert-Equal 2.2  $ld.AvailableGB 'available GB' }
It 'load total gb'        { Assert-Equal 16   $ld.TotalPhysicalGB 'total GB' }
It 'load commit pct raw'  { Assert-Equal 85   $ld.CommitPercent 'commit % (uses raw)' }
It 'load reads'           { Assert-Equal 2016 $ld.PageReadsPerSec 'page reads/sec' }
$ld2 = New-LoadReport -TotalPhysicalBytes 17179869184 -AvailableBytes 2367782912 -CommittedBytes (46379*1MB) -CommitLimitBytes (54512*1MB) -PercentCommitted $null -PageReadsPerSec 0
It 'load commit computed' { Assert-Equal 85 $ld2.CommitPercent 'commit % computed when raw absent' }
$ld3 = New-LoadReport -TotalPhysicalBytes $null -AvailableBytes $null -CommittedBytes $null -CommitLimitBytes $null -PercentCommitted $null -PageReadsPerSec $null
It 'load null avail pct'  { Assert-Equal $null $ld3.AvailablePercent 'null inputs -> null pct' }
It 'load null commit'     { Assert-Equal $null $ld3.CommitPercent 'null inputs -> null commit' }

Write-Host "`nGet-LoadInsights" -ForegroundColor Cyan
function LoadObj($ap, $ag, $cp, $rd) { [pscustomobject]@{ AvailablePercent=$ap; AvailableGB=$ag; CommitPercent=$cp; PageReadsPerSec=$rd } }
$loLowAvail = Get-LoadInsights -Load (LoadObj 6 1.0 70 50)
It 'load warn low avail'  { Assert-Equal 'warn' (@($loLowAvail)[0].Kind) 'avail 6% -> warn' }
It 'load warn text'       { Assert-Equal $true (HasNote $loLowAvail 'Low on memory') 'warn text' }
$loCommit = Get-LoadInsights -Load (LoadObj 30 5.0 92 10)
It 'load warn commit'     { Assert-Equal $true (HasNote $loCommit 'Low on memory') 'commit 92% -> warn' }
It 'load commit no clause'{ Assert-Equal $false (HasNote $loCommit 'paging to disk') 'commit warn, low paging -> no paging clause' }
$loPaging = Get-LoadInsights -Load (LoadObj 14 2.2 85 2000)
It 'load warn paging'     { Assert-Equal $true (HasNote $loPaging 'paging to disk') 'tight + paging -> warn w/ paging clause' }
$loInfo = Get-LoadInsights -Load (LoadObj 18 3.0 60 20)
It 'load info kind'       { Assert-Equal 'info' (@($loInfo)[0].Kind) 'avail 18% -> info' }
It 'load info no clause'  { Assert-Equal $false (HasNote $loInfo 'paging to disk') 'info -> no paging clause' }
$loOk = Get-LoadInsights -Load (LoadObj 60 9.5 40 0)
It 'load healthy none'    { Assert-Equal 0 (@($loOk).Count) 'healthy -> no note' }

Write-Host "`nSystem report (Load wiring)" -ForegroundColor Cyan
$loadWarn = New-LoadReport -TotalPhysicalBytes 17179869184 -AvailableBytes 1000000000 -CommittedBytes (52000*1MB) -CommitLimitBytes (54512*1MB) -PercentCommitted 95 -PageReadsPerSec 3000
$sysLoad = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Load $loadWarn
It 'sys has load note'  { Assert-Equal $true (HasNote $sysLoad 'Low on memory') 'load note in sys insights' }
$sysNoLoad = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Load $null
It 'sys null load ok'    { Assert-Equal $false (HasNote $sysNoLoad 'Low on memory') 'null load -> no note, no error' }
$repLoad = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Load $loadWarn
It 'report has load'     { Assert-Equal 95 $repLoad.Load.CommitPercent 'load section in report' }
It 'report load note'    { Assert-Equal $true (HasNote $repLoad.Insights 'Low on memory') 'load note flows to report' }
$repNoLoad = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st
It 'report null load'    { Assert-Equal $null $repNoLoad.Load 'no load -> null section' }

Write-Host "`nGet-LoadStatus" -ForegroundColor Cyan
It 'status pressure avail'  { Assert-Equal 'pressure' (Get-LoadStatus -Load (LoadObj 6 1.0 70 0))    'avail 6%' }
It 'status pressure commit' { Assert-Equal 'pressure' (Get-LoadStatus -Load (LoadObj 30 5 92 0))     'commit 92%' }
It 'status pressure paging' { Assert-Equal 'pressure' (Get-LoadStatus -Load (LoadObj 14 2.2 85 2000)) 'tight + paging' }
It 'status tight'           { Assert-Equal 'tight'    (Get-LoadStatus -Load (LoadObj 18 3 60 20))    'avail 18%' }
It 'status ok'              { Assert-Equal 'ok'       (Get-LoadStatus -Load (LoadObj 60 9 40 0))     'healthy' }

Write-Host "`nWrite-SystemConsole (Live/Load)" -ForegroundColor Cyan
$repLoadFull = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Load $loadWarn
$conLoad = (Write-SystemConsole $repLoadFull | Out-String)
It 'console load sect'   { Assert-Equal $true  ([bool]($conLoad -match 'Commit charge')) 'load section present' }
It 'console load status' { Assert-Equal $true  ([bool]($conLoad -match 'Under pressure')) 'status line shown' }
$conNoLoad2 = (Write-SystemConsole $repNoLoad | Out-String)
It 'console no load'     { Assert-Equal $false ([bool]($conNoLoad2 -match 'Commit charge')) 'no load -> no section' }

# =====================================================================
# Network — link + Wi-Fi health (slice F)
# =====================================================================

Write-Host "`nConvertFrom-NetshWlan" -ForegroundColor Cyan
$wlanTxt = @'
There is 1 interface on the system:

    Name                   : Wi-Fi
    State                  : connected
    SSID                   : REDACTED
    BSSID                  : 00:00:00:00:00:00
    Radio type             : 802.11ax
    Band                   : 5 GHz
    Channel                : 157
    Receive rate (Mbps)    : 360
    Transmit rate (Mbps)   : 324
    Signal                 : 80%
'@
$wl = ConvertFrom-NetshWlan -Text $wlanTxt
It 'wlan band'   { Assert-Equal '5 GHz'    $wl.Band 'band' }
It 'wlan radio'  { Assert-Equal '802.11ax' $wl.RadioType 'radio type' }
It 'wlan signal' { Assert-Equal 80         $wl.SignalPercent 'signal %' }
It 'wlan rx'     { Assert-Equal 360        $wl.ReceiveMbps 'rx rate' }
It 'wlan tx'     { Assert-Equal 324        $wl.TransmitMbps 'tx rate' }
It 'wlan state'  { Assert-Equal 'connected' $wl.State 'state' }
It 'wlan empty'  { Assert-Equal $null (ConvertFrom-NetshWlan -Text '').Band 'empty -> null' }

Write-Host "`nConvertTo-MaxLinkMbps" -ForegroundColor Cyan
It 'maxlink gbe'   { Assert-Equal 1000  (ConvertTo-MaxLinkMbps -ValidValues @('Auto Negotiation','10 Mbps Half Duplex','100 Mbps Full Duplex','1.0 Gbps Full Duplex')) '1 GbE' }
It 'maxlink 2.5g'  { Assert-Equal 2500  (ConvertTo-MaxLinkMbps -ValidValues @('100 Mbps Full Duplex','2.5 Gbps Full Duplex')) '2.5 GbE' }
It 'maxlink 100'   { Assert-Equal 100   (ConvertTo-MaxLinkMbps -ValidValues @('10 Mbps Half Duplex','100 Mbps Full Duplex')) '100 Mbps' }
It 'maxlink none'  { Assert-Equal $null (ConvertTo-MaxLinkMbps -ValidValues @('Auto Negotiation')) 'no speeds -> null' }
It 'maxlink empty' { Assert-Equal $null (ConvertTo-MaxLinkMbps -ValidValues @()) 'empty -> null' }

Write-Host "`nNew-NetworkReport" -ForegroundColor Cyan
$rawAdapters = @(
    [pscustomobject]@{ Name='Wi-Fi'; PhysicalMediaType='Native 802.11'; SpeedBps=324000000; Wlan=(ConvertFrom-NetshWlan -Text $wlanTxt); MaxSupportedMbps=$null }
    [pscustomobject]@{ Name='Ethernet'; PhysicalMediaType='802.3'; SpeedBps=100000000; Wlan=$null; MaxSupportedMbps=1000 }
)
$net = New-NetworkReport -Adapters $rawAdapters
$w0 = $net.Adapters[0]; $e0 = $net.Adapters[1]
It 'net wifi type'   { Assert-Equal 'Wi-Fi' $w0.Type 'wifi type' }
It 'net wifi link'   { Assert-Equal 324 $w0.LinkMbps 'wifi link mbps' }
It 'net wifi signal' { Assert-Equal 80 $w0.SignalPercent 'wifi signal' }
It 'net wifi band'   { Assert-Equal '5 GHz' $w0.Band 'wifi band' }
It 'net wifi std'    { Assert-Equal 'Wi-Fi 6 (802.11ax)' $w0.Standard 'wifi standard friendly' }
It 'net eth type'    { Assert-Equal 'Ethernet' $e0.Type 'eth type' }
It 'net eth link'    { Assert-Equal 100 $e0.LinkMbps 'eth link' }
It 'net eth max'     { Assert-Equal 1000 $e0.MaxSupportedMbps 'eth max supported' }

Write-Host "`nGet-NetworkInsights" -ForegroundColor Cyan
function NetAdp($type, $link, $sig, $band, $radio, $max) { [pscustomobject]@{ Name='X'; Type=$type; LinkMbps=$link; SignalPercent=$sig; Band=$band; RadioType=$radio; Standard=(ConvertTo-WifiStandard $radio); MaxSupportedMbps=$max } }
function NetRep($adps) { [pscustomobject]@{ Adapters=@($adps) } }
$niEth = Get-NetworkInsights -Network (NetRep @(NetAdp 'Ethernet' 100 $null $null $null 1000))
It 'net eth below kind' { Assert-Equal 'warn' (@($niEth)[0].Kind) 'eth 100 vs 1000 -> warn' }
It 'net eth below txt'  { Assert-Equal $true (HasNote $niEth 'but the adapter supports') 'eth below text' }
$niEthOk = Get-NetworkInsights -Network (NetRep @(NetAdp 'Ethernet' 1000 $null $null $null 1000))
It 'net eth ok'         { Assert-Equal 0 (@($niEthOk).Count) 'eth at max -> no note' }
$ni24 = Get-NetworkInsights -Network (NetRep @(NetAdp 'Wi-Fi' 144 70 '2.4 GHz' '802.11n' $null))
It 'net wifi 24'        { Assert-Equal $true (HasNote $ni24 '2.4 GHz') '2.4GHz -> info' }
It 'net wifi old'       { Assert-Equal $true (HasNote $ni24 '802.11ac/ax') 'old standard -> info' }
$niWeak = Get-NetworkInsights -Network (NetRep @(NetAdp 'Wi-Fi' 200 25 '5 GHz' '802.11ax' $null))
It 'net wifi weak'      { Assert-Equal $true (HasNote $niWeak 'Weak Wi-Fi signal') 'weak signal -> info' }
$niHealthy = Get-NetworkInsights -Network (NetRep @(NetAdp 'Wi-Fi' 324 80 '5 GHz' '802.11ax' $null))
It 'net wifi healthy'   { Assert-Equal 0 (@($niHealthy).Count) 'healthy wifi -> no note' }

Write-Host "`nSystem report (Network wiring)" -ForegroundColor Cyan
$netEth = New-NetworkReport -Adapters @([pscustomobject]@{ Name='Ethernet'; PhysicalMediaType='802.3'; SpeedBps=100000000; Wlan=$null; MaxSupportedMbps=1000 })
$sysNet = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Network $netEth
It 'sys has net note'  { Assert-Equal $true (HasNote $sysNet 'but the adapter supports') 'net note in sys insights' }
$sysNoNet = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Network $null
It 'sys null net ok'    { Assert-Equal $false (HasNote $sysNoNet 'adapter supports') 'null net -> no note, no error' }
$repNet = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Network $netEth
It 'report has net'     { Assert-Equal 'Ethernet' $repNet.Network.Adapters[0].Type 'net section in report' }
It 'report net note'    { Assert-Equal $true (HasNote $repNet.Insights 'but the adapter supports') 'net note flows to report' }
$repNoNet = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st
It 'report null net'    { Assert-Equal $null $repNoNet.Network 'no net -> null section' }

Write-Host "`nWrite-SystemConsole (Network)" -ForegroundColor Cyan
$repNetFull = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Network $netEth
$conNet = (Write-SystemConsole $repNetFull | Out-String)
It 'console net sect' { Assert-Equal $true  ([bool]($conNet -match 'Network')) 'net section present' }
It 'console net tbl'  { Assert-Equal $true  ([bool]($conNet -match 'Standard')) 'section table header (section-unique)' }
$conNoNet2 = (Write-SystemConsole $repNoNet | Out-String)
It 'console no net'   { Assert-Equal $false ([bool]($conNoNet2 -match 'Network')) 'no net -> no section' }

# =====================================================================
# GPU sensors / thermals (nvidia-smi) (slice G)
# =====================================================================

Write-Host "`nConvertFrom-NvidiaSmiCsv" -ForegroundColor Cyan
$smi = ConvertFrom-NvidiaSmiCsv -Line 'NVIDIA GeForce RTX 2060 with Max-Q Design, 50, 0, 300, 2100, 8.38, P8, Not Active, Not Active'
It 'smi name'   { Assert-Equal 'NVIDIA GeForce RTX 2060 with Max-Q Design' $smi.Name 'name' }
It 'smi temp'   { Assert-Equal 50   $smi.TempC 'temp' }
It 'smi util'   { Assert-Equal 0    $smi.UtilPercent 'util' }
It 'smi clock'  { Assert-Equal 300  $smi.ClockMHz 'clock' }
It 'smi maxclk' { Assert-Equal 2100 $smi.MaxClockMHz 'max clock' }
It 'smi power'  { Assert-Equal 8.38 $smi.PowerW 'power' }
It 'smi pstate' { Assert-Equal 'P8' $smi.PState 'pstate' }
It 'smi sw'     { Assert-Equal 'Not Active' $smi.SwThermal 'sw thermal' }
It 'smi na pwr' { Assert-Equal $null (ConvertFrom-NvidiaSmiCsv -Line 'X, 50, 0, 300, 2100, [N/A], P0, Active, Not Active').PowerW 'N/A power -> null' }
It 'smi empty'  { Assert-Equal $null (ConvertFrom-NvidiaSmiCsv -Line '').TempC 'empty -> null' }

Write-Host "`nNew-GpuSensorReport" -ForegroundColor Cyan
$gs = New-GpuSensorReport -Name 'RTX 2060' -TempC 50 -UtilPercent 0 -ClockMHz 300 -MaxClockMHz 2100 -PowerW 8.38 -PState 'P8' -SwThermal 'Not Active' -HwThermal 'Not Active'
It 'gs temp'       { Assert-Equal 50 $gs.TempC 'temp passthrough' }
It 'gs throttle0'  { Assert-Equal $false $gs.ThermalThrottle 'not active -> false' }
$gsThr = New-GpuSensorReport -Name 'RTX 2060' -TempC 88 -UtilPercent 99 -ClockMHz 1200 -MaxClockMHz 2100 -PowerW 80 -PState 'P0' -SwThermal 'Active' -HwThermal 'Not Active'
It 'gs throttle sw' { Assert-Equal $true $gsThr.ThermalThrottle 'sw active -> true' }
$gsHw = New-GpuSensorReport -Name 'x' -TempC 90 -UtilPercent 100 -ClockMHz 1000 -MaxClockMHz 2100 -PowerW 80 -PState 'P0' -SwThermal 'Not Active' -HwThermal 'Active'
It 'gs throttle hw' { Assert-Equal $true $gsHw.ThermalThrottle 'hw active -> true' }

Write-Host "`nGet-GpuSensorInsights" -ForegroundColor Cyan
$giThr = Get-GpuSensorInsights -GpuSensor $gsThr
It 'gs thr warn'  { Assert-Equal 'warn' (@($giThr)[0].Kind) 'throttle -> warn' }
It 'gs thr txt'   { Assert-Equal $true (HasNote $giThr 'thermally throttling') 'throttle text' }
$giHot = Get-GpuSensorInsights -GpuSensor (New-GpuSensorReport -Name 'x' -TempC 90 -SwThermal 'Not Active' -HwThermal 'Not Active')
It 'gs hot info'  { Assert-Equal $true (HasNote $giHot 'running hot') 'hot -> info' }
It 'gs hot kind'  { Assert-Equal 'info' (@($giHot | Where-Object { $_.Text -match 'running hot' })[0].Kind) 'hot info kind' }
$giIdle = Get-GpuSensorInsights -GpuSensor $gs
It 'gs idle none' { Assert-Equal 0 (@($giIdle).Count) 'idle 50C -> no note' }

Write-Host "`nSystem report (GpuSensor wiring)" -ForegroundColor Cyan
$sysGs = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -GpuSensor $gsThr
It 'sys has gs note' { Assert-Equal $true (HasNote $sysGs 'thermally throttling') 'gs note in sys insights' }
$sysNoGs = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -GpuSensor $null
It 'sys null gs ok'   { Assert-Equal $false (HasNote $sysNoGs 'throttling') 'null gs -> no note, no error' }
$repGs = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -GpuSensor $gs
It 'report has gs'    { Assert-Equal 50 $repGs.GpuSensor.TempC 'gs section in report' }
$repGsThr = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -GpuSensor $gsThr
It 'report gs note'   { Assert-Equal $true (HasNote $repGsThr.Insights 'thermally throttling') 'gs note flows to report' }
$repNoGs = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st
It 'report null gs'   { Assert-Equal $null $repNoGs.GpuSensor 'no gs -> null section' }

Write-Host "`nWrite-SystemConsole (GPU sensors)" -ForegroundColor Cyan
$repGsFull = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -GpuSensor $gs
$conGs = (Write-SystemConsole $repGsFull | Out-String)
It 'console gs sect' { Assert-Equal $true  ([bool]($conGs -match 'GPU sensors')) 'gs section present' }
It 'console gs temp' { Assert-Equal $true  ([bool]($conGs -match 'Temperature')) 'temp label (section-unique)' }
$conNoGs = (Write-SystemConsole $repNoGs | Out-String)
It 'console no gs'   { Assert-Equal $false ([bool]($conNoGs -match 'GPU sensors')) 'no gs -> no section' }

# =====================================================================
# Gaming capability (slice H)
# =====================================================================

Write-Host "`nGet-GpuGamingTier" -ForegroundColor Cyan
function Tier($n) { (Get-GpuGamingTier -Name $n).Rank }
It 'tier 5090'    { Assert-Equal 5 (Tier 'NVIDIA GeForce RTX 5090') 'rtx 5090' }
It 'tier 5070ti'  { Assert-Equal 4 (Tier 'NVIDIA GeForce RTX 5070 Ti') 'rtx 5070 ti' }
It 'tier 2060 desktop' { Assert-Equal 3 (Tier 'NVIDIA GeForce RTX 2060') 'desktop rtx 2060 unchanged' }
It 'tier 2060 maxq'    { Assert-Equal 2 (Tier 'NVIDIA GeForce RTX 2060 with Max-Q Design') 'max-q tiers one below desktop' }
It 'tier 5060'    { Assert-Equal 3 (Tier 'NVIDIA GeForce RTX 5060') 'rtx 5060 (not the 5090 rank)' }
It 'tier 1650'    { Assert-Equal 2 (Tier 'NVIDIA GeForce GTX 1650') 'gtx 1650' }
It 'tier 9070xt'  { Assert-Equal 5 (Tier 'AMD Radeon RX 9070 XT') 'rx 9070 xt' }
It 'tier 9070'    { Assert-Equal 4 (Tier 'AMD Radeon RX 9070') 'rx 9070 (no XT -> lower)' }
It 'tier 9060xt'  { Assert-Equal 3 (Tier 'AMD Radeon RX 9060 XT') 'rx 9060 xt' }
It 'tier b580'    { Assert-Equal 3 (Tier 'Intel Arc B580 Graphics') 'arc b580' }
It 'tier irisxe'  { Assert-Equal 1 (Tier 'Intel(R) Iris(R) Xe Graphics') 'iris xe' }
It 'tier uhd'     { Assert-Equal 1 (Tier 'Intel(R) UHD Graphics') 'intel uhd' }
It 'tier unknown' { Assert-Equal $null (Tier 'Frobozz 9000') 'unknown -> null' }
It 'tier label'   { Assert-Equal $true ([bool]((Get-GpuGamingTier -Name 'NVIDIA GeForce RTX 2060').Label -match '1080p')) 'label present' }
It 'tier 4090 laptop' { Assert-Equal 4 (Tier 'NVIDIA GeForce RTX 4090 Laptop GPU') '4090 laptop = desktop 4070 Ti class' }
It 'tier 3080 laptop' { Assert-Equal 3 (Tier 'NVIDIA GeForce RTX 3080 Laptop GPU') '3080 laptop' }
It 'tier 6800m'       { Assert-Equal 3 (Tier 'AMD Radeon RX 6800M') 'amd M suffix' }
It 'tier 4050'        { Assert-Equal 2 (Tier 'NVIDIA GeForce RTX 4050 Laptop GPU') 'laptop-native 4050 exempt from -1' }
It 'tier 1650ti maxq' { Assert-Equal 1 (Tier 'NVIDIA GeForce GTX 1650 Ti with Max-Q Design') 'floor holds at 1' }
It 'tier maxq flag'   { Assert-Equal $true  ((Get-GpuGamingTier -Name 'NVIDIA GeForce RTX 2060 with Max-Q Design').MobileVariant) 'mobile flag set' }
It 'tier desk flag'   { Assert-Equal $false ((Get-GpuGamingTier -Name 'NVIDIA GeForce RTX 2060').MobileVariant) 'desktop not mobile' }
It 'tier rank1 label' { Assert-Equal 'esports / light 1080p' ((Get-GpuGamingTier -Name 'Intel(R) UHD Graphics').Label) 'rank-1 label drops integrated-class' }
It 'tier 560m floor'  { Assert-Equal 1 (Tier 'AMD Radeon RX 560M') 'k=1 non-exempt mobile clamps at 1' }
It 'tier 1660ti mob'  { Assert-Equal 1 (Tier 'GeForce GTX 1660 Ti Mobile') 'Mobile marker detected + stripped' }

Write-Host "`nNew-GpuReport (display fields)" -ForegroundColor Cyan
$gpuDisp = New-GpuReport -Gpus @([pscustomobject]@{ Name='Intel UHD'; Vendor='Intel'; AdapterRamBytes=1073741824; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=1920; ResV=1200; ResRefresh=60 }) -Now ([datetime]'2026-07-01')
It 'gpu refresh'   { Assert-Equal 60   $gpuDisp.Gpus[0].RefreshHz 'refresh hz' }
It 'gpu reswidth'  { Assert-Equal 1920 $gpuDisp.Gpus[0].ResWidth 'res width' }
It 'gpu resheight' { Assert-Equal 1200 $gpuDisp.Gpus[0].ResHeight 'res height' }
$gpuNoDisp = New-GpuReport -Gpus @([pscustomobject]@{ Name='RTX 2060'; Vendor='NVIDIA'; AdapterRamBytes=6442450944; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=8; ResH=0; ResV=0; ResRefresh=0 }) -Now ([datetime]'2026-07-01')
It 'gpu no refresh' { Assert-Equal $null $gpuNoDisp.Gpus[0].RefreshHz 'no display -> null refresh' }

Write-Host "`nNew-GamingReport" -ForegroundColor Cyan
$gGpu = New-GpuReport -Gpus @(
    [pscustomobject]@{ Name='NVIDIA GeForce RTX 2060 with Max-Q Design'; Vendor='NVIDIA'; AdapterRamBytes=6442450944; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=8; ResH=0; ResV=0; ResRefresh=0 }
    [pscustomobject]@{ Name='Intel(R) UHD Graphics'; Vendor='Intel'; AdapterRamBytes=1073741824; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=1920; ResV=1200; ResRefresh=60 }
) -Now ([datetime]'2026-07-01')
$gStorage = New-StorageReport -Disks @([pscustomobject]@{ Name='NVMe X'; MediaType='SSD'; BusType='NVMe'; SizeBytes=512000000000; Health='Healthy'; IsBoot=$true }) -Volumes @()
$gm = New-GamingReport -Gpu $gGpu -Cpu $cpuDev -Memory $memDual -Storage $gStorage
It 'gaming gpu'      { Assert-Equal 'NVIDIA GeForce RTX 2060 with Max-Q Design' $gm.GpuName 'picks the discrete GPU' }
It 'gaming rank'     { Assert-Equal 2 $gm.Rank 'max-q adjusted rank 2' }
It 'gaming verdict'  { Assert-Equal $true ([bool]($gm.Verdict -match '1080p mainstream')) 'adjusted verdict label' }
It 'gaming refresh'  { Assert-Equal 60 $gm.RefreshHz 'display refresh from the UHD adapter' }
It 'gaming vram lim' { Assert-Equal $true ([bool](($gm.Limiters -join ',') -match 'VRAM')) '6 GB VRAM limiter' }
It 'gaming hz lim'   { Assert-Equal $true ([bool](($gm.Limiters -join ',') -match 'Hz')) '60 Hz limiter' }

$hiGpu = New-GpuReport -Gpus @([pscustomobject]@{ Name='NVIDIA GeForce RTX 5080'; Vendor='NVIDIA'; AdapterRamBytes=17179869184; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=3840; ResV=2160; ResRefresh=144 }) -Now ([datetime]'2026-07-01')
$hiMem = New-MemoryReport -Modules @([pscustomobject]@{ Slot='A'; CapacityBytes=17179869184; RatedSpeed=6000; CurrentSpeed=6000; VendorRaw='x'; PartNumber='y'; TypeCode=34 }, [pscustomobject]@{ Slot='B'; CapacityBytes=17179869184; RatedSpeed=6000; CurrentSpeed=6000; VendorRaw='x'; PartNumber='y'; TypeCode=34 }) -MaxCapacityBytes 137438953472 -TotalSlots 2 -BoardMaker x -BoardModel y -BoardVersion z
$hiGm = New-GamingReport -Gpu $hiGpu -Cpu $cpuDev -Memory $hiMem -Storage $gStorage
It 'gaming hi rank'  { Assert-Equal 5 $hiGm.Rank 'rtx 5080 -> 5' }
It 'gaming hi none'  { Assert-Equal 0 (@($hiGm.Limiters).Count) 'high-end -> no limiters' }

$igGpu = New-GpuReport -Gpus @([pscustomobject]@{ Name='Intel(R) UHD Graphics'; Vendor='Intel'; AdapterRamBytes=1073741824; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=1920; ResV=1080; ResRefresh=60 }) -Now ([datetime]'2026-07-01')
$igGm = New-GamingReport -Gpu $igGpu -Cpu $cpuDev -Memory $memDual -Storage $gStorage
It 'gaming ig disc'  { Assert-Equal $false $igGm.IsDiscrete 'integrated only' }
It 'gaming ig lim'   { Assert-Equal $true ([bool](($igGm.Limiters -join ',') -match 'no discrete')) 'no-discrete limiter' }

$gmDeskGpu = New-GpuReport -Gpus @([pscustomobject]@{ Name='NVIDIA GeForce RTX 2060'; Vendor='NVIDIA'; AdapterRamBytes=6442450944; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=1920; ResV=1080; ResRefresh=60 }) -Now ([datetime]'2026-07-01')
$gmDesk = New-GamingReport -Gpu $gmDeskGpu -Cpu $cpuDev -Memory $memDual -Storage $gStorage
It 'gaming desk rank' { Assert-Equal 3 $gmDesk.Rank 'desktop 2060 stays rank 3' }
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

$gi4 = Get-GamingInsights -Gaming $gm4
It 'game core note'   { Assert-Equal $true (HasNote $gi4 'want 6+ CPU cores') 'low-core note fires at rank 3' }
It 'game core kind'   { Assert-Equal 'info' (@($gi4 | Where-Object { $_.Text -match 'CPU cores' })[0].Kind) 'low-core note is info' }
$gm4Lo = New-GamingReport -Gpu $gGpu -Cpu $cpu4 -Memory $memDual -Storage $gStorage
It 'game core gated'  { Assert-Equal $false (HasNote (Get-GamingInsights -Gaming $gm4Lo) 'want 6+ CPU cores') 'gated off at rank 2' }
It 'game core 8c off' { Assert-Equal $false (HasNote (Get-GamingInsights -Gaming $gmDesk) 'want 6+ CPU cores') '8 cores silent' }

$gm30 = New-GamingReport -Gpu (New-GpuReport -Gpus @([pscustomobject]@{ Name='NVIDIA GeForce RTX 2060'; Vendor='NVIDIA'; AdapterRamBytes=6442450944; RegistryVramBytes=$null; DriverVersion='x'; DriverDate=$null; Availability=3; ResH=3840; ResV=2160; ResRefresh=30 }) -Now ([datetime]'2026-07-01')) -Cpu $cpuDev -Memory $memDual -Storage $gStorage
It 'gaming 30 wording' { Assert-Equal $true ($gm30.Limiters -contains '30 Hz display') 'sub-59 keeps measured number' }
$gm0 = New-GamingReport -Gpu $gmDeskGpu -Cpu (New-CpuReport -Name 'bad read' -Cores 0 -Threads 0 -AddressWidth 64 -MemoryType 'DDR4') -Memory $memDual -Storage $gStorage
It 'gaming 0core lim'  { Assert-Equal $false ([bool](($gm0.Limiters -join ',') -match 'core CPU')) 'cores=0 bad read stays silent' }
It 'game core 0c off'  { Assert-Equal $false (HasNote (Get-GamingInsights -Gaming $gm0) 'want 6+ CPU cores') 'cores=0 note silent' }

Write-Host "`nGet-GamingInsights" -ForegroundColor Cyan
$giVram = Get-GamingInsights -Gaming $gm
It 'game vram info'  { Assert-Equal $true (HasNote $giVram 'VRAM') 'low VRAM note' }
It 'game vram kind'  { Assert-Equal 'info' (@($giVram | Where-Object { $_.Text -match 'VRAM' })[0].Kind) 'vram info kind' }
It 'game 60hz gated' { Assert-Equal $false (HasNote $giVram 'caps what you see') '60 Hz note gated off at rank 2' }
It 'game 60hz info'  { Assert-Equal $true (HasNote (Get-GamingInsights -Gaming $gmDesk) 'caps what you see') '60 Hz note fires at rank 3' }
$giHi = Get-GamingInsights -Gaming $hiGm
It 'game hi none'    { Assert-Equal 0 (@($giHi).Count) 'high-end -> no notes' }
$giIg = Get-GamingInsights -Gaming $igGm
It 'game ig warn'    { Assert-Equal 'warn' (@($giIg | Where-Object { $_.Text -match 'No discrete' })[0].Kind) 'no-discrete warn' }

Write-Host "`nSystem report (Gaming wiring)" -ForegroundColor Cyan
$repGame = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gGpu -Storage $gStorage
It 'report has gaming'  { Assert-Equal 2 $repGame.Gaming.Rank 'gaming section computed into report (max-q adjusted)' }
It 'report gaming note' { Assert-Equal $true (HasNote $repGame.Insights 'VRAM') 'gaming note flows to report' }

Write-Host "`nWrite-SystemConsole (Gaming + memory footnote)" -ForegroundColor Cyan
$conGame = (Write-SystemConsole $repGame | Out-String)
It 'console gaming sect'    { Assert-Equal $true ([bool]($conGame -match 'Overall')) 'gaming section present (Overall label)' }
It 'console gaming verdict' { Assert-Equal $true ([bool]($conGame -match '1080p mainstream')) 'adjusted verdict shown' }
It 'console mem footnote'   { Assert-Equal $true ([bool]($conGame -match 'CPU-Z')) 'memory MT/s footnote' }
It 'console gaming laptop' { Assert-Equal $true ([bool]($conGame -match '\(laptop GPU\)')) 'laptop qualifier on Overall' }
It 'console gaming storage' { Assert-Equal $true ([bool]($conGame -match 'NVMe SSD boot drive')) 'Storage line rendered' }
It 'console gaming caption' { Assert-Equal $true ([bool]($conGame -match 'one rank below')) 'laptop tier rule in caption' }
$repGameNoSt = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gGpu
It 'console gaming st unk'  { Assert-Equal $true ([bool]((Write-SystemConsole $repGameNoSt | Out-String) -match 'Storage\s+: Unknown')) 'Storage Unknown fallback' }

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

Write-Host "`nSystem report (Upgrade wiring)" -ForegroundColor Cyan
$repUp = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Battery $batDev
It 'report has upgrade'   { Assert-Equal $true $repUp.Upgrade.HasAny 'upgrade section computed into report' }
It 'report upgrade bat'   { Assert-Equal $true (UpHas $repUp.Upgrade 'Replace the worn battery') 'battery rec present in report' }
# The advisor must NOT inject its Action text into the notes (no duplication).
$repUpHdd = New-SystemReport -Cpu $cpuVirtOn -Memory $memDual -Storage $stHdd
It 'upgrade no notes'     { Assert-Equal $false (HasNote $repUpHdd.Insights 'Move Windows to an SSD') 'advisor emits no notes' }

Write-Host "`nWrite-SystemConsole (Upgrade Advisor)" -ForegroundColor Cyan
$conUp = (Write-SystemConsole $repUp | Out-String)
It 'console upgrade sect'  { Assert-Equal $true ([bool]($conUp -match 'Upgrade Advisor')) 'upgrade section present' }
It 'console upgrade hw'    { Assert-Equal $true ([bool]($conUp -match 'Hardware upgrades')) 'hardware group present' }
$repUpGood = New-SystemReport -Cpu $cpuVirtOn -Memory $memDual -Gpu $gpuFresh -Storage $stGood -Battery $batGood
$conUpGood = (Write-SystemConsole $repUpGood | Out-String)
It 'console upgrade empty' { Assert-Equal $true ([bool]($conUpGood -match 'No upgrades suggested')) 'empty-state line' }

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

Write-Host "`nGet-FirmwareInsights" -ForegroundColor Cyan
It 'fw note sb off'     { Assert-Equal $true (HasNote (Get-FirmwareInsights -Firmware $fwSbOff) 'Secure Boot is supported but turned off') 'sb off note' }
It 'fw note legacy'     { Assert-Equal $true (HasNote (Get-FirmwareInsights -Firmware $fwLegacy) 'Legacy (CSM) mode') 'legacy note' }
It 'fw note no tpm'     { Assert-Equal $true (HasNote (Get-FirmwareInsights -Firmware $fwLegacy) 'No TPM detected') 'no tpm note' }
It 'fw healthy no note' { Assert-Equal 0 ((Get-FirmwareInsights -Firmware $fwWin11).Count) 'healthy none' }
It 'fw null no note'    { Assert-Equal 0 ((Get-FirmwareInsights -Firmware $null).Count) 'null none' }
It 'fw notes all info'  { Assert-Equal 'info' ((@(Get-FirmwareInsights -Firmware $fwLegacy) | ForEach-Object { $_.Kind } | Sort-Object -Unique) -join ',') 'info kind' }

Write-Host "`nSystem report (Firmware wiring)" -ForegroundColor Cyan
$sysFw = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $fwSbOff
It 'fw wiring note'    { Assert-Equal $true  (HasNote $sysFw 'Secure Boot is supported but turned off') 'wired' }
$sysNoFw = Get-SystemInsights -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $null
It 'fw wiring null ok' { Assert-Equal $false (HasNote $sysNoFw 'Secure Boot') 'null no note' }
$repFw = New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $fwWin11
It 'fw report section' { Assert-Equal 'UEFI' $repFw.Firmware.FirmwareType 'section' }
It 'fw report no arg'  { Assert-Equal '' "$((New-SystemReport -Cpu $cpuDev -Memory $memDual).Firmware)" 'null default' }

Write-Host "`nWrite-SystemConsole (Firmware & Security)" -ForegroundColor Cyan
$conFw = (Write-SystemConsole (New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st -Firmware $fwWin11) | Out-String)
It 'fw console header'    { Assert-Equal $true ([bool]($conFw -match 'Firmware & Security')) 'header' }
It 'fw console tpm'       { Assert-Equal $true ([bool]($conFw -match 'TPM')) 'tpm' }
It 'fw console readiness' { Assert-Equal $true ([bool]($conFw -match 'Windows 11 readiness')) 'readiness' }
It 'fw console verdict'   { Assert-Equal $true ([bool]($conFw -match 'running Windows 11')) 'verdict' }
$conNoFw = (Write-SystemConsole (New-SystemReport -Cpu $cpuDev -Memory $memDual -Gpu $gpu -Storage $st) | Out-String)
It 'fw console absent'    { Assert-Equal $false ([bool]($conNoFw -match 'Firmware & Security')) 'absent' }

# =====================================================================
# Benchmarks (slice L)
# =====================================================================

Write-Host "`nNew-BenchmarkReport" -ForegroundColor Cyan
$benchRawFull = [pscustomobject]@{
    CpuStMops = 1014; CpuMtMops = 11080; ThreadCount = 16
    MemStGBps = 19.3; MemMtGBps = 34.0; MemSkippedReason = $null
    DiskSeqMBps = 1186; DiskRandIops = 5135; DiskSkippedReason = $null; DiskDrive = 'C:'
    ElapsedS = 11.5
}
$benchBat = New-BatteryReport -ChargePercent 100 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 95065 -FullChargeCapacityMWh 52166 -CycleCount 0 -Chemistry 'LiP' -Manufacturer 'SMP' -PowerPlan 'Balanced' -PowerPlanGuid 'x'
$bm = New-BenchmarkReport -Raw $benchRawFull -Memory $memDual -Battery $benchBat -RanAt ([datetime]'2026-07-05 10:00')
It 'bench cpu st'      { Assert-Equal 1014 $bm.Cpu.StMops 'st mops' }
It 'bench cpu scale'   { Assert-Equal 10.9 $bm.Cpu.Scale 'mt/st scale 1 decimal' }
It 'bench theo dual'   { Assert-Equal 46.9 $bm.Memory.TheoreticalGBps '2ch x 8B x 2933 = 46.9' }
It 'bench theo label'  { Assert-Equal 'assumes dual-channel' $bm.Memory.ChannelAssumption 'dual label' }
It 'bench rand mbps'   { Assert-Equal 21 $bm.Disk.RandMBps '5135 iops x 4096 = 21.0 MB/s' }
It 'bench ctx ac'      { Assert-Equal $true $bm.Context.OnAC 'on AC from battery section' }
It 'bench ctx plan'    { Assert-Equal 'Balanced' $bm.Context.PowerPlan 'plan from battery section' }
It 'bench ok'          { Assert-Equal $true $bm.Ok 'measured -> ok' }
$bmSingle = New-BenchmarkReport -Raw $benchRawFull -Memory $memSingle -Battery $null -RanAt ([datetime]'2026-07-05 10:00')
It 'bench theo single' { Assert-Equal 25.6 $bmSingle.Memory.TheoreticalGBps '1ch x 8B x 3200 = 25.6' }
It 'bench single lbl'  { Assert-Equal '1 module = 1 channel' $bmSingle.Memory.ChannelAssumption 'single label' }
It 'bench no battery'  { Assert-Equal $null $bmSingle.Context.OnAC 'no battery -> null context' }
$memNoSpeed = New-MemoryReport -Modules @([pscustomobject]@{ Slot='A'; CapacityBytes=8589934592; RatedSpeed=0; CurrentSpeed=0; VendorRaw='x'; PartNumber='y'; TypeCode=26 }) -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker x -BoardModel y
$bmNoSpeed = New-BenchmarkReport -Raw $benchRawFull -Memory $memNoSpeed -Battery $null -RanAt ([datetime]'2026-07-05 10:00')
It 'bench theo unknown' { Assert-Equal $null $bmNoSpeed.Memory.TheoreticalGBps 'unknown speed -> null theoretical' }
$bmNoSlots = New-BenchmarkReport -Raw $benchRawFull -Memory ([pscustomobject]@{ RunningSpeed = 2933; PopulatedSlots = 0 }) -Battery $null -RanAt ([datetime]'2026-07-05 10:00')
It 'bench theo no slots' { Assert-Equal $null $bmNoSlots.Memory.TheoreticalGBps 'unknown slot count -> null theoretical' }
$benchRawSkips = [pscustomobject]@{
    CpuStMops = 1014; CpuMtMops = 11080; ThreadCount = 16
    MemStGBps = $null; MemMtGBps = $null; MemSkippedReason = 'low available memory (1.0 GB)'
    DiskSeqMBps = $null; DiskRandIops = $null; DiskSkippedReason = 'low free space on C: (3.2 GB)'; DiskDrive = 'C:'
    ElapsedS = 4.0
}
$bmSkips = New-BenchmarkReport -Raw $benchRawSkips -Memory $memDual -Battery $null -RanAt ([datetime]'2026-07-05 10:00')
It 'bench mem skip'    { Assert-Equal 'low available memory (1.0 GB)' $bmSkips.Memory.SkippedReason 'mem skip reason surfaced' }
It 'bench disk skip'   { Assert-Equal 'low free space on C: (3.2 GB)' $bmSkips.Disk.SkippedReason 'disk skip reason surfaced' }
It 'bench skip ok'     { Assert-Equal $true $bmSkips.Ok 'cpu still measured -> ok' }
$benchRawNull = [pscustomobject]@{
    CpuStMops = $null; CpuMtMops = $null; ThreadCount = $null
    MemStGBps = $null; MemMtGBps = $null; MemSkippedReason = $null
    DiskSeqMBps = $null; DiskRandIops = $null; DiskSkippedReason = $null; DiskDrive = $null
    ElapsedS = 0.1
}
$bmNull = New-BenchmarkReport -Raw $benchRawNull -Memory $null -Battery $null -RanAt ([datetime]'2026-07-05 10:00')
It 'bench all null ok' { Assert-Equal $false $bmNull.Ok 'nothing measured -> not ok' }
It 'bench null theo'   { Assert-Equal $null $bmNull.Memory.TheoreticalGBps 'no memory section -> null' }
It 'bench ranat'       { Assert-Equal ([datetime]'2026-07-05 10:00') $bm.Context.RanAt 'RanAt passed through (deterministic)' }

Write-Host "`nSystem report (Benchmark placeholder)" -ForegroundColor Cyan
$repBenchPh = New-SystemReport -Cpu $cpuDev -Memory $memDual
It 'bench placeholder' { Assert-Equal $true ($repBenchPh.PSObject.Properties.Name -contains 'Benchmark') 'report has Benchmark property' }
It 'bench ph null'     { Assert-Equal $null $repBenchPh.Benchmark 'placeholder starts null' }

$bmEmptyPlan = New-BenchmarkReport -Raw $benchRawFull -Memory $memDual -Battery (New-BatteryReport -ChargePercent 50 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 1 -FullChargeCapacityMWh 1 -CycleCount 0 -Chemistry 'x' -Manufacturer 'y' -PowerPlan '' -PowerPlanGuid 'z') -RanAt ([datetime]'2026-07-05 10:00')
It 'bench empty plan'  { Assert-Equal $null $bmEmptyPlan.Context.PowerPlan 'empty PowerPlan string -> null' }
$bmNoMt = New-BenchmarkReport -Raw ([pscustomobject]@{ CpuStMops = 1014; CpuMtMops = $null; ThreadCount = 16; MemStGBps = $null; MemMtGBps = $null; MemSkippedReason = $null; DiskSeqMBps = $null; DiskRandIops = $null; DiskSkippedReason = $null; DiskDrive = $null; ElapsedS = 2.0 }) -Memory $memDual -Battery $null -RanAt ([datetime]'2026-07-05 10:00')
It 'bench scale null'  { Assert-Equal $null $bmNoMt.Cpu.Scale 'MT missing -> null scale, no crash' }

Write-Host "`nWrite-SystemConsole (Benchmarks)" -ForegroundColor Cyan
$repBench = New-SystemReport -Cpu $cpuDev -Memory $memDual
$repBench.Benchmark = $bm
$conBench = (Write-SystemConsole $repBench | Out-String)
It 'bench console sect'  { Assert-Equal $true ([bool]($conBench -match 'Benchmarks')) 'Benchmarks section present' }
It 'bench console cpu'   { Assert-Equal $true ([bool]($conBench -match 'arith Mops/s single-thread')) 'cpu line' }
It 'bench console theo'  { Assert-Equal $true ([bool]($conBench -match 'theoretical peak ~46.9 GB/s')) 'memory theoretical' }
It 'bench console disk'  { Assert-Equal $true ([bool]($conBench -match 'IOPS random 4K')) 'disk line' }
It 'bench console ctx'   { Assert-Equal $true ([bool]($conBench -match 'on AC power, Balanced plan, 2026-07-05 10:00')) 'context line' }
It 'bench console qd1'   { Assert-Equal $true ([bool]($conBench -match 'single-stream/QD1')) 'honesty caption' }
$repBenchSkip = New-SystemReport -Cpu $cpuDev -Memory $memDual
$repBenchSkip.Benchmark = $bmSkips
$conBenchSkip = (Write-SystemConsole $repBenchSkip | Out-String)
It 'bench console skip'  { Assert-Equal $true ([bool]($conBenchSkip -match 'Unavailable \(low available memory')) 'skip reason rendered' }
$conNoBench = (Write-SystemConsole (New-SystemReport -Cpu $cpuDev -Memory $memDual) | Out-String)
It 'bench console absent' { Assert-Equal $false ([bool]($conNoBench -match 'Benchmarks')) 'no run -> no section' }
$repBenchNull = New-SystemReport -Cpu $cpuDev -Memory $memDual
$repBenchNull.Benchmark = $bmNull
It 'bench console null'  { Assert-Equal $true ([bool]((Write-SystemConsole $repBenchNull | Out-String) -match 'CPU              : Unavailable')) 'all-null bundle renders Unavailable lines' }

# =====================================================================
# Startup progress (slice M)
# =====================================================================

Write-Host "`nInvoke-LoadStep" -ForegroundColor Cyan
It 'ls quiet ret'    { Assert-Equal 42 (Invoke-LoadStep -Label 'M' -Action { 42 } -Show:$false) 'quiet returns the action value' }
It 'ls show ret'     { Assert-Equal 42 (Invoke-LoadStep -Label 'M' -Action { 42 } -Show:$true 6>&1 | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] }) 'showing still returns the value' }
It 'ls array'        { Assert-Equal 3 (@(Invoke-LoadStep -Label 'M' -Action { 1, 2, 3 } -Show:$false)).Count 'array output round-trips' }
It 'ls null'         { Assert-Equal $true ($null -eq (Invoke-LoadStep -Label 'M' -Action { $null } -Show:$false)) 'null passes through (no-battery desktop path)' }
$lsQuiet = @(Invoke-LoadStep -Label 'ZZTOP' -Action { 'v' } -Show:$false 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
It 'ls quiet silent' { Assert-Equal 0 $lsQuiet.Count 'quiet prints nothing (console/benchmark gating)' }
$lsLoud = @(Invoke-LoadStep -Label 'ZZTOP' -Action { 'v' } -Show:$true 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
It 'ls show prints'  { Assert-Equal $true ([bool](($lsLoud -join '') -match 'ZZTOP')) 'showing prints the label' }

Write-Host "`n$script:Pass passed, $script:Fail failed`n"
if ($script:Fail) { exit 1 } else { exit 0 }
