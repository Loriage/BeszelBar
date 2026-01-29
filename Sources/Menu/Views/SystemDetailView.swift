import SwiftUI

struct SystemDetailView: View {
    let system: SystemRecord
    var details: SystemDetailsRecord? = nil

    // Computed properties to get CPU info from either source
    private var cpuModel: String? {
        // Prefer system_details (v0.18.0+), fallback to info
        details?.cpu ?? system.info?.m
    }

    private var cpuCores: Int? {
        details?.cores ?? system.info?.c
    }

    private var hostname: String? {
        details?.hostname ?? system.info?.h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // System info header
            VStack(alignment: .leading, spacing: 2) {
                // Line 1: Hostname + uptime
                HStack {
                    let displayName = hostname ?? system.name
                    Label {
                        Text(displayName)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "desktopcomputer")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                    Spacer()
                }

                // Line 2: CPU info (only if available from either source)
                if cpuModel != nil || cpuCores != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9))
                        if let model = cpuModel {
                            Text(model)
                                .lineLimit(1)
                        }
                        if let cores = cpuCores {
                            if cpuModel != nil {
                                Text("•")
                            }
                            Text("\(cores) cores")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }

                // Line 3: Temperature and uptime
                if system.info?.dt != nil || system.info?.u != nil {
                    HStack(spacing: 12) {
                        if let temp = system.info?.dt {
                            Label(String(format: "%.0f°C", temp), systemImage: "thermometer.medium")
                                .foregroundColor(temp > 80 ? .red : (temp > 60 ? .orange : .secondary))
                        }
                        if let uptime = system.info?.u {
                            Label(formatUptime(uptime), systemImage: "clock")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.system(size: 10))
                }
            }

            // Divider
            Divider()
                .padding(.vertical, 2)

            // Metrics section
            VStack(alignment: .leading, spacing: 6) {
                Label("Usage", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                if let cpu = system.cpuPercentage {
                    MetricBar(label: "CPU", value: cpu, color: valueColor(cpu))
                }
                if let mem = system.memoryPercentage {
                    MetricBar(label: "Memory", value: mem, color: valueColor(mem))
                }
                if let disk = system.diskPercentage {
                    MetricBar(label: "Disk", value: disk, color: valueColor(disk))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: 240)
    }

    private func formatUptime(_ seconds: Double) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        if days > 0 {
            return "\(days)d \(hours)h"
        } else {
            let mins = (Int(seconds) % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }

    private func formatBandwidth(_ mb: Double) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB/s", mb / 1024)
        }
        return String(format: "%.1f MB/s", mb)
    }

    private func valueColor(_ value: Double) -> Color {
        if value >= 90 { return AppColors.red }
        if value >= 70 { return AppColors.orange }
        return AppColors.green
    }
}

enum AppColors {
    static let green = Color.green
    static let orange = Color.orange
    static let red = Color.red
    static let gray = Color.gray
}

struct MetricBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(value))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geometry.size.width * min(value / 100, 1.0), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}
