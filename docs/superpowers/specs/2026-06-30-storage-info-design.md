# System Info — Storage + notes (slice C)

- **Date:** 2026-06-30
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/storage_info` (based on slice B)
- **Part of:** full system-info effort (A=CPU, B=GPU done, **C=Storage**, final).

## Goal

Add a Storage subsystem: physical disks and volumes, with disk-type detection
and storage health/space bottleneck notes. Completes the "full system
bottleneck" picture. Reuses the established subsystem pattern.

## Decisions (chosen by user)

- **Display:** both physical disks and volumes (drive letters + free space).
- **Notes:** boot-drive-is-HDD, low-free-space, disk-health, SATA-SSD-upgrade-hint.
- **Low-space threshold:** a volume under **10% free** OR under **25 GB free**.

## Architecture

- **`Get-StorageInfo`** (collector) — `Get-PhysicalDisk` (FriendlyName, MediaType,
  BusType, Size, HealthStatus), `Get-Disk` (Number, IsBoot/IsSystem -> mark the
  boot disk), `Get-Volume` (DriveLetter, FileSystemLabel, FileSystemType, Size,
  SizeRemaining). Wrapped in try/catch; returns `{ Disks=@(raw); Volumes=@(raw) }`.
  Boot disk matched to a physical disk by disk Number == PhysicalDisk DeviceId.
- **`New-StorageReport`** (pure) — `-Disks <raw> -Volumes <raw>` -> the Storage
  section `{ Disks=@(...); Volumes=@(...) }`.
- **`Get-DiskKind`** (pure) — NVMe SSD / SATA SSD / HDD / Unknown.
- **`Get-StorageInsights`** (pure) — storage notes.
- Wired into `Get-SystemInsights` and `New-SystemReport` (now `-Storage`).
  `Invoke-SystemInfo` collects storage and passes it through.

## Per-disk / per-volume fields

**Disk** (`New-StorageReport` output): `{ Name; Kind; SizeGB; Health; IsBoot; MediaType; Bus }`.
**Volume:** `{ DriveLetter; Label; FileSystem; SizeGB; FreeGB; FreePercent }`
(FreePercent = round(FreeBytes / SizeBytes * 100)).

### `Get-DiskKind` (pure)

`-Name -MediaType -BusType`:
- `isNvme` = BusType matches `NVMe` OR Name matches `NVMe` (covers Intel RST
  "RAID" bus where the name still says NVMe).
- SSD (MediaType `SSD`/4) -> `NVMe SSD` if isNvme else `SATA SSD`.
- HDD (MediaType `HDD`/3) -> `HDD`.
- else if isNvme -> `NVMe SSD`; else `Unknown`.

## Insights (`Get-StorageInsights`)

- **Boot on HDD:** a disk `IsBoot -and Kind -eq 'HDD'` ->
  *warn:* "Windows is installed on a mechanical hard drive - the single biggest
  slowdown on an otherwise capable PC. Moving to an SSD would transform it."
- **Low free space** (per volume): `FreePercent -lt 10 -or FreeGB -lt 25` ->
  *warn:* "Drive X: is low on space (Y GB free, Z%). Free up space - drives slow
  down and Windows struggles when nearly full."
- **Disk health:** a disk `Health -ne 'Healthy'` (and not blank) ->
  *warn:* "Disk <name> reports health '<status>' - back up your data and run a
  check (e.g. CrystalDiskInfo / manufacturer tool)."
- **SATA SSD hint:** a disk `IsBoot -and Kind -eq 'SATA SSD'` ->
  *info:* "Boot drive is a SATA SSD; an NVMe SSD is several times faster if your
  system has an M.2 NVMe slot."

## GUI / console

- **Storage tab** (after Memory): a **Disks** ListView (Disk · Type · Size ·
  Health · Boot) on top, a **Volumes** ListView (Drive · Label · FS · Size ·
  Free · Free%) below. Last column of each fills width.
- **Overview** gains a *Storage:* one-liner from the boot disk + its volume:
  e.g. "512 GB NVMe SSD - 102 GB free on C:".
- **Console** gains a *Storage* section: a disks table then a volumes table,
  before Notes. Tab order: Overview / CPU / GPU / Memory / Storage.

## Reference data (dev machine, 2026-06-30)

One physical disk: `NVMe PC611 NVMe SK hynix 512GB` - MediaType SSD, BusType
**RAID** (Intel RST; name reveals NVMe), 477 GB, Healthy, boot+system. Volume
C: "OS" NTFS, 458.7 GB total, 102.2 GB free (~22%). No notes fire (healthy NVMe,
ample space).

## Testing

- TDD pure units: `Get-DiskKind` (NVMe via bus, NVMe via name over RAID, SATA
  SSD, HDD, Unknown), `New-StorageReport` (disk kind/boot, volume free%),
  `Get-StorageInsights` (boot-HDD, low-space by % and by GB, unhealthy,
  SATA-SSD-hint, and the healthy-NVMe no-note case).
- Collector `Get-StorageInfo` + Storage cmdlets: verified by the `-Console` run
  on real hardware (NVMe SSD boot disk, C: free space).
- Storage tab: smoke (tab + two ListViews) + off-screen render.

## Out of scope (YAGNI)

- SMART attribute detail, temperatures, TBW/wear, partition layout.
- Network/removable drive analysis beyond what Get-Volume returns.
- This is the last planned subsystem; after it the tool is "full system".
