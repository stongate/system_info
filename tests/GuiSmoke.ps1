# Headless smoke test for the WinForms window: builds the form via New-RamForm
# (no ShowDialog) and checks its structure. Run under Windows PowerShell (STA):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\GuiSmoke.ps1
$env:RAMINFO_NOMAIN = '1'
. "$PSScriptRoot\..\Show-RamInfo.ps1"

$script:fail = 0
function Check($Cond, $Name) {
    if ($Cond) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name" -ForegroundColor Red; $script:fail++ }
}

$mods = @(
    [pscustomobject]@{ Slot='DIMM A'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
    [pscustomobject]@{ Slot='DIMM B'; CapacityBytes=8589934592; RatedSpeed=3200; CurrentSpeed=2933; VendorRaw='80AD00000000'; PartNumber='HMA81GS6CJR8N-XN'; TypeCode=26 }
)
$r = New-RamReport -Modules $mods -MaxCapacityBytes 68719476736 -TotalSlots 2 -BoardMaker 'Dell Inc.' -BoardModel '0CXCCY' -BoardVersion 'A03' -CpuName 'Intel(R) Core(TM) i7-10875H CPU @ 2.30GHz'

try {
    $form = New-RamForm $r
    Check ($form -is [System.Windows.Forms.Form]) 'New-RamForm returns a Form'
    Check ($form.Text -eq 'RAM Info')              'window title set'
    $lv = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.ListView] } | Select-Object -First 1
    Check ($null -ne $lv)            'has a ListView'
    Check ($lv.Items.Count -eq 2)    'two module rows'
    Check ($lv.Columns.Count -eq 6)  'six columns'
    $btns = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] })
    Check ($btns.Count -eq 2)                                          'two buttons'
    Check (($btns.Text -contains 'Copy') -and ($btns.Text -contains 'Close')) 'Copy + Close present'
    $lbls = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Label] })
    Check ($lbls.Count -ge 2)                       'summary split into key + value columns'
    Check ([bool]($lbls.Text -match 'used of'))     'values column rendered'
    $tb = $form.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] } | Select-Object -First 1
    Check ($null -ne $tb)                              'has notes textbox'
    Check ([bool]($tb.Text -match 'CPU is the limiter')) 'notes populated with insight'
    $form.Dispose()
} catch {
    Write-Host "  FAIL  New-RamForm threw: $($_.Exception.Message)" -ForegroundColor Red
    $script:fail++
}

if ($script:fail) { Write-Host "`nGUI smoke: $script:fail failed`n" -ForegroundColor Red; exit 1 }
else { Write-Host "`nGUI smoke: all passed`n" -ForegroundColor Green; exit 0 }
