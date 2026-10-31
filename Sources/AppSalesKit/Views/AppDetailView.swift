#if !os(watchOS)
import SwiftUI
import Charts

/// Everything there is to know about one app: its sales over the last 30 days and the devices they
/// came from, its webpage's views, its App Store analytics, and — when the host passes
/// `AppReviewsSection` as `reviews` — what its customers are saying.
public struct AppDetailView<Reviews: View>: View {

    let app: AppPerformanceSummary
    let loader: SalesDataLoader
    let reviews: Reviews

    /// - Parameter reviews: Sections after the analytics, such as `AppReviewsSection(account:appleID:)`.
    public init(app: AppPerformanceSummary, loader: SalesDataLoader, @ViewBuilder reviews: () -> Reviews) {
        self.app = app
        self.loader = loader
        self.reviews = reviews()
    }

    @State private var editingWebsitePage: AppPerformanceSummary?
    @Environment(\.openURL) private var openURL

    private var data: ACData {
        loader.data ?? ACData(entries: [], currency: .USD, apps: [])
    }
    private var websiteTraffic: WebPageTraffic? {
        loader.websiteTraffic[app.appleID]
    }
    private var showsWebsite: Bool {
        loader.showsWebsite
    }
    private var analytics: AnalyticsAvailability? {
        loader.appStoreAnalytics
    }

    /// The same 30 days as the home screen's downloads and proceeds.
    private let range = (Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now)..<Date.now

    private var acApps: [ACApp] {
        data.apps.filter { $0.appleID == app.appleID }
    }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    AppIconView(app: app, length: 72)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name)
                            .font(.title2.bold())
                            // The screenshot walk waits on this before photographing the app's page.
                            .accessibilityIdentifier("AppDetail.Name")
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text(priceString)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section {
                Chart(dailySeries) { point in
                    LineMark(x: .value(String(localized: "Day", bundle: #bundle), point.date, unit: .day), y: .value(point.series, point.value))
                        .foregroundStyle(by: .value(String(localized: "Data Type", bundle: #bundle), point.series))
                        .interpolationMethod(.monotone)
                }
                // The same colours as the home screen's chart.
                .chartForegroundStyleScale([
                    "Downloads": Color.blue,
                    "Proceeds": Color.green,
                    "Daily Active Devices": Color.orange
                ])
                .chartXScale(domain: range.lowerBound...range.upperBound)
                .frame(height: 180)
                .padding(.vertical, 4)

                LabeledContent {
                    Text(app.downloads, format: .number)
                } label: {
                    Label(String(localized: "Downloads", bundle: #bundle), systemImage: "arrow.down.app")
                }
                LabeledContent {
                    Text(NumberFormatter.currency.string(from: NSNumber(value: app.proceeds)) ?? "")
                } label: {
                    Label(String(localized: "Proceeds", bundle: #bundle), systemImage: "dollarsign.circle")
                }
                if app.adProceeds > 0 {
                    // Where the proceeds above came from, for an app that also earns from ads.
                    LabeledContent {
                        Text(NumberFormatter.currency.string(from: NSNumber(value: app.proceeds - app.adProceeds)) ?? "")
                    } label: {
                        Label(String(localized: "App Store Sales", bundle: #bundle), image: .logoAppstore)
                    }
                    LabeledContent {
                        Text(NumberFormatter.currency.string(from: NSNumber(value: app.adProceeds)) ?? "")
                    } label: {
                        Label(String(localized: "Ad Earnings", bundle: #bundle), systemImage: "rectangle.stack.badge.play")
                    }
                }
                LabeledContent {
                    Text(Int(data.getTotal(for: .updates, in: range, filteredApps: acApps)), format: .number)
                } label: {
                    Label(String(localized: "Updates", bundle: #bundle), systemImage: "arrow.triangle.2.circlepath")
                }
                LabeledContent {
                    Text(Int(data.getTotal(for: .iap, in: range, filteredApps: acApps)), format: .number)
                } label: {
                    Label(String(localized: "In-App Purchases", bundle: #bundle), systemImage: "cart")
                }
            } header: {
                Text("Last 30 Days", bundle: #bundle)
            }

            SharePiesSection(data: data, filteredApps: acApps, analytics: analytics, isLoadingAnalytics: loader.isLoadingAppStoreAnalytics)

            if showsWebsite {
                Section(String(localized: "Webpage", bundle: #bundle)) {
                    LabeledContent {
                        if let views = websiteTraffic?.views {
                            Text(views, format: .number)
                        } else {
                            Text("—", bundle: #bundle)
                                .accessibilityLabel(Text("Not available", bundle: #bundle))
                        }
                    } label: {
                        Label(String(localized: "Page Views", bundle: #bundle), systemImage: "globe")
                    }
                }
            }

            if let analytics {
                Section {
                    switch analytics {
                    case .ready(let analytics):
                        AnalyticsTotalsRows(totals: analytics.totals(for: app.appleID), downloads: Int(data.getTotal(for: .downloads, in: analytics.range, filteredApps: acApps)))
                    case .preparing:
                        Text("App Store Connect is preparing analytics reports for your apps. The first ones usually arrive within two days.", bundle: #bundle)
                            .foregroundStyle(.secondary)
                    case .needsAdminKey:
                        Text("Analytics reports need to be turned on once with an API key that has the Admin role. After that, a Sales and Reports key can read them.", bundle: #bundle)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("App Store Analytics", bundle: #bundle)
                } footer: {
                    if case .ready(let analytics) = analytics {
                        Text("30 days through \(analytics.range.upperBound.addingTimeInterval(-1), format: .dateTime.month().day()), the latest reported.", bundle: #bundle)
                    }
                }
            }

            reviews
        }
        .navigationTitle(app.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button(String(localized: "View on the App Store", bundle: #bundle), image: .logoAppstore) {
                    openURL(app.url)
                }
                .help(Text("View on the App Store", bundle: #bundle))
            }
            if websiteTraffic?.url != nil || showsWebsite {
                #if !os(visionOS)
                ToolbarSpacer(.fixed)
                #endif
                ToolbarItem {
                    webpageButton
                }
            }
        }
        .websitePageEditor(for: $editingWebsitePage, currentURL: websiteTraffic?.url)
    }

    /// Opens the webpage, with setting it as the secondary action, which macOS shows behind a chevron.
    @ViewBuilder private var webpageButton: some View {
        switch (websiteTraffic?.url, showsWebsite) {
        case (let url?, true):
            Menu {
                setWebpageButton
            } label: {
                Label(String(localized: "Open Webpage", bundle: #bundle), systemImage: "safari")
            } primaryAction: {
                openURL(url)
            }
            .help(Text("Open Webpage", bundle: #bundle))
        case (let url?, false):
            Button(String(localized: "Open Webpage", bundle: #bundle), systemImage: "safari") {
                openURL(url)
            }
            .help(Text("Open Webpage", bundle: #bundle))
        case (nil, _):
            setWebpageButton
                .help(Text("Set Webpage…", bundle: #bundle))
        }
    }

    private var setWebpageButton: some View {
        Button(String(localized: "Set Webpage…", bundle: #bundle), systemImage: "pencil") {
            editingWebsitePage = app
        }
    }

    private var priceString: String {
        guard app.price > 0 else { return String(localized: "Free", bundle: #bundle) }

        return NumberFormatter.currency.string(from: NSNumber(value: app.price)) ?? ""
    }

    /// A point per day for downloads and proceeds, with days that sold nothing at zero rather than
    /// skipped, plus active devices for the days the analytics reports cover.
    private var dailySeries: [ChartPoint] {
        var points = [("Downloads", InfoType.downloads), ("Proceeds", .proceeds)].flatMap { series, type in
            data.dailyTotals(for: type, in: range, filteredApps: acApps)
                .map { ChartPoint(series: series, date: $0.date, value: $0.value) }
        }
        if case .ready(let analytics) = analytics {
            points += (analytics.days[app.appleID] ?? [:])
                .filter { range.contains($0.key) }
                .sorted { $0.key < $1.key }
                .map { ChartPoint(series: "Daily Active Devices", date: $0.key, value: Double($0.value.activeDevices)) }
        }
        return points
    }
}

private struct ChartPoint: Identifiable {
    public let series: String
    public let date: Date
    public let value: Double

    public var id: String { "\(series)-\(date.timeIntervalSinceReferenceDate)" }
}

/// The funnel from being seen to being used, as one row per figure.
private struct AnalyticsTotalsRows: View {

    public let totals: AnalyticsTotals
    public let downloads: Int

    public var body: some View {
        LabeledContent {
            Text(totals.impressions, format: .number)
        } label: {
            Label(String(localized: "Impressions", bundle: #bundle), systemImage: "eye")
        }
        LabeledContent {
            Text(totals.pageViews, format: .number)
        } label: {
            Label(String(localized: "Product Page Views", bundle: #bundle), systemImage: "doc.text.magnifyingglass")
        }
        LabeledContent {
            Text(downloads, format: .number)
        } label: {
            Label(String(localized: "Downloads", bundle: #bundle), systemImage: "arrow.down.app")
        }
        LabeledContent {
            if let rate = totals.conversionRate(downloads: downloads) {
                Text(rate, format: .percent.precision(.fractionLength(0...1)))
            } else {
                Text("—", bundle: #bundle)
                    .accessibilityLabel(Text("Not available", bundle: #bundle))
            }
        } label: {
            Label(String(localized: "Conversion Rate", bundle: #bundle), systemImage: "percent")
        }
        LabeledContent {
            Text(totals.sessions, format: .number)
        } label: {
            Label(String(localized: "Sessions", bundle: #bundle), systemImage: "hand.tap")
        }
        LabeledContent {
            Text(totals.averageDailyActiveDevices, format: .number)
        } label: {
            Label(String(localized: "Daily Active Devices", bundle: #bundle), systemImage: "person.2")
        }
    }
}

extension AppDetailView where Reviews == EmptyView {
    public init(app: AppPerformanceSummary, loader: SalesDataLoader) {
        self.init(app: app, loader: loader) { EmptyView() }
    }
}

#Preview {
    let loader = SalesDataLoader(data: .example, lastRefresh: .now)
    NavigationStack {
        AppDetailView(app: ACData.example.getAppSummaries()[0], loader: loader) {
            AppReviewsSection(account: .demoAccount, appleID: ACData.example.getAppSummaries()[0].appleID)
        }
    }
}
#endif
