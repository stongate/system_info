# Headless smoke test for the tabbed WinForms window: builds the form via
# New-SystemForm (no ShowDialog) and checks its structure. Run under Windows
# PowerShell (STA):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\GuiSmoke.ps1
$env:SYSTEMINFO_NOMAIN = '1'
. "$PSScriptRoot\..\Show-SystemInfo.ps1"

$script:fail = 0
function Check($Cond, $Name) {
    if ($Cond) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:fail++ }
}

$mods = @(
    [pscustomobject]@{ Slot='DIMM A'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
    [pscustomobject]@{ Slot='DIMM B'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
)
$cpu = New-CpuReport -Name 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz' -Cores 8 -Threads 16 -MaxClockMHz 2304 `
                     -L2CacheKB 2048 -L3CacheKB 16384 -Socket 'CPU 1' -AddressWidth 64 -VirtualizationEnabled $false -MemoryType 'DDR4'
$mem = New-MemoryReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell Inc.' -BoardModel '0CXCCY' -BoardVersion 'A03'
$rawGpus = @(
    [pscustomobject]@{ Name='NVIDIA GeForce RTX 2060 with Max-Q Design'; Vendor='NVIDIA'; AdapterRamBytes=4293918720; RegistryVramBytes=6442450944; DriverVersion='32.0.15.8180'; DriverDate=[datetime]'2025-10-28'; Availability=8; ResH=0; ResV=0; ResRefresh=0 }
    [pscustomobject]@{ Name='Intel(R) UHD Graphics'; Vendor='Intel Corporation'; AdapterRamBytes=1073741824; RegistryVramBytes=$null; DriverVersion='31.0.101.2130'; DriverDate=[datetime]'2024-08-12'; Availability=3; ResH=1920; ResV=1200; ResRefresh=59 }
)
$gpu = New-GpuReport -Gpus $rawGpus -Now ([datetime]'2026-06-30')
$rawDisks = @([pscustomobject]@{ Name='NVMe PC611 NVMe SK hynix 512GB'; MediaType='SSD'; BusType='RAID'; SizeBytes=549755813888; Health='Healthy'; IsBoot=$true })
$rawVols  = @([pscustomobject]@{ DriveLetter='C'; Label='OS'; FileSystem='NTFS'; SizeBytes=515396075520; FreeBytes=103079215104 })
$st = New-StorageReport -Disks $rawDisks -Volumes $rawVols
$bat = New-BatteryReport -ChargePercent 100 -IsOnAC $true -IsCharging $false -DesignCapacityMWh 95065 -FullChargeCapacityMWh 52166 -CycleCount 0 -Chemistry 'LiP' -Manufacturer 'SMP' -PowerPlan 'Balanced' -PowerPlanGuid '381b4222-f694-41f0-9685-ff5bb260df2e'
$load = New-LoadReport -TotalPhysicalBytes 17179869184 -AvailableBytes 1000000000 -CommittedBytes (52000*1MB) -CommitLimitBytes (54512*1MB) -PercentCommitted 95 -PageReadsPerSec 3000
$net = New-NetworkReport -Adapters @([pscustomobject]@{ Name='Wi-Fi'; PhysicalMediaType='Native 802.11'; SpeedBps=324000000; Wlan=([pscustomobject]@{ State='connected'; Band='5 GHz'; RadioType='802.11ax'; SignalPercent=80; ReceiveMbps=360; TransmitMbps=324 }); MaxSupportedMbps=$null })
$gsen = New-GpuSensorReport -Name 'NVIDIA GeForce RTX 2060 with Max-Q Design' -TempC 50 -UtilPercent 0 -ClockMHz 300 -MaxClockMHz 2100 -PowerW 8.38 -PState 'P8' -SwThermal 'Not Active' -HwThermal 'Not Active'
$fw = New-FirmwareReport -Raw ([pscustomobject]@{ BiosVendor='Dell Inc.'; BiosVersion='1.33.1'; BiosDate=[datetime]'2024-11-17'; IsUefi=$true; SecureBootRaw=1; TpmName='Trusted Platform Module 2.0'; OsBuild=26200; RamBytes=17179869184; SysDriveBytes=1024209543168; AddressWidth=64 })
$benchRaw = [pscustomobject]@{ CpuStMops = 1014; CpuMtMops = 11080; ThreadCount = 16; MemStGBps = 19.3; MemMtGBps = 34.0; MemSkippedReason = $null; DiskSeqMBps = 1186; DiskRandIops = 5135; DiskSkippedReason = $null; DiskDrive = 'C:'; ElapsedS = 11.5 }
$benchFake = New-BenchmarkReport -Raw $benchRaw -Memory $mem -Battery $bat -RanAt ([datetime]'2026-07-05 10:00')
$report = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st -Battery $bat -Load $load -Network $net -GpuSensor $gsen -Firmware $fw
$reportNoBat = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st -Firmware $fw

# recursively collect all control text (labels, textboxes) under a control
function Get-AllText($ctrl) {
    $acc = @()
    foreach ($c in $ctrl.Controls) {
        if ($c.Text) { $acc += $c.Text }
        $acc += Get-AllText $c
    }
    $acc
}

try {
    $form = New-SystemForm $report
    Check ($form -is [System.Windows.Forms.Form]) 'New-SystemForm returns a Form'
    Check ($form.Text -eq 'System Info')            'window title'
    $tabControl = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    Check ($null -ne $tabControl)            'has a TabControl'
    Check ($tabControl.TabPages.Count -eq 10) 'ten tabs'
    $tabNames = @($tabControl.TabPages | ForEach-Object { $_.Text })
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'Graphics') -and ($tabNames -contains 'Memory') -and ($tabNames -contains 'Storage') -and ($tabNames -contains 'Power') -and ($tabNames -contains 'Benchmark') -and ($tabNames -contains 'Network') -and ($tabNames -contains 'Security') -and ($tabNames -contains 'Upgrade')) 'Overview/CPU/Graphics/Memory/Storage/Power/Benchmark/Network/Security/Upgrade tabs'

    $memTab2 = $tabControl.TabPages | Where-Object { $_.Text -eq 'Memory' } | Select-Object -First 1
    Check ([bool]((Get-AllText $memTab2) -join "`n" -match 'CPU-Z')) 'Memory tab has the MT/s footnote'
    $gfxTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Graphics' } | Select-Object -First 1
    Check ($null -ne $gfxTab) 'has Graphics tab'
    Check ($gfxTab.AutoScroll) 'Graphics tab scrolls if its stacked sections overflow'
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

    # Regression guard (slice N): the Graphics GPU list must fit the tab width.
    # A right-anchor added before layout once stretched it ~400px off-screen,
    # clipping 5 of 6 columns. Show off-screen so the geometry is real.
    $formG = New-SystemForm $report
    $formG.StartPosition = 'Manual'; $formG.Location = New-Object System.Drawing.Point(-3000, -3000)
    $formG.Show(); [System.Windows.Forms.Application]::DoEvents()
    $tcG = $formG.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    $gfxTabG = $tcG.TabPages | Where-Object { $_.Text -eq 'Graphics' } | Select-Object -First 1
    $glvG = $gfxTabG.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($glvG.Right -le ($gfxTabG.ClientRectangle.Width + 4)) 'Graphics GPU list fits the tab width (all columns reachable)'
    $formG.Dispose()

    $benchTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Benchmark' } | Select-Object -First 1
    Check ($null -ne $benchTab) 'has Benchmark tab'
    $benchText = (Get-AllText $benchTab) -join "`n"
    Check ([bool]($benchText -match 'Run benchmarks'))                'Benchmark tab has the Run button'
    Check ([bool]($benchText -match 'Nothing runs until you click'))  'Benchmark tab caption states on-demand'
    Check (-not ($benchText -match 'Context:'))                       'fresh Benchmark tab has no results'

    $memTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Memory' } | Select-Object -First 1
    $lv = $memTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $lv)         'Memory tab has a ListView'
    Check ($lv.Items.Count -eq 2) 'two module rows'

    $ovTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Overview' } | Select-Object -First 1
    $tb = $ovTab.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] } | Select-Object -First 1
    Check ($null -ne $tb)                                 'Overview tab has a Notes textbox'
    Check ([bool]($tb.Text -match 'CPU is the limiter'))  'notes populated with insight'

    $storTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Storage' } | Select-Object -First 1
    $storLvs = @()
    foreach ($c in $storTab.Controls) {
        if ($c -is [System.Windows.Forms.ListView]) { $storLvs += $c }
        foreach ($cc in $c.Controls) { if ($cc -is [System.Windows.Forms.ListView]) { $storLvs += $cc } }
    }
    Check ($storLvs.Count -eq 2) 'Storage tab has disks + volumes tables'

    $pwrTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Power' } | Select-Object -First 1
    Check ($null -ne $pwrTab) 'has Power tab'
    Check ($pwrTab.AutoScroll) 'Power tab scrolls if its stacked sections overflow'
    $pwrText = (Get-AllText $pwrTab) -join "`n"
    Check ([bool]($pwrText -match 'Cycle count'))     'Power tab shows battery labels'
    Check ([bool]($pwrText -match '95,065 mWh'))      'Power tab shows battery design capacity'
    Check ([bool]($pwrText -match '45% worn'))        'Power tab shows battery wear'
    Check ([bool]($pwrText -match 'Commit charge'))   'Power tab shows live-load labels'
    Check ([bool]($pwrText -match 'Under pressure'))  'Power tab shows live-load status'

    $ovText = (Get-AllText $ovTab) -join "`n"
    Check ([bool]($ovText -match 'Battery:'))       'Overview has a Battery line'
    Check ([bool]($ovText -match '45% worn'))       'Overview battery line shows wear'

    $netTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Network' } | Select-Object -First 1
    Check ($null -ne $netTab) 'has Network tab'
    $netLv = $netTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $netLv)         'Network tab has a ListView'
    Check ($netLv.Items.Count -eq 1) 'one adapter row'
    $netRow = @($netLv.Items[0].SubItems | ForEach-Object { $_.Text }) -join ' | '
    Check ([bool]($netRow -match 'Wi-Fi 6'))  'Network row shows standard'
    Check ([bool]($ovText -match 'Network:')) 'Overview has a Network line'
    Check ([bool]($ovText -match 'Gaming:'))  'Overview has a Gaming line'

    $upgTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Upgrade' } | Select-Object -First 1
    Check ($null -ne $upgTab) 'has Upgrade tab'
    $upgText = (Get-AllText $upgTab) -join "`n"
    Check ([bool]($upgText -match 'Free fixes'))        'Upgrade tab shows Free fixes group'
    Check ([bool]($upgText -match 'Hardware upgrades'))  'Upgrade tab shows Hardware upgrades group'
    Check ([bool]($upgText -match 'coarse estimate'))    'Upgrade tab shows the honesty caption'

    $fwTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Security' } | Select-Object -First 1
    Check ($null -ne $fwTab) 'has Security tab'
    $fwText = (Get-AllText $fwTab) -join "`n"
    Check ([bool]($fwText -match 'Windows 11 readiness')) 'Firmware tab shows readiness checklist'
    Check ([bool]($fwText -match 'running Windows 11'))    'Firmware tab shows the summary verdict'
    Check ([bool]($fwText -match 'Microsoft'))             'Firmware tab shows the honesty caption'
    Check ([bool]($ovText -match 'Security:'))             'Overview has a Security line'

    # No-battery / no-load / no-net case: no Battery/Live/Network tab; Overview says 'none (AC only)'.
    $form2 = New-SystemForm $reportNoBat
    $tc2 = $form2.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    $names2 = @($tc2.TabPages | ForEach-Object { $_.Text })
    Check ($tc2.TabPages.Count -eq 8)          'desktop: eight tabs (Graphics + Benchmark + Security + Upgrade; no Power/Network)'
    Check ($names2 -contains 'Benchmark')      'desktop: Benchmark tab present'
    Check ($names2 -contains 'Graphics')       'desktop: Graphics tab present'
    Check ($names2 -contains 'Security') 'desktop: Security tab present'
    Check ($names2 -contains 'Upgrade')        'desktop: Upgrade tab present'
    Check (-not ($names2 -contains 'Power'))   'desktop: no Power tab (no battery, no load)'
    Check (-not ($names2 -contains 'Network')) 'no-net: no Network tab'
    $gfx2 = $tc2.TabPages | Where-Object { $_.Text -eq 'Graphics' } | Select-Object -First 1
    Check (-not ((Get-AllText $gfx2) -join "`n" -match 'nvidia-smi')) 'no-sensor: Graphics tab has no sensor panel'
    $ov2 = $tc2.TabPages | Where-Object { $_.Text -eq 'Overview' } | Select-Object -First 1
    $ov2Text = (Get-AllText $ov2) -join "`n"
    Check ([bool]($ov2Text -match 'none \(AC only\)')) 'desktop: Overview shows none (AC only)'
    $form2.Dispose()

    # Results renderer: a report with a pre-attached (fake) Benchmark section
    $report.Benchmark = $benchFake
    $form3 = New-SystemForm $report
    $tc3 = $form3.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    $benchTab3 = $tc3.TabPages | Where-Object { $_.Text -eq 'Benchmark' } | Select-Object -First 1
    $benchText3 = (Get-AllText $benchTab3) -join "`n"
    Check ([bool]($benchText3 -match 'arith Mops/s'))       'Benchmark tab renders CPU result'
    Check ([bool]($benchText3 -match 'theoretical peak'))   'Benchmark tab renders memory reference'
    Check ([bool]($benchText3 -match 'Context:'))           'Benchmark tab renders context row'
    $form3.Dispose()

    # Headless Run-click regression guard: stub the suite (New-SystemForm captures
    # ${function:Invoke-BenchmarkSuite} at build time) so the closure + handler path
    # exercises OnStage without a real ~15 s load.
    $realSuite = ${function:Invoke-BenchmarkSuite}
    function Invoke-BenchmarkSuite { param([scriptblock]$OnStage) if ($OnStage) { $null = & $OnStage 'stub stage' }; [pscustomobject]@{ CpuStMops = 1000; CpuMtMops = 10000; ThreadCount = 16; MemStGBps = 20.0; MemMtGBps = 22.0; MemSkippedReason = $null; DiskSeqMBps = 1000; DiskRandIops = 5000; DiskSkippedReason = $null; DiskDrive = 'C:'; ElapsedS = 0.1 } }
    $repStub = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st -Firmware $fw
    $formStub = New-SystemForm $repStub
    $tcS = $formStub.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    $benchTabS = $tcS.TabPages | Where-Object { $_.Text -eq 'Benchmark' } | Select-Object -First 1
    $btnRunS = $benchTabS.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] } | Select-Object -First 1
    # Fire the REAL click handler. PerformClick() is a silent no-op on a
    # never-shown form (visibility gate), so raise the protected OnClick.
    $onClickM = [System.Windows.Forms.Control].GetMethod('OnClick', [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    $clickErr = $null
    try { $onClickM.Invoke($btnRunS, @([System.EventArgs]::Empty)) } catch { $clickErr = $_.Exception.InnerException }
    Check ($null -eq $clickErr) 'Run click handler ran without error'

    $benchTextS = (Get-AllText $benchTabS) -join "`n"
    Check ([bool]($benchTextS -match 'arith Mops/s'))      'Run click renders results (stubbed suite)'
    Check ([bool]($benchTextS -match 'Done in 0.1s'))      'Run click updates the status label'
    Check ($btnRunS.Text -eq 'Run again')                  'Run click flips the button to Run again'
    Check ($repStub.Benchmark.Ok -eq $true)                'Run click attaches a populated section'
    $formStub.Dispose()
    Set-Item function:Invoke-BenchmarkSuite $realSuite

    $btns = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
    Check ($btns.Count -eq 2)                                                  'two buttons'
    Check (($btns.Text -contains 'Copy') -and ($btns.Text -contains 'Close')) 'Copy + Close present'
    $form.Dispose()
} catch {
    Write-Host "  FAIL  New-SystemForm threw: $($_.Exception.Message)" -ForegroundColor Red
    $script:fail++
}

if ($script:fail) { Write-Host "`nGUI smoke: $script:fail failed`n" -ForegroundColor Red; exit 1 }
else { Write-Host "`nGUI smoke: all passed`n" -ForegroundColor Green; exit 0 }
