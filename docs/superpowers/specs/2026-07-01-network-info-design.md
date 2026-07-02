# System Info — Network (link + Wi-Fi health) + notes (slice F)

- **Date:** 2026-07-01
- **Status:** Approved (design), pre-implementation
- **Branch:** `feature/network_info` (off `main`)
- **Part of:** full system-info effort (A=CPU … E=Live/Load done, **F=Network**).

## Goal

Show each active network adapter's link speed and — for Wi-Fi — band, signal,
and standard, with **honest** bottleneck notes. Explicitly **not** "Wi-Fi link
vs theoretical PHY max" (real Wi-Fi always runs far below it, so that would cry
wolf on every machine). Privacy: never display SSID/BSSID (the report is
shareable via Copy).

## Why this scope (honest-data findings, dev machine 2026-07-01)

Grounding showed the "link vs capability" framing only holds honestly for
**Ethernet** (a GbE port stuck at 100 Mbps = bad cable/switch). For **Wi-Fi**,
the honest signals are **band** (2.4 GHz is slow), **weak signal**, and **old
standard** (802.11n/g/b). The dev Wi-Fi (5 GHz, 802.11ax, 80% signal, 324 Mbps)
is healthy, so few notes fire here — the tab still *shows* the link info, and
notes fire on machines that actually have a problem (same as a healthy disk in
Storage).

## Architecture (mirrors the established pattern)

- **`ConvertFrom-NetshWlan`** (pure) — `-Text <string>` from
  `netsh wlan show interfaces` → `{ State; Band; RadioType; SignalPercent;
  ReceiveMbps; TransmitMbps }`. English-label regex; any missing label → `$null`
  (graceful degradation on non-English Windows — the netsh-derived fields are
  best-effort and labelled as such). Uses the first connected interface.
- **`ConvertTo-MaxLinkMbps`** (pure) — `-ValidValues <string[]>` from an
  Ethernet adapter's "Speed & Duplex" advanced property (e.g.
  `'1.0 Gbps Full Duplex'`, `'100 Mbps Half Duplex'`) → the highest speed in
  Mbps, or `$null` if none parse.
- **`Get-NetworkInfo`** (collector, I/O; verified via `-Console`) —
  `Get-NetAdapter -Physical` where `Status -eq 'Up'`; classify **Wi-Fi**
  (`PhysicalMediaType` matches `802.11`) vs **Ethernet** (`802.3`). For Wi-Fi,
  run `netsh wlan show interfaces` → `ConvertFrom-NetshWlan`. For Ethernet, read
  the "Speed & Duplex" advanced property → `ConvertTo-MaxLinkMbps`. Returns raw
  adapter objects (empty array if none up); wrapped in try/catch.
- **`New-NetworkReport`** (pure, `-Adapters <raw>`) → `{ Adapters = @(...) }`.
- **`Get-NetworkInsights`** (pure) → notes.
- Wired into **`Get-SystemInsights`** / **`New-SystemReport`** (`-Network`,
  assign-then-`+=`); **`Invoke-SystemInfo`** collects + builds it.

## Per-adapter fields (`New-NetworkReport` output)

`{ Name; Type; LinkMbps; SignalPercent; Band; Standard; MaxSupportedMbps }`

- `Type` = `Wi-Fi` | `Ethernet` | `Other`.
- `LinkMbps` = `Get-NetAdapter.Speed / 1e6` (rounded; not localized).
- `Standard` (Wi-Fi) = friendly from RadioType: `802.11ax` → `Wi-Fi 6 (802.11ax)`,
  `ac` → `Wi-Fi 5 (802.11ac)`, `n` → `Wi-Fi 4 (802.11n)`, else raw; `$null` for
  Ethernet.
- `Band` / `SignalPercent` — Wi-Fi only (from netsh); `$null` otherwise.
- `MaxSupportedMbps` — Ethernet only (from advanced property); `$null` for Wi-Fi
  (no honest "vs max" for wireless).

## Insights (`Get-NetworkInsights`)

- **Ethernet below capability:** `Type -eq 'Ethernet'` and `LinkMbps -gt 0` and
  `MaxSupportedMbps` present and `LinkMbps -lt MaxSupportedMbps` → *warn:*
  "Ethernet is linked at `<link>` Mbps but the adapter supports `<max>` Mbps —
  usually a bad cable, a slow switch/port, or a duplex mismatch."
- **Wi-Fi on 2.4 GHz:** `Band` matches `2.4` → *info:* "Wi-Fi is on the slower
  2.4 GHz band; the 5 GHz (or 6 GHz) band is much faster when you're in range."
- **Weak Wi-Fi signal:** `SignalPercent` present and `-lt 40` → *info:* "Weak
  Wi-Fi signal (`<sig>`%); the link rate drops with signal — move closer to the
  router or reduce interference."
- **Old Wi-Fi standard:** `Standard` matches `802.11(n|g|b)` (not ac/ax/be) →
  *info:* "Wi-Fi is `<standard>`; 802.11ac/ax is several times faster if your
  router supports it."
- No note when data is missing (never fabricated). Notes read as present-tense
  where transient (signal/link).

## GUI / console

- **Network tab** (after Live — only when at least one adapter is up): a ListView
  — Adapter · Type · Link · Signal · Band · Standard (the Adapter column absorbs
  slack width). Tab order: Overview / CPU / GPU / Memory / Storage / Battery /
  Live / Network.
- **Overview** gains a `Network:` line: the primary connected adapter, e.g.
  `Wi-Fi  -  324 Mbps, 5 GHz, Wi-Fi 6 (80%)`, or `No active connection`. The
  Overview header panel grows one row.
- **Console**: a `Network` section before `Notes` (only when adapters exist).

## Reference data (dev machine, 2026-07-01 — Dell XPS 17 9700)

Wi-Fi: Killer AX1650s, **324 Mbps**, **5 GHz**, **802.11ax** (→ Wi-Fi 6),
**80% signal** → healthy, no notes. Ethernet: Realtek USB GbE, **Disconnected**
(not shown). So the tab displays the Wi-Fi row and fires no notes — honest.

## Testing

- **Pure `ConvertFrom-NetshWlan`:** captured fixture → Band `5 GHz`, RadioType
  `802.11ax`, Signal `80`, Rx `360`, Tx `324`; empty/garbage → nulls.
- **Pure `ConvertTo-MaxLinkMbps`:** `{'100 Mbps ...','1.0 Gbps ...'}` → 1000;
  `{'2.5 Gbps ...'}` → 2500; `{'Auto Negotiation'}` → `$null`.
- **Pure `New-NetworkReport`:** Wi-Fi row (link/band/signal/standard friendly),
  Ethernet row (max supported), Type classification.
- **Pure `Get-NetworkInsights`:** Ethernet-below-capability (100 vs 1000) → warn;
  2.4 GHz → info; weak signal (25%) → info; 802.11n → info; healthy 5 GHz ax
  80% → no note.
- **Wiring:** `-Network` flows notes; `Get-SystemInsights -Network $null` → no
  note, no error.
- **Console:** `Network` section present with adapters, absent when `$null`.
- **GUI (`GuiSmoke.ps1`):** add a Network fixture; assert **8 tabs** + a Network
  tab with a ListView; no-network case (`-Network $null`) → 7 tabs, no Network
  tab; off-screen render.

## Out of scope (YAGNI)

- Wi-Fi link vs theoretical PHY max (dishonest), throughput/speed tests, SSID or
  BSSID display, per-connection history, VPN/proxy detection, IPv4/IPv6 config,
  and precise Wi-Fi max-rate computation from streams/width.
