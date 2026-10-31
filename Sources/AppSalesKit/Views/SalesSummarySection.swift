#if !os(watchOS)
import SwiftUI

/// The summary's lead section: the 30-day figures over a chart of them, the figures doubling as the
/// chart's legend — picking one charts it app by app, day by day — with when they were last read
/// beneath. Nothing until `loader` has sales.
public struct SalesSummarySection: View {

    let loader: SalesDataLoader

    public init(loader: SalesDataLoader) {
        self.loader = loader
    }

    /// Whether the summary has the width for its figures to stand larger over the chart.
    @State private var isWide = false
    /// The stat the chart's legend has picked to chart app by app, day by day, in place of the bars.
    @State private var chartedStat: AppListSort?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @AppStorage(UserDefaults.Key.homeChartSort, store: UserDefaults.shared) private var chartSortChoice: AppListSort = .downloads
    @AppStorage(UserDefaults.Key.homeChartShowsActiveDevices, store: UserDefaults.shared) private var chartShowsActiveDevices = false

    public var body: some View {
        if let data = loader.data, let summary = loader.summary {
            Section {
                let availableActiveDevices = loader.appCounts[.activeDevices]
                let activeDevices = chartShowsActiveDevices ? availableActiveDevices : nil
                // Back to the bars once the stat it picked is off the chart.
                let shownStat = chartedStat == .activeDevices && activeDevices == nil ? nil : chartedStat
                VStack(alignment: .leading, spacing: 16) {
                    // In the chart's order, each figure's icon in its bars' colour, so the row doubles as the
                    // legend — and picking a figure charts it app by app.
                    HStack(alignment: .top, spacing: isWide ? 32 : 16) {
                        legendEntry(.downloads, charted: shownStat) {
                            SummaryStat(
                                name: "Downloads",
                                value: summary.downloads.formatted(),
                                systemImage: "arrow.down.app",
                                color: .blue,
                                isLarge: isWide,
                                change: summary.downloadsPercentageChange)
                        }
                        legendEntry(.proceeds, charted: shownStat) {
                            SummaryStat(
                                name: "Proceeds",
                                value: NumberFormatter.currency.string(from: NSNumber(value: summary.proceeds)) ?? "",
                                systemImage: "dollarsign.circle",
                                color: .green,
                                isLarge: isWide,
                                change: summary.proceedsPercentageChange,
                                // The screenshot walk waits on this before its first shot,
                                // so a capture cannot beat the fetched data onto the screen.
                                identifier: "Summary.Proceeds")
                        }
                        if activeDevices != nil, case .ready(let analytics) = loader.appStoreAnalytics {
                            // The account's devices on an average day, the funnel's figure, rather than
                            // each app's own average summed, which overcounts apps with fewer days of data.
                            let total = analytics.totals().averageDailyActiveDevices
                            legendEntry(.activeDevices, charted: shownStat) {
                                SummaryStat(
                                    name: "Daily Active Devices",
                                    value: total.formatted(),
                                    systemImage: AppListSort.activeDevices.systemImage,
                                    color: .orange,
                                    isLarge: isWide,
                                    caption: "a day")
                            }
                        } else if chartShowsActiveDevices && loader.isLoadingAppStoreAnalytics {
                            // Holds the legend's place while the analytics reports load.
                            SummaryStat(
                                name: "Daily Active Devices",
                                value: 1000.formatted(),
                                systemImage: AppListSort.activeDevices.systemImage,
                                color: .orange,
                                isLarge: isWide,
                                caption: "a day",
                                isLoading: true)
                        }

                        Spacer(minLength: 0)

                        chartMenu(activeDevicesAvailable: availableActiveDevices != nil)
                    }

                    Group {
                        if let shownStat {
                            let lines = trends(of: shownStat, data: data, apps: summary.apps, activeDevices: activeDevices)
                            AppTrendsChart(trends: lines.0, stat: shownStat, range: lines.1)
                        } else {
                            DownloadsAndProceedsChart(
                                apps: chartSort(activeDevices: activeDevices).sort(summary.apps, counts: activeDevices ?? [:]),
                                iconLength: 32,
                                activeDevices: activeDevices)
                                .chartLegend(.hidden)
                        }
                    }
                    .frame(height: chartHeight)
                }
                .padding(.vertical)
                .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { isWide = $0 }
            } footer: {
                // Two ages, and they are not the same one: when the app last asked, and how far the
                // reports it was given reach — App Store Connect publishes a day behind, so the
                // second is always older than it looks.
                HStack(spacing: 4) {
                    if let lastRefresh = loader.lastRefresh {
                        Text(updated: lastRefresh)

                        if data.latestReportingDate() != .distantPast {
                            Text(verbatim: "·")
                        }
                    }

                    if data.latestReportingDate() != .distantPast {
                        Text("Sales through \(data.latestReportingDate(), format: .dateTime.month().day())", bundle: #bundle)
                    }
                }
            }
        }
    }

    /// A legend figure that charts its stat app by app when picked, and the bars again when picked
    /// twice; the others fade while one is charted.
    private func legendEntry(_ stat: AppListSort, charted: AppListSort?, @ViewBuilder label: () -> some View) -> some View {
        Button {
            withAnimation { chartedStat = charted == stat ? nil : stat }
        } label: {
            label()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(charted == nil || charted == stat ? 1 : 0.4)
        .accessibilityAddTraits(charted == stat ? .isSelected : [])
        .accessibilityHint(charted == stat ? Text("Shows every stat again", bundle: #bundle) : Text("Charts each app's figure by day", bundle: #bundle))
    }

    /// The summary chart's height: shorter on a phone, much shorter turned on its side, where it
    /// would otherwise fill the screen, and as short on a Mac or Vision Pro, where a window that
    /// starts small would otherwise be all chart.
    private var chartHeight: CGFloat {
        #if os(iOS)
        if verticalSizeClass == .compact {
            300
        } else if horizontalSizeClass == .compact {
            360
        } else {
            420
        }
        #else
        300
        #endif
    }

    /// The best few apps by `stat`, stacked over the days its figures cover, with every other app
    /// summed into an Other layer: the summary's 30 days for sales, and the analytics reports' own
    /// 30 for active devices, which lag a few days.
    private func trends(of stat: AppListSort, data: ACData, apps: [AppPerformanceSummary], activeDevices: [String: Int]?) -> ([AppTrend], Range<Date>) {
        let sorted = stat.sort(apps, counts: activeDevices ?? [:])
        let top = sorted
            .filter { app in
                switch stat {
                case .proceeds: app.proceeds > 0
                case .activeDevices: (activeDevices?[app.appleID] ?? 0) > 0
                default: app.downloads > 0
                }
            }
            .prefix(DownloadsAndProceedsChart.limit)
        let topIDs = Set(top.map(\.appleID))
        let rest = sorted.filter { !topIDs.contains($0.appleID) }

        if stat == .activeDevices, case .ready(let analytics) = loader.appStoreAnalytics {
            func days(of apps: [AppPerformanceSummary]) -> [DailyValue] {
                Dictionary(apps.flatMap { (analytics.days[$0.appleID] ?? [:]).map { ($0.key, Double($0.value.activeDevices)) } }, uniquingKeysWith: +)
                    .sorted { $0.key < $1.key }
                    .map { DailyValue(date: $0.key, value: $0.value) }
            }
            var trends = top.map { AppTrend(app: $0, days: days(of: [$0])) }
            let other = days(of: rest)
            if other.contains(where: { $0.value > 0 }) {
                trends.append(rest.count == 1 ? AppTrend(app: rest[0], days: other) : AppTrend(otherDays: other))
            }
            return (trends, analytics.range)
        }

        let range = (Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now)..<Date.now
        let type: InfoType = stat == .proceeds ? .proceeds : .downloads
        var trends = top.map { app in
            AppTrend(app: app, days: data.dailyTotals(for: type, in: range, filteredApps: data.apps.filter { $0.appleID == app.appleID }))
        }
        let restIDs = Set(rest.map(\.appleID))
        let restApps = data.apps.filter { restIDs.contains($0.appleID) }
        // An empty filter means every app, so there is no Other without apps to put in it.
        if !restApps.isEmpty {
            let other = data.dailyTotals(for: type, in: range, filteredApps: restApps)
            if other.contains(where: { $0.value > 0 }) {
                // One app left over takes its own layer rather than an Other of one.
                trends.append(rest.count == 1 ? AppTrend(app: rest[0], days: other) : AppTrend(otherDays: other))
            }
        }
        return (trends, range)
    }

    /// The figures the chart can be sorted by, in the order its bars stand.
    private static let chartSorts: [AppListSort] = [.downloads, .proceeds, .activeDevices]

    /// Downloads while the chosen sort's figures are not on the chart.
    private func chartSort(activeDevices: [String: Int]?) -> AppListSort {
        chartSortChoice == .activeDevices && activeDevices == nil ? .downloads : chartSortChoice
    }

    /// Daily active devices come from the analytics reports, so they can only be turned on once
    /// those have figures — or off, whenever they are on.
    private func chartMenu(activeDevicesAvailable: Bool) -> some View {
        Menu {
            Toggle(isOn: $chartShowsActiveDevices) {
                Label(AppListSort.activeDevices.title, systemImage: AppListSort.activeDevices.systemImage)
            }
            .disabled(!activeDevicesAvailable && !chartShowsActiveDevices)

            Picker(String(localized: "Sort By", bundle: #bundle), selection: $chartSortChoice) {
                ForEach(Self.chartSorts.filter { $0 != .activeDevices || chartShowsActiveDevices }) { sort in
                    Label(sort.title, systemImage: sort.systemImage)
                        .tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(String(localized: "Chart Options", bundle: #bundle), systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuIndicator(.hidden)
        .onChange(of: chartShowsActiveDevices) {
            if !chartShowsActiveDevices, chartSortChoice == .activeDevices {
                chartSortChoice = .downloads
            }
        }
    }
}

/// The conversion funnel, from the webpage to active devices — a placeholder while the analytics
/// reports load, and nothing without a stage ahead of downloads.
public struct FunnelSection: View {

    let loader: SalesDataLoader

    public init(loader: SalesDataLoader) {
        self.loader = loader
    }

    public var body: some View {
        if loader.appStoreAnalytics == nil && loader.isLoadingAppStoreAnalytics {
            Section(String(localized: "Funnel", bundle: #bundle)) {
                ConversionFunnel(stages: FunnelStage.placeholders(website: loader.showsWebsite))
                    .redacted(reason: .placeholder)
                    .accessibilityLabel(Text("Loading", bundle: #bundle))
            }
        } else if let funnel = loader.funnel {
            Section(String(localized: "Funnel", bundle: #bundle)) {
                ConversionFunnel(stages: funnel)
            }
        }
    }
}

extension SharePiesSection {
    /// Every app's shares, from `loader`. Nothing until it has sales.
    public init(loader: SalesDataLoader) {
        self.init(data: loader.data ?? ACData(entries: [], currency: .USD, apps: []), analytics: loader.appStoreAnalytics, isLoadingAnalytics: loader.isLoadingAppStoreAnalytics)
    }
}

extension InsightsView {
    /// Insights on `loader`'s summary and funnel. Nothing until it has sales.
    public init(loader: SalesDataLoader) {
        self.init(summary: loader.summary, funnel: loader.funnel ?? [])
    }
}

/// One figure above the summary's chart: its icon in the colour of its bars, and beneath it
/// the change from the 30 days before, or a caption for a figure with nothing to compare against.
private struct SummaryStat: View {

    /// What VoiceOver reads for the icon.
    let name: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color
    /// Beside a wide chart, where the title3 figures would look lost.
    var isLarge = false
    var change: Double?
    var caption: LocalizedStringKey?
    var identifier = ""
    /// Shows `value` and `caption` as placeholders, the figure still on its way.
    var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .symbolVariant(.fill)
                    .foregroundStyle(color)
                    .accessibilityLabel(Text(name, bundle: #bundle))
                Text(value)
                    .redacted(reason: isLoading ? .placeholder : [])
                    .accessibilityLabel(isLoading ? Text("Loading", bundle: #bundle) : Text(value))
            }
            .font((isLarge ? Font.title : .title3).weight(.semibold))

            Group {
                if let change {
                    PercentChange(change: change)
                } else if let caption {
                    Text(caption, bundle: #bundle)
                        .foregroundStyle(.secondary)
                        .redacted(reason: isLoading ? .placeholder : [])
                }
            }
            .font(isLarge ? .body : .subheadline)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

#Preview {
    List {
        SalesSummarySection(loader: SalesDataLoader(data: .example, lastRefresh: .now))
    }
}
#endif
