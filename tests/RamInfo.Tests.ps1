# Lightweight zero-dependency test harness for Show-RamInfo.ps1
# Run:  pwsh -File tests\RamInfo.Tests.ps1
$ErrorActionPreference = 'Continue'
$env:RAMINFO_NOMAIN = '1'          # tell the script not to run its GUI/main on dot-source
. "$PSScriptRoot\..\Show-RamInfo.ps1"

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
It 'space -> Unknown'{ Assert-Equal 'Unknown'  (ConvertTo-VendorName '   ')              'whitespace' }
It 'null -> Unknown' { Assert-Equal 'Unknown'  (ConvertTo-VendorName $null)              'null' }

Write-Host "`nNew-RamReport" -ForegroundColor Cyan
$mods = @(
    [pscustomobject]@{ Slot='DIMM A'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
    [pscustomobject]@{ Slot='DIMM B'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
)
$r = New-RamReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03'
It 'total installed GB' { Assert-Equal 16   $r.TotalInstalledGB     'sum 2x8' }
It 'populated slots'    { Assert-Equal 2    $r.PopulatedSlots       'count' }
It 'free slots zero'    { Assert-Equal 0    $r.FreeSlots            '2-2' }
It 'type name'          { Assert-Equal DDR4 $r.TypeName             'code 26' }
It 'max capacity GB'    { Assert-Equal 64   $r.MaxCapacityGB        '64GB' }
It 'board string'       { Assert-Equal 'Dell 0CXCCY (rev A03)' $r.Board 'maker+model+rev' }
It 'module size GB'     { Assert-Equal 8    $r.Modules[0].SizeGB    'per-stick 8' }
It 'module vendor'      { Assert-Equal 'SK Hynix' $r.Modules[0].Vendor 'decoded' }
It 'module rated'       { Assert-Equal 3200 $r.Modules[0].Rated     'rated' }
It 'module current'     { Assert-Equal 2933 $r.Modules[0].Current   'current' }

$r4 = New-RamReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 4 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03'
It 'free slots 4-2'     { Assert-Equal 2 $r4.FreeSlots 'two free' }

$rNoVer = New-RamReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion ''
It 'board no version'   { Assert-Equal 'Dell 0CXCCY' $rNoVer.Board 'omit rev' }

$modEdge = @([pscustomobject]@{ Slot='DIMM A'; CapacityBytes=8589934592; RatedSpeed=$null; CurrentSpeed=0; VendorRaw='80AD00000000'; PartNumber='   '; TypeCode=26 })
$rEdge = New-RamReport -Modules $modEdge -MaxCapacityBytes $null -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03'
It 'null rated Unknown'   { Assert-Equal 'Unknown' $rEdge.Modules[0].Rated   'rated null' }
It 'zero current Unknown' { Assert-Equal 'Unknown' $rEdge.Modules[0].Current 'current 0' }
It 'blank part Unknown'   { Assert-Equal 'Unknown' $rEdge.Modules[0].Part    'part blank' }
It 'null maxcap null'     { Assert-Equal $null     $rEdge.MaxCapacityGB      'unknown maxcap' }

$rEmpty = New-RamReport -Modules @() -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03'
It 'empty total 0'      { Assert-Equal 0 $rEmpty.TotalInstalledGB 'no modules' }
It 'empty populated 0'  { Assert-Equal 0 $rEmpty.PopulatedSlots   'none' }
It 'empty type Unknown' { Assert-Equal 'Unknown' $rEmpty.TypeName 'no first' }
It 'empty free = slots' { Assert-Equal 2 $rEmpty.FreeSlots        'all free' }
It 'empty modules array'{ Assert-Equal 0 $rEmpty.Modules.Count    'no phantom' }

Write-Host "`nGet-CpuMemorySpec" -ForegroundColor Cyan
function SpecSpeed($name, $type) { (Get-CpuMemorySpec -Name $name -MemoryType $type).MaxSpeed }
function SpecKnown($name)        { (Get-CpuMemorySpec -Name $name -MemoryType 'DDR4').Known }
function SpecLabel($name, $type) { (Get-CpuMemorySpec -Name $name -MemoryType $type).Label }

# Intel
It 'i7-10875H'     { Assert-Equal 2933 (SpecSpeed 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' 'DDR4') 'gen10 H' }
It 'i5-10400'      { Assert-Equal 2666 (SpecSpeed 'Intel(R) Core(TM) i5-10400 CPU @ 2.90GHz' 'DDR4') 'gen10 i5 desktop' }
It 'i9-10900K'     { Assert-Equal 2933 (SpecSpeed 'Intel(R) Core(TM) i9-10900K' 'DDR4') 'gen10 i9' }
It 'i7-1065G7'     { Assert-Equal 2933 (SpecSpeed 'Intel(R) Core(TM) i7-1065G7 CPU @ 1.30GHz' 'DDR4') 'gen10 4-digit' }
It 'i7-1255U'      { Assert-Equal 3200 (SpecSpeed 'Intel(R) Core(TM) i7-1255U' 'DDR4') 'gen12 4-digit DDR4' }
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
# AMD
It 'Ryzen 5800X'   { Assert-Equal 3200 (SpecSpeed 'AMD Ryzen 7 5800X 8-Core Processor' 'DDR4') 'zen3' }
It 'Ryzen 3600'    { Assert-Equal 3200 (SpecSpeed 'AMD Ryzen 5 3600 6-Core Processor' 'DDR4') 'zen2' }
It 'Ryzen 2700X'   { Assert-Equal 2933 (SpecSpeed 'AMD Ryzen 7 2700X Eight-Core Processor' 'DDR4') 'zen+' }
It 'Ryzen 1600'    { Assert-Equal 2667 (SpecSpeed 'AMD Ryzen 5 1600 Six-Core Processor' 'DDR4') 'zen1' }
It 'Ryzen 7950X'   { Assert-Equal 5200 (SpecSpeed 'AMD Ryzen 9 7950X 16-Core Processor' 'DDR5') 'zen4' }
It 'Ryzen 9950X'   { Assert-Equal 5600 (SpecSpeed 'AMD Ryzen 9 9950X 16-Core Processor' 'DDR5') 'zen5' }
It 'Ryzen 6900HS'  { Assert-Equal 4800 (SpecSpeed 'AMD Ryzen 9 6900HS Creator Edition' 'DDR5') 'zen3+' }
# Unknown
It 'Xeon unknown'    { Assert-Equal $false (SpecKnown 'Intel(R) Xeon(R) W-2245 CPU @ 3.90GHz') 'xeon' }
It 'Threadripper'    { Assert-Equal $false (SpecKnown 'AMD Ryzen Threadripper 3960X 24-Core Processor') 'tr' }
It 'Pentium unknown' { Assert-Equal $false (SpecKnown 'Intel(R) Pentium(R) Gold G6400 CPU @ 4.00GHz') 'pentium' }
It 'empty unknown'   { Assert-Equal $false (SpecKnown '') 'empty' }
# Labels
It 'label ddr4'    { Assert-Equal 'DDR4-2933' (SpecLabel 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' 'DDR4') 'label4' }
It 'label ddr5'    { Assert-Equal 'DDR5-4800' (SpecLabel '12th Gen Intel(R) Core(TM) i7-12700H' 'DDR5') 'label5' }

Write-Host "`nGet-RamInsights" -ForegroundColor Cyan
function HasNote($ins, $sub) { [bool](@($ins) | Where-Object { $_.Text -match [regex]::Escape($sub) }) }

$i = Get-RamInsights -RunningSpeed 2933 -ModuleRatedSpeeds @(3200,3200) -CpuMaxSpeed 2933 -CpuName 'i7-10875H' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'cpu-capped note'   { Assert-Equal $true  (HasNote $i 'CPU is the limiter') 'limiter' }
It 'no single-channel' { Assert-Equal $false (HasNote $i 'Single-channel')      'dual ok' }
It 'capacity replace'  { Assert-Equal $true  (HasNote $i 'replacing modules')   'full below max' }

$sc = Get-RamInsights -RunningSpeed 3200 -ModuleRatedSpeeds @(3200) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 1 -TotalSlots 2 -InstalledGB 8 -MaxCapacityGB 64
It 'single-channel warn' { Assert-Equal $true (HasNote $sc 'Single-channel') 'one stick' }
It 'free slot note'      { Assert-Equal $true (HasNote $sc 'free slot')      'has free' }

$mx = Get-RamInsights -RunningSpeed 2666 -ModuleRatedSpeeds @(3200,2666) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'mixed speeds warn'  { Assert-Equal $true (HasNote $mx 'Mixed module speeds') 'mixed' }

$cfg = Get-RamInsights -RunningSpeed 2133 -ModuleRatedSpeeds @(3200,3200) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'config xmp warn'    { Assert-Equal $true (HasNote $cfg 'XMP') 'enable xmp' }

$ml = Get-RamInsights -RunningSpeed 2666 -ModuleRatedSpeeds @(2666,2666) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'module-limited info'{ Assert-Equal $true (HasNote $ml 'faster modules') 'modules slow' }

$bal = Get-RamInsights -RunningSpeed 3200 -ModuleRatedSpeeds @(3200,3200) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 16 -MaxCapacityGB 64
It 'balanced ok'        { Assert-Equal $true (HasNote $bal 'maximum this CPU') 'balanced' }

$uk = Get-RamInsights -RunningSpeed 2133 -ModuleRatedSpeeds @(3200) -CpuMaxSpeed $null -CpuName 'x' -PopulatedSlots 1 -TotalSlots 1 -InstalledGB 8 -MaxCapacityGB 16
It 'unknown cpu xmp'    { Assert-Equal $true (HasNote $uk 'XMP') 'below rating' }

$uk2 = Get-RamInsights -RunningSpeed 3200 -ModuleRatedSpeeds @(3200) -CpuMaxSpeed $null -CpuName 'x' -PopulatedSlots 1 -TotalSlots 1 -InstalledGB 8 -MaxCapacityGB 16
It 'unknown cpu ok'     { Assert-Equal $true (HasNote $uk2 'module rated speed') 'at rating' }

$cap = Get-RamInsights -RunningSpeed 3200 -ModuleRatedSpeeds @(3200,3200) -CpuMaxSpeed 3200 -CpuName 'x' -PopulatedSlots 2 -TotalSlots 2 -InstalledGB 64 -MaxCapacityGB 64
It 'at max capacity'    { Assert-Equal $true (HasNote $cap 'maximum capacity') 'maxed' }

Write-Host "`nNew-RamReport + CPU/insights integration" -ForegroundColor Cyan
$rCpu = New-RamReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell' -BoardModel '0CXCCY' -BoardVersion 'A03' -CpuName 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz'
It 'report max speed label' { Assert-Equal 'DDR4-2933' $rCpu.MaxSpeedLabel 'cpu label' }
It 'report max speed known' { Assert-Equal $true $rCpu.MaxSpeedKnown 'known' }
It 'report has insights'    { Assert-Equal $true (@($rCpu.Insights).Count -gt 0) 'insights present' }
It 'report cpu-capped note' { Assert-Equal $true (HasNote $rCpu.Insights 'CPU is the limiter') 'capped' }
It 'report cpu display'     { Assert-Equal 'Intel Core i7-10875H' $rCpu.CpuName 'cleaned name' }

Write-Host "`nFormat-CpuName" -ForegroundColor Cyan
It 'intel clean'   { Assert-Equal 'Intel Core i7-10875H' (Format-CpuName 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz') 'intel' }
It 'amd clean'     { Assert-Equal 'AMD Ryzen 7 5800X'     (Format-CpuName 'AMD Ryzen 7 5800X 8-Core Processor') 'amd' }
It 'amd words'     { Assert-Equal 'AMD Ryzen 5 1600'      (Format-CpuName 'AMD Ryzen 5 1600 Six-Core Processor') 'amd words' }
It 'cpuname empty' { Assert-Equal '' (Format-CpuName '') 'empty' }

Write-Host "`n$script:Pass passed, $script:Fail failed`n"
if ($script:Fail) { exit 1 } else { exit 0 }
