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
$report = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st -Battery $bat -Load $load -Network $net
$reportNoBat = New-SystemReport -Cpu $cpu -Memory $mem -Gpu $gpu -Storage $st

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
    Check ($tabControl.TabPages.Count -eq 8) 'eight tabs'
    $tabNames = @($tabControl.TabPages | ForEach-Object { $_.Text })
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'GPU') -and ($tabNames -contains 'Memory') -and ($tabNames -contains 'Storage') -and ($tabNames -contains 'Battery') -and ($tabNames -contains 'Live') -and ($tabNames -contains 'Network')) 'Overview/CPU/GPU/Memory/Storage/Battery/Live/Network tabs'

    $memTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Memory' } | Select-Object -First 1
    $lv = $memTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $lv)         'Memory tab has a ListView'
    Check ($lv.Items.Count -eq 2) 'two module rows'

    $ovTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Overview' } | Select-Object -First 1
    $tb = $ovTab.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] } | Select-Object -First 1
    Check ($null -ne $tb)                                 'Overview tab has a Notes textbox'
    Check ([bool]($tb.Text -match 'CPU is the limiter'))  'notes populated with insight'

    $gpuTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'GPU' } | Select-Object -First 1
    $glv = $gpuTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $glv)         'GPU tab has a ListView'
    Check ($glv.Items.Count -eq 2) 'two GPU rows'

    $storTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Storage' } | Select-Object -First 1
    $storLvs = @()
    foreach ($c in $storTab.Controls) {
        if ($c -is [System.Windows.Forms.ListView]) { $storLvs += $c }
        foreach ($cc in $c.Controls) { if ($cc -is [System.Windows.Forms.ListView]) { $storLvs += $cc } }
    }
    Check ($storLvs.Count -eq 2) 'Storage tab has disks + volumes tables'

    $batTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Battery' } | Select-Object -First 1
    Check ($null -ne $batTab) 'has Battery tab'
    $batText = (Get-AllText $batTab) -join "`n"
    Check ([bool]($batText -match 'Cycle count'))  'Battery tab has KV labels'
    Check ([bool]($batText -match '95,065 mWh'))   'Battery tab shows design capacity'
    Check ([bool]($batText -match '45% worn'))     'Battery tab shows wear'

    $ovText = (Get-AllText $ovTab) -join "`n"
    Check ([bool]($ovText -match 'Battery:'))       'Overview has a Battery line'
    Check ([bool]($ovText -match '45% worn'))       'Overview battery line shows wear'

    $liveTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Live' } | Select-Object -First 1
    Check ($null -ne $liveTab) 'has Live tab'
    $liveText = (Get-AllText $liveTab) -join "`n"
    Check ([bool]($liveText -match 'Commit charge'))  'Live tab has KV labels'
    Check ([bool]($liveText -match 'Under pressure')) 'Live tab shows status'

    $netTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Network' } | Select-Object -First 1
    Check ($null -ne $netTab) 'has Network tab'
    $netLv = $netTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $netLv)         'Network tab has a ListView'
    Check ($netLv.Items.Count -eq 1) 'one adapter row'
    $netRow = @($netLv.Items[0].SubItems | ForEach-Object { $_.Text }) -join ' | '
    Check ([bool]($netRow -match 'Wi-Fi 6'))  'Network row shows standard'
    Check ([bool]($ovText -match 'Network:')) 'Overview has a Network line'

    # No-battery / no-load / no-net case: no Battery/Live/Network tab; Overview says 'none (AC only)'.
    $form2 = New-SystemForm $reportNoBat
    $tc2 = $form2.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    $names2 = @($tc2.TabPages | ForEach-Object { $_.Text })
    Check ($tc2.TabPages.Count -eq 5)          'desktop: five tabs (no Battery/Live)'
    Check (-not ($names2 -contains 'Battery')) 'desktop: no Battery tab'
    Check (-not ($names2 -contains 'Live'))    'no-load: no Live tab'
    Check (-not ($names2 -contains 'Network')) 'no-net: no Network tab'
    $ov2 = $tc2.TabPages | Where-Object { $_.Text -eq 'Overview' } | Select-Object -First 1
    $ov2Text = (Get-AllText $ov2) -join "`n"
    Check ([bool]($ov2Text -match 'none \(AC only\)')) 'desktop: Overview shows none (AC only)'
    $form2.Dispose()

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
