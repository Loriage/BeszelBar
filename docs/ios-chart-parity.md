# Beszel iOS chart parity

The chart components and data models originate from `Loriage/Beszel-Swift-App`, local revision `e262400`, as present in the iOS working tree on 2026-09-16. Source components are retained under `Sources/Dashboard/iOS` and source chart models under `Sources/Models/iOS`.

## Preserved design

- `MonitoringDesignSystem`, `CardGroupBoxStyle`, `SystemSummaryCard`, and the original Swift Charts components.
- iOS font point sizes are explicit because the identically named macOS semantic fonts are smaller.
- Card radius, padding, half-point border, grouped light/dark surfaces, metric severity colors and seven-point progress bars.
- Chart colors, area gradients, dashed comparison lines, axes, units, subtitles and legends.
- The five iOS intervals: 1h/12h/24h/7d/30d and their 1m/10m/20m/120m/480m record types.

## Chart inventory

| Family | Charts | iOS components |
| --- | --- | --- |
| CPU | Usage, load, time breakdown, all cores, each individual core | `SystemMetricChartView`, `SystemLoadChartView`, `SystemCpuTimeBreakdownChartView`, `SystemCpuCoresChartView`, plot from `SystemCpuDetailView` |
| Memory | Usage, swap | `SystemMetricChartView`, `SystemSwapChartView` |
| Root disk | Capacity, I/O rate, utilization, I/O times, await, queue depth, cumulative reads/writes | `SystemDisk*ChartView`, `StorageHistoryChart` |
| Additional disks | Capacity, I/O rate, utilization, I/O times, await, queue depth, cumulative reads/writes for each disk | `ExtraDisk*ChartView`, `StorageHistoryChart` |
| ZFS | Pool usage and pool I/O | `StorageHistoryChart` |
| Network | Overall bandwidth, interfaces, interface download/upload, cumulative received/sent | `SystemBandwidthChartView`, `SystemNetworkInterfacesChartView`, `Bandwidth*ChartView` |
| Sensors | Temperatures, batteries, fan speed | `SystemTemperatureChartView`, `SensorHistoryChart` |
| GPU | Usage, device/package power, memory, engines | `SystemGPUChartView` and the complete iOS GPU model |
| Containers | Stacked CPU/memory/network, detail charts and tables, individual CPU/memory | `Stacked*ChartView`, `Detailed*ChartView`, `ContainerMetricChartView` |

All categories are accessible directly from the dashboard. Individual container charts are selected by container name, so a server with dozens of containers does not force hundreds of charts into the initial overview. Hardware-dependent charts appear only when their source measurements exist.

## macOS integration

The iOS settings and pin managers are adapted to BeszelBar. Date labels use an explicit anchor on macOS. The optional `drawingGroup` rasterization is removed because it clipped chart-axis text on macOS; the native Swift Charts drawing is preserved. Disk/network axes use one unit throughout each chart; these small correctness fixes preserve the source drawing style. Pin identities include hub UUID and system record ID. The iOS single-core plot is extracted into `SingleCPUCoreChart`. ZFS and disk-counter headers show the pool/disk name because multiple cards coexist in the dashboard. Container rows navigate to their history; alert cards retain the iOS visual structure.

`ChartDataLoader` loads mandatory system history and optional container/ZFS history. `ChartDataSet` prepares the chart models and three stacks per response. Like iOS, each stack orders containers by ascending average usage for its metric (CPU, memory or combined network traffic), with the palette following that order. Data errors remain visible and refreshes retain the last successful history. No demo data is compiled into the product.

## Verification

- Model tests cover advanced fields, availability, zero readings, stacked totals and unique chart identities.
- Native SwiftUI render tests cover every catalog chart in light and dark mode. The application test host loads the real translations without reading ordinary preferences or Keychain entries.
- The opt-in live test reads both systems on the authorized demo hub, their container history and all five periods, and renders their real charts.
- Interactive checks on the Mac cover hub setup, all five periods, categories, pins, container search/history, and chart scrubbing with a dated values table. Actual window captures are stored separately from native offscreen renders.
- In isolated Debug demo sessions only, chart accessibility is compacted to one node to avoid a crash in the Mac automation helper while it expands Swift Charts. Production accessibility is unchanged. This is not a VoiceOver validation.
