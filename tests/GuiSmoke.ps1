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
$report = New-SystemReport -Cpu $cpu -Memory $mem

try {
    $form = New-SystemForm $report
    Check ($form -is [System.Windows.Forms.Form]) 'New-SystemForm returns a Form'
    Check ($form.Text -eq 'System Info')            'window title'
    $tabControl = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TabControl] } | Select-Object -First 1
    Check ($null -ne $tabControl)            'has a TabControl'
    Check ($tabControl.TabPages.Count -eq 3) 'three tabs'
    $tabNames = @($tabControl.TabPages | ForEach-Object { $_.Text })
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'Memory')) 'Overview/CPU/Memory tabs'

    $memTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Memory' } | Select-Object -First 1
    $lv = $memTab.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $lv)         'Memory tab has a ListView'
    Check ($lv.Items.Count -eq 2) 'two module rows'

    $ovTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Overview' } | Select-Object -First 1
    $tb = $ovTab.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] } | Select-Object -First 1
    Check ($null -ne $tb)                                 'Overview tab has a Notes textbox'
    Check ([bool]($tb.Text -match 'CPU is the limiter'))  'notes populated with insight'

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
