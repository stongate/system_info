# Benchmarks (slice L) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On-demand CPU/memory/disk micro-benchmarks — a 12th "Benchmark" tab with a Run button and a `-Benchmark` console switch — measured on this machine, labeled honestly, with derivable references only.

**Architecture:** A new "on-demand prober" pattern: `Invoke-BenchmarkSuite` (I/O + timed load; in-memory C# via `Add-Type`; guards, per-stage try/catch, never throws) → pure `New-BenchmarkReport` (unit-tested; derives theoretical memory peak + MT/ST scale + power context) → renderers. `New-SystemReport` gains only a `Benchmark = $null` placeholder; both entry points assign to it. The GUI runs staged-sync with `DoEvents`; the Copy button switches to click-time rendering so results reach the clipboard. Spec: `docs/superpowers/specs/2026-07-04-benchmark-design.md`.

**Tech Stack:** PowerShell 5.1-compatible script; C# 5 via `Add-Type` (CodeDom on 5.1 — no string interpolation, no expression-bodied members); hand-rolled test harness (`It`/`Assert-Equal`, NOT Pester); WinForms smoke (`Check` helper, synthetic fixtures).

**Grounding notes for the implementer:**
- Run unit suite: `pwsh -File tests/SystemInfo.Tests.ps1` → gate is **0 FAIL** (current: 419 passing). New unit tests insert after the last `It` (line 864, `'fw console absent'`), before the summary block (line 866).
- Run GUI smoke: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → gate "GUI smoke: all passed" (current: 57 checks).
- Line numbers are from `main` at slice K (`bccdd43`) and shift as tasks land — **locate by content**, edit by exact match.
- Battery section fields (verified): `IsOnAC` (`$true|$false|$null`), `PowerPlan` (string, may be `''`). Memory section fields (verified): `RunningSpeed` (int MT/s or 0/`$null`), `PopulatedSlots` (int).
- `Add-KvBlock` (Show-SystemInfo.ps1:1782): `param($Parent, [string[]]$Keys, [string[]]$Values, [int]$X = 14, [int]$Y = 14, [int]$KeyW = 150, [int]$ValW = 404)`, 20 px per row, returns next Y. Values render one line per array element (no wrapping) — long values must be split across rows.
- ASCII-safe strings everywhere (the script has no BOM; Windows PowerShell 5.1 mis-decodes literal non-ASCII).

---

### Task 1: `New-BenchmarkReport` (pure) + `Benchmark` placeholder + unit tests

**Files:**
- Modify: `Show-SystemInfo.ps1` — insert the new function immediately BEFORE `function New-SystemReport` (locate by content, ~line 1216); add one line to `New-SystemReport`'s output object (~line 1263)
- Test: `tests/SystemInfo.Tests.ps1` — new group after line 864 (`'fw console absent'`), before the summary at 866

- [ ] **Step 1: Write the failing tests**

Insert after the `It 'fw console absent'` line and before the `Write-Host "`n$script:Pass passed...` summary:

```powershell
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
```

Note: `$memDual` (dual-channel DDR4, RatedSpeed 3200 / CurrentSpeed 2933, line 160) and `$memSingle` (one module, CurrentSpeed 3200, line ~166) are pre-existing fixtures. `New-MemoryReport`'s `RunningSpeed` comes from `CurrentSpeed` — so `$memDual` → 2933 (46.9 theoretical) and `$memSingle` → 3200 (25.6 theoretical).

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: the `New-BenchmarkReport` calls throw (function not defined) → the 19 builder tests FAIL (reported by the `It` wrapper); `bench placeholder` also FAILs (property missing) and `bench ph null` FAILs alongside it. Everything else PASSes (419).

- [ ] **Step 3: Implement `New-BenchmarkReport` + the placeholder**

Insert immediately BEFORE `function New-SystemReport` in `Show-SystemInfo.ps1`:

```powershell
function New-BenchmarkReport {
    # Shape an on-demand benchmark run into the report section (pure). References
    # are derivable-only: memory theoretical peak = channels x 8 B x MT/s (channels
    # estimated as min(populated slots, 2), labelled), and the MT/ST scale factor.
    # No good/bad verdicts, no shipped comparison data.
    param([object] $Raw, [object] $Memory = $null, [object] $Battery = $null, [datetime] $RanAt)
    $scale = if ($null -ne $Raw.CpuStMops -and $null -ne $Raw.CpuMtMops -and [double]$Raw.CpuStMops -gt 0) {
        [math]::Round([double]$Raw.CpuMtMops / [double]$Raw.CpuStMops, 1)
    } else { $null }
    $theo = $null; $chanNote = $null
    if ($null -ne $Memory -and $null -ne $Memory.RunningSpeed -and [int]$Memory.RunningSpeed -gt 0 -and
        $null -ne $Memory.PopulatedSlots -and [int]$Memory.PopulatedSlots -ge 1) {
        $chan = [Math]::Min([int]$Memory.PopulatedSlots, 2)
        $theo = [math]::Round($chan * 8 * [int]$Memory.RunningSpeed / 1000, 1)
        $chanNote = if ($chan -eq 2) { 'assumes dual-channel' } else { '1 module = 1 channel' }
    }
    $randMBps = if ($null -ne $Raw.DiskRandIops) { [math]::Round([double]$Raw.DiskRandIops * 4096 / 1e6, 1) } else { $null }
    [pscustomobject]@{
        Cpu     = [pscustomobject]@{ StMops = $Raw.CpuStMops; MtMops = $Raw.CpuMtMops; Scale = $scale; Threads = $Raw.ThreadCount }
        Memory  = [pscustomobject]@{ StGBps = $Raw.MemStGBps; MtGBps = $Raw.MemMtGBps; TheoreticalGBps = $theo; ChannelAssumption = $chanNote; SkippedReason = $Raw.MemSkippedReason }
        Disk    = [pscustomobject]@{ Drive = $Raw.DiskDrive; SeqMBps = $Raw.DiskSeqMBps; RandIops = $Raw.DiskRandIops; RandMBps = $randMBps; SkippedReason = $Raw.DiskSkippedReason }
        Context = [pscustomobject]@{ OnAC = $(if ($Battery) { $Battery.IsOnAC } else { $null }); PowerPlan = $(if ($Battery -and $Battery.PowerPlan) { $Battery.PowerPlan } else { $null }); RanAt = $RanAt }
        Ok      = [bool]($null -ne $Raw.CpuStMops -or $null -ne $Raw.MemStGBps -or $null -ne $Raw.DiskSeqMBps)
    }
}
```

Then in `New-SystemReport`'s output object, insert after the `Upgrade   = $upgrade` line:

```powershell
        Benchmark = $null   # on-demand; assigned by -Benchmark / the GUI Run button
```

- [ ] **Step 4: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (440 passing: 419 + 21).

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Benchmarks: New-BenchmarkReport (pure) + report placeholder (slice L)"
```

---

### Task 2: Console renderer — `Benchmarks` section

**Files:**
- Modify: `Show-SystemInfo.ps1` — `Write-SystemConsole`, insert a new block between the `if ($Report.Load) { ... }` block (ends `''` then `}` at ~line 1679) and `if ($Report.Network ...` (~line 1680)
- Test: `tests/SystemInfo.Tests.ps1` — extend the slice-L group from Task 1

- [ ] **Step 1: Write the failing tests**

Add after the `It 'bench ph null'` line:

```powershell
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
```

- [ ] **Step 2: Run the suite to verify the new tests fail**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: FAILs for `bench console sect/cpu/theo/disk/ctx/qd1/skip` (no section exists). `bench console absent` PASSes trivially (pins the default). Everything else PASSes.

- [ ] **Step 3: Implement the console block**

In `Write-SystemConsole`, insert between the Load block's closing `}` and the `if ($Report.Network ...` line:

```powershell
    if ($Report.Benchmark) {
        $bmr = $Report.Benchmark
        $cparts = @()
        if ($null -ne $bmr.Cpu.StMops) { $cparts += '{0:N0} arith Mops/s single-thread' -f $bmr.Cpu.StMops }
        if ($null -ne $bmr.Cpu.MtMops) { $cparts += '{0:N0} all-threads ({1}x on {2} threads)' -f $bmr.Cpu.MtMops, $bmr.Cpu.Scale, $bmr.Cpu.Threads }
        $cpuStr = if ($cparts.Count) { $cparts -join ' -> ' } else { 'Unavailable' }
        $mparts = @()
        if ($null -ne $bmr.Memory.StGBps) { $mparts += '{0:N1} GB/s copy (1 thread)' -f $bmr.Memory.StGBps }
        if ($null -ne $bmr.Memory.MtGBps) { $mparts += '{0:N1} GB/s (all threads)' -f $bmr.Memory.MtGBps }
        $memStr = if ($mparts.Count) {
            ($mparts -join ' / ') + $(if ($null -ne $bmr.Memory.TheoreticalGBps) { '; theoretical peak ~{0:N1} GB/s ({1})' -f $bmr.Memory.TheoreticalGBps, $bmr.Memory.ChannelAssumption } else { '' })
        } elseif ($bmr.Memory.SkippedReason) { "Unavailable ($($bmr.Memory.SkippedReason))" } else { 'Unavailable' }
        $dparts = @()
        if ($null -ne $bmr.Disk.SeqMBps) { $dparts += '{0:N0} MB/s sequential' -f $bmr.Disk.SeqMBps }
        if ($null -ne $bmr.Disk.RandIops) { $dparts += '{0:N0} IOPS random 4K (~{1:N1} MB/s)' -f $bmr.Disk.RandIops, $bmr.Disk.RandMBps }
        $diskStr = if ($dparts.Count) {
            $(if ($bmr.Disk.Drive) { "$($bmr.Disk.Drive) " } else { '' }) + ($dparts -join ' / ')
        } elseif ($bmr.Disk.SkippedReason) { "Unavailable ($($bmr.Disk.SkippedReason))" } else { 'Unavailable' }
        $ctxParts = @()
        if ($bmr.Context.OnAC -eq $true) { $ctxParts += 'on AC power' } elseif ($bmr.Context.OnAC -eq $false) { $ctxParts += 'on battery' }
        if ($bmr.Context.PowerPlan) { $ctxParts += "$($bmr.Context.PowerPlan) plan" }
        $ctxParts += '{0:yyyy-MM-dd HH:mm}' -f $bmr.Context.RanAt
        '  Benchmarks'
        '  ----------'
        '  CPU              : {0}' -f $cpuStr
        '  Memory           : {0}' -f $memStr
        '  Disk             : {0}' -f $diskStr
        '  Context          : {0} (short-burst)' -f ($ctxParts -join ', ')
        '  (measured by this tool''s own workloads - comparable across runs of this'
        '   tool, not to other benchmarks; disk is single-stream/QD1 - spec-sheet'
        '   numbers need deep queues)'
        ''
    }
```

- [ ] **Step 4: Run the suite to verify everything passes**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (448 passing: 440 + 8).

- [ ] **Step 5: Commit**

```bash
git add Show-SystemInfo.ps1 tests/SystemInfo.Tests.ps1
git commit -m "Benchmarks: console Benchmarks section (slice L)"
```

---

### Task 3: `Invoke-BenchmarkSuite` + the C# workloads

**Files:**
- Modify: `Show-SystemInfo.ps1` — insert the C# here-string + function immediately AFTER the closing brace of `function Get-FirmwareInfo` (the last collector; locate `function Get-FirmwareInfo`, find its end)

No unit tests (I/O + timed load — the house rule for collectors); Step 3 verifies by direct invocation.

- [ ] **Step 1: Implement the C# + orchestrator**

Insert after `Get-FirmwareInfo`'s closing brace:

```powershell
# C# workloads for the on-demand benchmark suite (compiled once per session via
# Add-Type; C# 5-compatible for the Windows PowerShell 5.1 CodeDom compiler).
$script:SysInfoBenchCs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;

public static class SysInfoBench {
    // Plain integer+float mix (xorshift + multiply-add). Deliberately NOT crypto:
    // SHA-NI-capable CPUs would skew cross-machine comparisons. "Ops" are nominal.
    public static double CpuMopsSingle(double seconds) {
        var sw = Stopwatch.StartNew();
        ulong x = 88172645463325252UL; double acc = 1.000000001; long ops = 0;
        while (sw.Elapsed.TotalSeconds < seconds) {
            for (int i = 0; i < 1000000; i++) {
                x ^= x << 13; x ^= x >> 7; x ^= x << 17;
                acc = acc * 1.0000001 + (x & 0xFF);
            }
            ops += 2000000;
        }
        sw.Stop();
        if (acc == 12345.6789) Console.WriteLine("");  // defeat dead-code elimination
        return ops / sw.Elapsed.TotalSeconds / 1e6;
    }
    public static double CpuMopsAll(double seconds) {
        int n = Environment.ProcessorCount;
        long[] counts = new long[n];
        var sw = Stopwatch.StartNew();
        Parallel.For(0, n, t => {
            ulong x = 88172645463325252UL + (ulong)t * 2654435761UL;
            double acc = 1.000000001;
            while (sw.Elapsed.TotalSeconds < seconds) {
                for (int i = 0; i < 1000000; i++) {
                    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
                    acc = acc * 1.0000001 + (x & 0xFF);
                }
                counts[t] += 2000000;
            }
            if (acc == 12345.6789) Console.WriteLine("");
        });
        sw.Stop();
        long total = 0; foreach (var c in counts) total += c;
        return total / sw.Elapsed.TotalSeconds / 1e6;
    }
    // Copy bandwidth over buffers far beyond L3 so cache cannot lie.
    // Bytes touched = 2x bytes copied (read + write).
    public static double MemCopyGBps(int totalMB, double seconds) {
        int half = totalMB * 1024 * 1024 / 2;
        byte[] src = new byte[half]; byte[] dst = new byte[half];
        new Random(42).NextBytes(src);
        long bytes = 0; var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) {
            Buffer.BlockCopy(src, 0, dst, 0, half);
            bytes += half;
        }
        sw.Stop();
        return (bytes * 2.0) / sw.Elapsed.TotalSeconds / 1e9;
    }
    public static double MemCopyGBpsAll(int totalMB, double seconds) {
        int half = totalMB * 1024 * 1024 / 2;
        byte[] src = new byte[half]; byte[] dst = new byte[half];
        new Random(42).NextBytes(src);
        int n = Environment.ProcessorCount;
        int slice = half / n;
        long[] counts = new long[n];
        var sw = Stopwatch.StartNew();
        Parallel.For(0, n, t => {
            int off = t * slice;
            while (sw.Elapsed.TotalSeconds < seconds) {
                Buffer.BlockCopy(src, off, dst, off, slice);
                counts[t] += slice;
            }
        });
        sw.Stop();
        long total = 0; foreach (var c in counts) total += c;
        return (total * 2.0) / sw.Elapsed.TotalSeconds / 1e9;
    }
    // Unbuffered (FILE_FLAG_NO_BUFFERING) reads so the file cache cannot inflate
    // the numbers. Single-stream / QD1 by design - labelled as such in the UI.
    public static double DiskSeqMBps(string path, double capSeconds) {
        const FileOptions NoBuf = (FileOptions)0x20000000;
        byte[] buf = new byte[1024 * 1024];
        long bytes = 0;
        var sw = Stopwatch.StartNew();
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, buf.Length, NoBuf)) {
            int n;
            while ((n = fs.Read(buf, 0, buf.Length)) > 0) {
                bytes += n;
                if (sw.Elapsed.TotalSeconds >= capSeconds) break;   // HDDs may not finish
            }
        }
        sw.Stop();
        if (bytes == 0) return 0;
        return bytes / sw.Elapsed.TotalSeconds / 1e6;
    }
    public static double DiskRandIops(string path, double seconds) {
        const FileOptions NoBuf = (FileOptions)0x20000000;
        byte[] buf = new byte[4096];
        var rng = new Random(3);
        long ops = 0; double elapsed;
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, NoBuf)) {
            long len = fs.Length;
            var sw = Stopwatch.StartNew();
            while (sw.Elapsed.TotalSeconds < seconds) {
                long pos = (long)(rng.NextDouble() * (len - 8192));
                pos = pos - (pos % 4096);   // sector-aligned for NO_BUFFERING
                fs.Position = pos;
                fs.Read(buf, 0, 4096);
                ops++;
            }
            sw.Stop();
            elapsed = sw.Elapsed.TotalSeconds;
        }
        return ops / elapsed;
    }
}
'@

function Invoke-BenchmarkSuite {
    # On-demand micro-benchmark run (I/O + timed CPU/memory/disk load). NEVER runs
    # automatically - callers are the -Benchmark switch and the GUI Run button.
    # Guards: memory stage skipped below 2 GB available RAM; disk stage skipped
    # below 5 GB free. Each stage try/catch -> nulls + reason; a total failure
    # returns a bundle of nulls - never throws. -OnStage (optional scriptblock)
    # is invoked with a short label before each stage, for progress display.
    param([scriptblock] $OnStage)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $r = [pscustomobject]@{
        CpuStMops = $null; CpuMtMops = $null; ThreadCount = $null
        MemStGBps = $null; MemMtGBps = $null; MemSkippedReason = $null
        DiskSeqMBps = $null; DiskRandIops = $null; DiskSkippedReason = $null; DiskDrive = $null
        ElapsedS = $null
    }
    try {
        if (-not ('SysInfoBench' -as [type])) {
            if ($OnStage) { & $OnStage 'compiling workloads (one-time)' }
            Add-Type -TypeDefinition $script:SysInfoBenchCs -Language CSharp
        }
        $r.ThreadCount = [Environment]::ProcessorCount
        try {
            if ($OnStage) { & $OnStage 'CPU (single-thread)' }
            $r.CpuStMops = [math]::Round([SysInfoBench]::CpuMopsSingle(1.5), 0)
            if ($OnStage) { & $OnStage 'CPU (all threads)' }
            $r.CpuMtMops = [math]::Round([SysInfoBench]::CpuMopsAll(2.0), 0)
        } catch { }
        try {
            $availGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
            if ($availGB -lt 2) { $r.MemSkippedReason = "low available memory ($availGB GB)" }
            else {
                if ($OnStage) { & $OnStage 'memory copy (1 thread)' }
                $r.MemStGBps = [math]::Round([SysInfoBench]::MemCopyGBps(512, 1.5), 1)
                if ($OnStage) { & $OnStage 'memory copy (all threads)' }
                $r.MemMtGBps = [math]::Round([SysInfoBench]::MemCopyGBpsAll(512, 1.5), 1)
            }
        } catch { $r.MemSkippedReason = "failed ($($_.Exception.Message))" }
        $tmp = $null
        try {
            $drive = Split-Path -Qualifier $env:TEMP
            $r.DiskDrive = $drive
            $freeGB = [math]::Round((New-Object IO.DriveInfo($drive)).AvailableFreeSpace / 1GB, 1)
            if ($freeGB -lt 5) { $r.DiskSkippedReason = "low free space on $drive ($freeGB GB)" }
            else {
                if ($OnStage) { & $OnStage 'disk (writing test file)' }
                $tmp = Join-Path $env:TEMP 'SystemInfo-diskbench.tmp'
                $buf = New-Object byte[] (4MB)
                (New-Object Random(42)).NextBytes($buf)
                $fs = [IO.File]::Create($tmp)
                foreach ($i in 1..128) { $fs.Write($buf, 0, $buf.Length) }   # 512 MB
                $fs.Flush($true); $fs.Close()
                if ($OnStage) { & $OnStage 'disk read (sequential)' }
                $r.DiskSeqMBps = [math]::Round([SysInfoBench]::DiskSeqMBps($tmp, 4.0), 0)
                if ($OnStage) { & $OnStage 'disk read (random 4K)' }
                $r.DiskRandIops = [math]::Round([SysInfoBench]::DiskRandIops($tmp, 2.0), 0)
            }
        } catch { $r.DiskSkippedReason = "failed ($($_.Exception.Message))" }
        finally { if ($tmp -and (Test-Path $tmp)) { [IO.File]::Delete($tmp) } }
    } catch { }
    $sw.Stop()
    $r.ElapsedS = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    return $r
}
```

- [ ] **Step 2: Run the unit suite to confirm nothing broke**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (448 — unchanged; this task adds no tests).

- [ ] **Step 3: Verify the suite by direct invocation on BOTH runtimes**

Run (takes ~15 s each):
```
pwsh -NoProfile -Command "$env:SYSTEMINFO_NOMAIN='1'; . .\Show-SystemInfo.ps1; Invoke-BenchmarkSuite -OnStage { param($m) Write-Host \"  stage: $m\" } | Format-List"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$env:SYSTEMINFO_NOMAIN='1'; . .\Show-SystemInfo.ps1; Invoke-BenchmarkSuite -OnStage { param($m) Write-Host \"  stage: $m\" } | Format-List"
```
Expected on both: stage labels print in order; the bundle shows plausible non-null numbers — CpuStMops ~1000, CpuMtMops ~11000, ThreadCount 16, DiskSeqMBps ~1000+, DiskRandIops ~5000, ElapsedS ~10-15. MemStGBps/MemMtGBps are ~19/~30+ **or** `MemSkippedReason = 'low available memory (…)'` if the machine is under pressure — both are correct outcomes; note which occurred. Confirm `SystemInfo-diskbench.tmp` does NOT remain in `$env:TEMP` afterward:
```
pwsh -Command "Test-Path (Join-Path $env:TEMP 'SystemInfo-diskbench.tmp')"
```
Expected: `False`.

- [ ] **Step 4: Commit**

```bash
git add Show-SystemInfo.ps1
git commit -m "Benchmarks: Invoke-BenchmarkSuite + C# workloads (slice L)"
```

---

### Task 4: `-Benchmark` console switch

**Files:**
- Modify: `Show-SystemInfo.ps1:11` (script param), `Invoke-SystemInfo` (~line 2331: param + post-report hook), the main call (~line 2409)

No unit tests (main-flow code runs only outside `SYSTEMINFO_NOMAIN`); Step 2 verifies with a real run.

- [ ] **Step 1: Implement the switch**

Script param block — replace line 11:
```powershell
param([switch]$Console)
```
with:
```powershell
param([switch]$Console, [switch]$Benchmark)
```

`Invoke-SystemInfo` — replace its param line:
```powershell
    param([switch]$Console)
```
with:
```powershell
    param([switch]$Console, [switch]$Benchmark)
```

Then replace (inside `Invoke-SystemInfo`, right after `$report = New-SystemReport ...`):
```powershell
    if ($Console) { Write-SystemConsole $report; return }
```
with:
```powershell
    if ($Benchmark) {
        # -Benchmark implies console mode (a GUI must never auto-run a load).
        Write-Output 'Running benchmarks (~10-15 s)...'
        $bundle = Invoke-BenchmarkSuite -OnStage { param($msg) Write-Output "  $msg..." }
        $report.Benchmark = New-BenchmarkReport -Raw $bundle -Memory $memory -Battery $battery -RanAt (Get-Date)
        Write-SystemConsole $report
        return
    }
    if ($Console) { Write-SystemConsole $report; return }
```

Main call — replace:
```powershell
if (-not $env:SYSTEMINFO_NOMAIN) {
    Invoke-SystemInfo -Console:$Console
}
```
with:
```powershell
if (-not $env:SYSTEMINFO_NOMAIN) {
    Invoke-SystemInfo -Console:$Console -Benchmark:$Benchmark
}
```

- [ ] **Step 2: Verify with a real run**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-SystemInfo.ps1 -Benchmark`
Expected: the progress lines print first, then the full console report including a `Benchmarks` section (between `Live / Load` and `Network`) with real numbers (or the memory-skip line if the machine is under pressure), the context line ending `(short-burst)`, and the caption. Also verify plain `-Console` output has NO `Benchmarks` section:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-SystemInfo.ps1 -Console
```

- [ ] **Step 3: Run the unit suite (regression)**

Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (448).

- [ ] **Step 4: Commit**

```bash
git add Show-SystemInfo.ps1
git commit -m "Benchmarks: -Benchmark console switch (slice L)"
```

---

### Task 5: GUI — Benchmark tab, results renderer, Copy fix; GuiSmoke updates

**Files:**
- Modify: `Show-SystemInfo.ps1` — new `Add-BenchmarkResults` helper immediately AFTER `Add-KvBlock`'s closing brace (~line 1798); new tab block in `New-SystemForm` between the Live tab block (`[void]$tabs.TabPages.Add($tabLive)` + its closing `}`) and the Network tab block (`# --- Network tab` or `if ($Report.Network ...`); the Copy button (~line 2296-2305)
- Modify: `tests/GuiSmoke.ps1` — fixtures + checks

- [ ] **Step 1: Update GuiSmoke so it fails first**

(a) After the `$fw = New-FirmwareReport ...` fixture line (line 33), add:

```powershell
$benchRaw = [pscustomobject]@{ CpuStMops = 1014; CpuMtMops = 11080; ThreadCount = 16; MemStGBps = 19.3; MemMtGBps = 34.0; MemSkippedReason = $null; DiskSeqMBps = 1186; DiskRandIops = 5135; DiskSkippedReason = $null; DiskDrive = 'C:'; ElapsedS = 11.5 }
$benchFake = New-BenchmarkReport -Raw $benchRaw -Memory $mem -Battery $bat -RanAt ([datetime]'2026-07-05 10:00')
```

(b) Replace line 53:
```powershell
    Check ($tabControl.TabPages.Count -eq 11) 'eleven tabs'
```
with:
```powershell
    Check ($tabControl.TabPages.Count -eq 12) 'twelve tabs'
```

(c) Replace the line-55 tab-names `Check` (one long line) with:

```powershell
    Check (($tabNames -contains 'Overview') -and ($tabNames -contains 'CPU') -and ($tabNames -contains 'GPU') -and ($tabNames -contains 'Memory') -and ($tabNames -contains 'Storage') -and ($tabNames -contains 'Gaming') -and ($tabNames -contains 'Battery') -and ($tabNames -contains 'Live') -and ($tabNames -contains 'Benchmark') -and ($tabNames -contains 'Network') -and ($tabNames -contains 'Firmware & Security') -and ($tabNames -contains 'Upgrade')) 'Overview/CPU/GPU/Memory/Storage/Gaming/Battery/Live/Benchmark/Network/Firmware & Security/Upgrade tabs'
```

(d) After the Gaming-tab checks (the five slice-K `Check` lines ending `'Gaming tab caption states the laptop tier rule'`), add:

```powershell
    $benchTab = $tabControl.TabPages | Where-Object { $_.Text -eq 'Benchmark' } | Select-Object -First 1
    Check ($null -ne $benchTab) 'has Benchmark tab'
    $benchText = (Get-AllText $benchTab) -join "`n"
    Check ([bool]($benchText -match 'Run benchmarks'))                'Benchmark tab has the Run button'
    Check ([bool]($benchText -match 'Nothing runs until you click'))  'Benchmark tab caption states on-demand'
    Check (-not ($benchText -match 'Context:'))                       'fresh Benchmark tab has no results'
```

(e) In the desktop-fixture block, replace:
```powershell
    Check ($tc2.TabPages.Count -eq 8)          'desktop: eight tabs (Gaming + Firmware & Security + Upgrade; no Battery/Live/Network)'
```
with:
```powershell
    Check ($tc2.TabPages.Count -eq 9)          'desktop: nine tabs (Gaming + Benchmark + Firmware & Security + Upgrade; no Battery/Live/Network)'
    Check ($names2 -contains 'Benchmark')      'desktop: Benchmark tab present'
```

(f) After the desktop block's last check (`'desktop: Overview shows none (AC only)'`) and its `$form2.Dispose()`, add:

```powershell
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
```

- [ ] **Step 2: Run GuiSmoke to verify the new checks fail**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: FAILs for 'twelve tabs', the tab-names conjunction, 'has Benchmark tab', the fresh-state checks, 'desktop: nine tabs', 'desktop: Benchmark tab present', and the three results-render checks. Exit 1.

- [ ] **Step 3: Implement `Add-BenchmarkResults`**

Insert immediately after `Add-KvBlock`'s closing brace:

```powershell
function Add-BenchmarkResults {
    # Render (or re-render) benchmark results into the Benchmark tab. String
    # composition intentionally mirrors the console section (per-renderer
    # duplication is the house idiom). Values are split across KV rows because
    # Add-KvBlock does not wrap long lines.
    param($Tab, $Benchmark)
    $old = $Tab.Controls['BenchResults']
    if ($old) { $Tab.Controls.Remove($old); $old.Dispose() }
    $bmr = $Benchmark
    $cparts = @()
    if ($null -ne $bmr.Cpu.StMops) { $cparts += '{0:N0} arith Mops/s single-thread' -f $bmr.Cpu.StMops }
    if ($null -ne $bmr.Cpu.MtMops) { $cparts += '{0:N0} all-threads ({1}x on {2} threads)' -f $bmr.Cpu.MtMops, $bmr.Cpu.Scale, $bmr.Cpu.Threads }
    $cpuStr = if ($cparts.Count) { $cparts -join ' -> ' } else { 'Unavailable' }
    $mparts = @()
    if ($null -ne $bmr.Memory.StGBps) { $mparts += '{0:N1} GB/s copy (1 thread)' -f $bmr.Memory.StGBps }
    if ($null -ne $bmr.Memory.MtGBps) { $mparts += '{0:N1} GB/s (all threads)' -f $bmr.Memory.MtGBps }
    $memStr = if ($mparts.Count) { $mparts -join ' / ' }
              elseif ($bmr.Memory.SkippedReason) { "Unavailable ($($bmr.Memory.SkippedReason))" } else { 'Unavailable' }
    $memRef = if ($null -ne $bmr.Memory.TheoreticalGBps) { 'theoretical peak ~{0:N1} GB/s ({1})' -f $bmr.Memory.TheoreticalGBps, $bmr.Memory.ChannelAssumption } else { '' }
    $dparts = @()
    if ($null -ne $bmr.Disk.SeqMBps) { $dparts += '{0:N0} MB/s sequential' -f $bmr.Disk.SeqMBps }
    if ($null -ne $bmr.Disk.RandIops) { $dparts += '{0:N0} IOPS random 4K (~{1:N1} MB/s)' -f $bmr.Disk.RandIops, $bmr.Disk.RandMBps }
    $diskStr = if ($dparts.Count) { $(if ($bmr.Disk.Drive) { "$($bmr.Disk.Drive) " } else { '' }) + ($dparts -join ' / ') }
               elseif ($bmr.Disk.SkippedReason) { "Unavailable ($($bmr.Disk.SkippedReason))" } else { 'Unavailable' }
    $ctxParts = @()
    if ($bmr.Context.OnAC -eq $true) { $ctxParts += 'on AC power' } elseif ($bmr.Context.OnAC -eq $false) { $ctxParts += 'on battery' }
    if ($bmr.Context.PowerPlan) { $ctxParts += "$($bmr.Context.PowerPlan) plan" }
    $ctxParts += '{0:yyyy-MM-dd HH:mm}' -f $bmr.Context.RanAt
    $ctxStr = ($ctxParts -join ', ') + ' (short-burst)'
    $keys = @('CPU:', 'Memory:', '', 'Disk:', 'Context:')
    $vals = @($cpuStr, $memStr, $memRef, $diskStr, $ctxStr)
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Name = 'BenchResults'
    $panel.Location = New-Object System.Drawing.Point(0, 104)
    $panel.Size = New-Object System.Drawing.Size(600, 220)
    $panel.Anchor = 'Top,Left,Right'
    $y = Add-KvBlock -Parent $panel -Keys $keys -Values $vals -KeyW 70 -ValW 500
    $bcap = New-Object System.Windows.Forms.Label
    $bcap.Text = "Measured by this tool's own workloads - comparable across runs of this tool, not to`r`nother benchmarks. Disk is single-stream (QD1) - spec-sheet numbers need deep queues."
    $bcap.Location = New-Object System.Drawing.Point(14, ($y + 6))
    $bcap.AutoSize = $true
    $bcap.ForeColor = [System.Drawing.Color]::Gray
    $panel.Controls.Add($bcap)
    $Tab.Controls.Add($panel)
}
```

- [ ] **Step 4: Implement the Benchmark tab in `New-SystemForm`**

Insert between the Live tab block's closing `}` and the Network tab block:

```powershell
    # --- Benchmark tab (on-demand prober; always present - runs only on click) ---
    $tabBench = New-Object System.Windows.Forms.TabPage
    $tabBench.Text = 'Benchmark'
    $bCap = New-Object System.Windows.Forms.Label
    $bCap.Text = "Measures this machine right now - CPU arithmetic, memory bandwidth, disk read.`r`nTakes ~10-15 seconds and loads the machine. Nothing runs until you click."
    $bCap.Location = New-Object System.Drawing.Point(14, 14)
    $bCap.AutoSize = $true
    $tabBench.Controls.Add($bCap)
    $btnRun = New-Object System.Windows.Forms.Button
    $btnRun.Text = 'Run benchmarks'
    $btnRun.Size = New-Object System.Drawing.Size(130, 30)
    $btnRun.Location = New-Object System.Drawing.Point(14, 64)
    $tabBench.Controls.Add($btnRun)
    $bStatus = New-Object System.Windows.Forms.Label
    $bStatus.Text = ''
    $bStatus.Location = New-Object System.Drawing.Point(154, 71)
    $bStatus.AutoSize = $true
    $bStatus.ForeColor = [System.Drawing.Color]::Gray
    $tabBench.Controls.Add($bStatus)
    if ($Report.Benchmark) { Add-BenchmarkResults -Tab $tabBench -Benchmark $Report.Benchmark }
    $btnRun.Add_Click({
        $btnRun.Enabled = $false
        $onStage = { param($msg) $bStatus.Text = "Running: $msg..."; [System.Windows.Forms.Application]::DoEvents() }.GetNewClosure()
        $bundle = Invoke-BenchmarkSuite -OnStage $onStage
        $Report.Benchmark = New-BenchmarkReport -Raw $bundle -Memory $Report.Memory -Battery $Report.Battery -RanAt (Get-Date)
        Add-BenchmarkResults -Tab $tabBench -Benchmark $Report.Benchmark
        $bStatus.Text = "Done in $($bundle.ElapsedS)s"
        $btnRun.Text = 'Run again'
        $btnRun.Enabled = $true
    }.GetNewClosure())
    [void]$tabs.TabPages.Add($tabBench)
```

- [ ] **Step 5: Implement the Copy fix**

Replace (in the Buttons region, ~line 2301-2305):
```powershell
    $copyText = (Write-SystemConsole $Report | Out-String).Trim()
    $btnCopy.Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText($copyText); $btnCopy.Text = 'Copied!' }
        catch { $btnCopy.Text = 'Copy failed' }
    }.GetNewClosure())
```
with:
```powershell
    # Rendered at click time (not form-build time) so an on-demand benchmark run
    # is included once it exists; output is otherwise identical.
    $btnCopy.Add_Click({
        try { [System.Windows.Forms.Clipboard]::SetText((Write-SystemConsole $Report | Out-String).Trim()); $btnCopy.Text = 'Copied!' }
        catch { $btnCopy.Text = 'Copy failed' }
    }.GetNewClosure())
```

- [ ] **Step 6: Run both suites to verify everything passes**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1`
Expected: "GUI smoke: all passed" (65 checks: 57 + 8 new), exit 0.
Run: `pwsh -File tests/SystemInfo.Tests.ps1`
Expected: 0 FAIL (448 — unchanged by this task).

- [ ] **Step 7: Commit**

```bash
git add Show-SystemInfo.ps1 tests/GuiSmoke.ps1
git commit -m "Benchmarks: GUI tab + results renderer + Copy click-time render (slice L)"
```

---

### Task 6: End-to-end verification + reference capture

**Files:**
- Modify: `docs/superpowers/specs/2026-07-04-benchmark-design.md` (Reference data section only)

- [ ] **Step 1: Run both suites one final time**

Run: `pwsh -File tests/SystemInfo.Tests.ps1` → 0 FAIL (448).
Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/GuiSmoke.ps1` → all passed (65), exit 0.

- [ ] **Step 2: Real `-Benchmark` run and reference capture**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Show-SystemInfo.ps1 -Benchmark`
Expected shape (numbers vary somewhat run to run):

```
Running benchmarks (~10-15 s)...
  compiling workloads (one-time)...
  CPU (single-thread)...
  ...
  Benchmarks
  ----------
  CPU              : ~1,000 arith Mops/s single-thread -> ~11,000 all-threads (~10-11x on 16 threads)
  Memory           : ~19 GB/s copy (1 thread) / ~25-40 GB/s (all threads); theoretical peak ~46.9 GB/s (assumes dual-channel)
  Disk             : C: ~1,000-1,200 MB/s sequential / ~4,000-6,000 IOPS random 4K
  Context          : on AC power, Balanced plan, <timestamp> (short-burst)
```

If the memory line reads `Unavailable (low available memory (...))` instead, that is the guard working as designed on a pressured machine — free RAM (close apps) and re-run once to capture the full numbers. Confirm the temp file is gone afterward (`Test-Path` on `$env:TEMP\SystemInfo-diskbench.tmp` → False).

- [ ] **Step 3: Record the real numbers in the spec**

Edit `docs/superpowers/specs/2026-07-04-benchmark-design.md` — replace the "Reference data" section's expectations paragraph with the actual captured numbers (CPU ST/MT + scale, memory ST/MT vs 46.9, disk seq/rand, whether the memory guard fired on first attempt).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-04-benchmark-design.md
git commit -m "Benchmarks: record dev-machine reference capture (slice L)"
```

- [ ] **Step 5: Report done**

The branch is ready for the finishing flow (final whole-slice review → fast-forward merge to `main` → push), which the session drives via superpowers:finishing-a-development-branch.
