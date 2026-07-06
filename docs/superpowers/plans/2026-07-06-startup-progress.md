# Startup Progress (slice M) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the several-second blank console before the GUI opens with a per-collector progress readout (`Reading system information...` → `  Memory... done` … → `Opening window...`), shown only on GUI launch.

**Architecture:** A tiny `Invoke-LoadStep -Label -Action -Show` helper wraps each collector call: prints `  <label>... ` (no newline), runs the collector, prints `done`, returning the collector's output unchanged. `Invoke-SystemInfo` computes `$show = -not ($Console -or $Benchmark)` and wraps its 11 collectors in 9 labelled steps; when `$show` is false the helper is a silent passthrough, so `-Console`/`-Benchmark` output is byte-identical. Spec: `docs/superpowers/specs/2026-07-06-startup-progress-design.md`.

**Tech Stack:** PowerShell 5.1-compatible script; hand-rolled test harness `tests/SystemInfo.Tests.ps1` (`It`/`Assert-Equal`, NOT Pester); `Write-Host` for host/information-stream output (redirect-safe, like the benchmark progress lines).

**Notes for the implementer:**
- Branch: work happens on `feature/startup_progress` (off `main`). If it doesn't exist yet, `git switch -c feature/startup_progress`. The spec file `docs/superpowers/specs/2026-07-06-startup-progress-design.md` may be an uncommitted new file in the working tree — if so, it belongs to this slice; include it in the first commit.
- Run unit suite: `pwsh -File tests/SystemInfo.Tests.ps1` → gate **0 FAIL**. Baseline before this slice: **451 passing**.
- The test file dot-sources `Show-SystemInfo.ps1` with `SYSTEMINFO_NOMAIN=1` ([tests/SystemInfo.Tests.ps1:5](../../tests/SystemInfo.Tests.ps1)), so any new script function is callable from tests once defined.
- Line numbers are from `main` at slice L (`32d704e`) and shift as edits land — **locate by content**, edit by exact match. ASCII-only strings (the script has no BOM; Windows PowerShell 5.1 mis-decodes literal non-ASCII).
- **Write-Host capture fact used by the tests:** `Write-Host` emits an `InformationRecord` on stream 6 (both PS 5.1 and pwsh 7). `<expr> 6>&1` merges those records into the success stream, so a test can capture/inspect them. `-NoNewline` still emits one record per call; on a real console those two records render as one joined line, but in a `6>&1` capture they are two discrete records — so verification asserts individual substrings, never the joined `"Memory... done"` form.

---

### Task 1: `Invoke-LoadStep` helper + unit tests

**Files:**
- Modify: `Show-SystemInfo.ps1` — insert the new function immediately BEFORE `function Invoke-SystemInfo` (locate by content, ~line 2679)
- Test: `tests/SystemInfo.Tests.ps1` — new group after the last `It` (`It 'bench console null' …`, ~line 945) and before the summary `Write-Host "`n$script:Pass passed…`

- [ ] **Step 1: Write the failing tests**

Insert after the `It 'bench console null'` line and before the summary `Write-Host`:

```powershell
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
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: the six new tests FAIL — `Invoke-LoadStep` is not defined, so each call throws (the `It` wrapper reports FAIL). Everything else PASSes (451).

- [ ] **Step 3: Implement `Invoke-LoadStep`**

Insert immediately BEFORE `function Invoke-SystemInfo` in `Show-SystemInfo.ps1`:

```powershell
function Invoke-LoadStep {
    # Print a labelled progress line ("  <Label>... " then "done") around a
    # collector call so the pre-GUI console shows real progress. Returns the
    # action's output unchanged. A hung/throwing step leaves its line without
    # "done", naming the culprit. -Show:$false is a silent passthrough (console
    # / benchmark modes), keeping their output byte-identical.
    param([string] $Label, [scriptblock] $Action, [bool] $Show = $true)
    if ($Show) { Write-Host "  $Label... " -NoNewline }
    $result = & $Action
    if ($Show) { Write-Host 'done' }
    return $result
}
```

- [ ] **Step 4: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (457 passing: 451 + 6). Note: `ls show ret` / `ls show prints` capture their host output via `6>&1`, so the suite's own console stays clean (no stray `M... done` noise).

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1 docs/superpowers/specs/2026-07-06-startup-progress-design.md docs/superpowers/plans/2026-07-06-startup-progress.md
git commit -m "Startup progress: Invoke-LoadStep helper + tests (slice M)"
```
(Include the spec + plan docs here if they are not already committed on the branch.)

---

### Task 2: Wire the progress readout into `Invoke-SystemInfo`

**Files:**
- Modify: `Show-SystemInfo.ps1` — `Invoke-SystemInfo`: the collection `try` block (~lines 2682-2693), and the GUI branch (~line 2756)

No new unit tests (the wiring is main-flow I/O — same posture as the collectors and the `-Benchmark` switch). Verified by the stub-capture and console-clean checks in Steps 3-4.

- [ ] **Step 1: Add `$show` + the banner, and wrap the collectors**

In `Invoke-SystemInfo`, replace the collection block — currently:

```powershell
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
        $fwRaw   = Get-FirmwareInfo
    } catch {
```

with:

```powershell
    $show = -not ($Console -or $Benchmark)
    if ($show) { Write-Host 'Reading system information...' }
    try {
        $memRaw  = Invoke-LoadStep -Label 'Memory' -Show $show -Action {
            [pscustomobject]@{ Modules = @(Get-RamModules); Array = Get-RamArrayInfo; Board = Get-MotherboardInfo }
        }
        $modules = @($memRaw.Modules)
        $array   = $memRaw.Array
        $board   = $memRaw.Board
        $cpuRaw  = Invoke-LoadStep -Label 'Processor'               -Show $show -Action { Get-CpuInfo }
        $gpuRaw  = @(Invoke-LoadStep -Label 'Graphics'             -Show $show -Action { Get-GpuInfo })
        $stRaw   = Invoke-LoadStep -Label 'Storage'                -Show $show -Action { Get-StorageInfo }
        $batRaw  = Invoke-LoadStep -Label 'Battery (a few seconds)' -Show $show -Action { Get-BatteryInfo }
        $loadRaw = Invoke-LoadStep -Label 'Live load'              -Show $show -Action { Get-LoadInfo }
        $netRaw  = Invoke-LoadStep -Label 'Network'                -Show $show -Action { Get-NetworkInfo }
        $gsRaw   = Invoke-LoadStep -Label 'GPU sensors'            -Show $show -Action { Get-GpuSensorInfo }
        $fwRaw   = Invoke-LoadStep -Label 'Firmware & security'    -Show $show -Action { Get-FirmwareInfo }
    } catch {
```

(The downstream code is unchanged — it still reads `$modules`, `$array`, `$board`, `$cpuRaw`, … exactly as before. The `catch` block, which references `$Console`, is untouched.)

- [ ] **Step 2: Add the `Opening window...` line**

In the same function, the GUI branch — currently:

```powershell
    try {
        Show-SystemWindow $report
    } catch {
        Write-Output "(GUI unavailable - showing text. $($_.Exception.Message))"
        Write-SystemConsole $report
    }
```

becomes:

```powershell
    try {
        if ($show) { Write-Host 'Opening window...' }
        Show-SystemWindow $report
    } catch {
        Write-Output "(GUI unavailable - showing text. $($_.Exception.Message))"
        Write-SystemConsole $report
    }
```

- [ ] **Step 3: Verify the GUI-path readout headlessly (stub `Show-SystemWindow`)**

This runs the REAL collectors (~5 s of I/O) but stubs the blocking GUI, so it exercises the actual banner + steps + `Opening window...` without opening a window. **Run via the PowerShell tool (the `$env:`/`$o` are PowerShell variables — do not let a bash wrapper interpolate them); run from the repo root so `.\Show-SystemInfo.ps1` resolves:**

```
pwsh -NoProfile -Command "$env:SYSTEMINFO_NOMAIN='1'; . .\Show-SystemInfo.ps1; function Show-SystemWindow { param($Report) }; $o = (Invoke-SystemInfo 6>&1 | Out-String); 'Reading system information','Memory','Processor','Graphics','Storage','Battery','Live load','Network','GPU sensors','Firmware & security','done','Opening window' | ForEach-Object { '{0,-22}: {1}' -f $_, ([bool]($o -match [regex]::Escape($_))) }"
```

Expected: every line reports `True` (each label, plus `done` and `Opening window` appear in the captured host output). If any is `False`, stop and fix before proceeding.

- [ ] **Step 4: Verify `-Console` and `-Benchmark` stay silent (gating)**

Run:

```
pwsh -NoProfile -Command "$env:SYSTEMINFO_NOMAIN='1'; . .\Show-SystemInfo.ps1; $o = (Invoke-SystemInfo -Console 6>&1 | Out-String); 'console has no banner : ' + (-not ($o -match 'Reading system information')); 'console has no opening : ' + (-not ($o -match 'Opening window'))"
```

Expected: both report `True` — the readout is absent in console mode (proving the gating). (The full console report still prints; we only assert the progress strings are absent.)

- [ ] **Step 5: Run the unit suite (regression)**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (457 — unchanged by this task).

- [ ] **Step 6: Commit**

```bash
git add Show-SystemInfo.ps1
git commit -m "Startup progress: per-collector readout in Invoke-SystemInfo, GUI-gated (slice M)"
```

---

### Task 3: End-to-end verification + real GUI launch

**Files:** none modified (verification only)

- [ ] **Step 1: Both suites green**

Run: `pwsh -File tests/SystemInfo.Tests.ps1` → 0 FAIL (457).
Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → "GUI smoke: all passed" (70 checks — unchanged; GuiSmoke bypasses `Invoke-SystemInfo`, so the tab count stays 12 and nothing about the smoke changes).

- [ ] **Step 2: Real launch — observe the readout**

Launch the app the way a user does and watch the console fill during collection, then `Opening window...` just before the window appears:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-SystemInfo.ps1
```

Expected console (on this Dell XPS 17, joined lines via `-NoNewline`):

```
Reading system information...
  Memory... done
  Processor... done
  Graphics... done
  Storage... done
  Battery (a few seconds)... done
  Live load... done
  Network... done
  GPU sensors... done
  Firmware & security... done
Opening window...
```

then the GUI window opens. Close the window to end. If the collection is fast enough that a step is not individually visible, that is fine — the point is no blank gap and a clear final `Opening window...`.

- [ ] **Step 3: Report done**

No commit (nothing changed). The branch is ready for the finishing flow (verify → fast-forward merge to `main` → push), driven via superpowers:finishing-a-development-branch.
