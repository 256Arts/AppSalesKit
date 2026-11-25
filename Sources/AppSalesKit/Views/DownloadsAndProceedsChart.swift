#if !os(watchOS)
import SwiftUI
import Charts

public struct DownloadsAndProceedsChart: View {

    /// In the order their bars stand, top down: the first `limit` get a row each, and the rest share
    /// an Other row beneath them — unless there is only one more, which takes the row itself.
    public let apps: [AppPerformanceSummary]
    public let iconLength: CGFloat
    /// Each app's average daily active devices, keyed by Apple ID; `nil` leaves their bars out.
    public var activeDevices: [String: Int]?

    public init(apps: [AppPerformanceSummary], iconLength: CGFloat, activeDevices: [String: Int]? = nil) {
        self.apps = apps
        self.iconLength = iconLength
        self.activeDevices = activeDevices
    }

    public static let limit = 4

    private struct Row: Identifiable {
        public let id: String
        public let app: AppPerformanceSummary?
        public let downloads: Double
        public let proceeds: Double
        public let activeDevices: Double
        /// The change on the window before, `nil` without one to compare against.
        public let downloadsChange: Double?
        public let proceedsChange: Double?
    }

    private var rows: [Row] {
        let shown = apps.count == Self.limit + 1 ? apps.count : Self.limit
        var rows = apps.prefix(shown).map { app in
            Row(
                id: app.appleID,
                app: app,
                downloads: Double(app.downloads),
                proceeds: app.proceeds,
                activeDevices: Double(activeDevices?[app.appleID] ?? 0),
                downloadsChange: app.downloadsPercentageChange,
                proceedsChange: app.proceedsPercentageChange)
        }
        let rest = apps.dropFirst(shown)
        if !rest.isEmpty {
            let downloads = Double(rest.reduce(0) { $0 + $1.downloads })
            let proceeds = rest.reduce(0) { $0 + $1.proceeds }
            let prevDownloads = rest.allSatisfy { $0.prevDownloads != nil } ? Double(rest.reduce(0) { $0 + ($1.prevDownloads ?? 0) }) : nil
            let prevProceeds = rest.allSatisfy { $0.prevProceeds != nil } ? rest.reduce(0) { $0 + ($1.prevProceeds ?? 0) } : nil
            rows.append(Row(
                id: "Other",
                app: nil,
                downloads: downloads,
                proceeds: proceeds,
                activeDevices: Double(rest.reduce(0) { $0 + (activeDevices?[$1.appleID] ?? 0) }),
                downloadsChange: prevDownloads.map { PerformanceSummary.percentageChange(from: $0, to: downloads) },
                proceedsChange: prevProceeds.map { PerformanceSummary.percentageChange(from: $0, to: proceeds) }))
        }
        return rows
    }

    public var body: some View {
        let rows = rows
        Chart {
            ForEach(rows) { row in
                bar(for: row, series: "Downloads", value: row.downloads, change: row.downloadsChange)
                bar(for: row, series: "Proceeds", value: row.proceeds, change: row.proceedsChange)
                if activeDevices != nil {
                    // The analytics reports carry no earlier window, so these bars go without an arrow.
                    bar(for: row, series: "Daily Active Devices", value: row.activeDevices, change: nil)
                }
            }
        }
        // The same colours as the home screen's figures above the chart, which stand in for its legend.
        .chartForegroundStyleScale([
            "Downloads": Color.blue,
            "Proceeds": Color.green,
            "Daily Active Devices": Color.orange
        ])
        .chartXAxis {
            AxisMarks(position: .top)
        }
        .chartYScale(domain: rows.map(\.id))
        // The axis only holds the icons' room: Charts sets a categorical label on its band's top
        // edge whatever its anchor, so the icons are laid in the overlay, across each band's middle.
        .chartYAxis {
            AxisMarks(preset: .extended, position: .leading, values: rows.map(\.id)) { axis in
                AxisValueLabel(horizontalSpacing: Self.iconSpacing) {
                    Color.clear
                        .frame(width: iconLength, height: iconLength)
                        .accessibilityLabel(rows[axis.index].app?.name ?? String(localized: "Other", bundle: #bundle))
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    ForEach(rows) { row in
                        if let y = proxy.position(forY: row.id) {
                            icon(for: row)
                                .position(x: frame.minX - Self.iconSpacing - iconLength / 2, y: frame.minY + y)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    private static let iconSpacing: CGFloat = 8

    @ViewBuilder
    private func icon(for row: Row) -> some View {
        if let app = row.app {
            AppIconView(app: app, length: iconLength)
        } else {
            Image(systemName: "app.grid.2x2.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: iconLength, height: iconLength)
        }
    }

    /// A bar with an arrow past its end, green up and red down, for its change on the window
    /// before — none when it held level or has nothing to compare against.
    private func bar(for row: Row, series: String, value: Double, change: Double?) -> some ChartContent {
        BarMark(x: .value(series, value), y: .value(String(localized: "App", bundle: #bundle), row.id))
            .foregroundStyle(by: .value(String(localized: "Data Type", bundle: #bundle), series))
            .position(by: .value(String(localized: "Data Type", bundle: #bundle), series))
            .annotation(position: .trailing, alignment: .leading, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                if let change, change != 0 {
                    Image(systemName: change < 0 ? "arrowtriangle.backward.fill" : "arrowtriangle.forward.fill")
                        .font(.caption2)
                        .imageScale(.small)
                        .foregroundStyle(change < 0 ? Color.red : Color.green)
                        .accessibilityLabel(change < 0 ? Text("Down", bundle: #bundle) : Text("Up", bundle: #bundle))
                }
            }
    }
}
#endif
