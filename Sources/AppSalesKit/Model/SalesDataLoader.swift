import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif
import SwiftUI

/// One account's sales data, the App Store analytics and webpage views that go with it, and the
/// fetches that produce them.
///
/// Every platform's home screen wants the same three states — loading, loaded, failed — and the
/// same refresh behaviour, so they share one loader rather than each keeping its own pair of
/// `@State`s and its own copy of the error handling. Every summary section, the app list, and the
/// app detail view read from it; `.loadsSales(_:account:)` keeps it fetching.
@MainActor
@Observable
public final class SalesDataLoader {

    public private(set) var data: ACData?
    /// Kept alongside the data rather than computed on demand: rolling 60 days of events up is real
    /// work, and a view body reads it more than once per pass.
    public private(set) var summary: PerformanceSummary?
    public private(set) var error: APIError?
    /// When the figures on screen were last read from App Store Connect, for the "Updated" line
    /// under them. Nothing persists it: a launch fetches before it draws anything anyway.
    public private(set) var lastRefresh: Date?
    /// The account last loaded, whose analytics and reviews go with the data.
    public private(set) var account: Account?

    public private(set) var appStoreAnalytics: AnalyticsAvailability?
    public private(set) var isLoadingAppStoreAnalytics = false
    /// What `appStoreAnalytics` was last loaded for, and when, since the reports only change daily.
    private var appStoreAnalyticsLoad: (query: AppStoreAnalyticsQuery, date: Date)?
    /// Keyed by Apple ID; empty while Google Analytics is not connected.
    public private(set) var websiteTraffic: [String: WebPageTraffic] = [:]
    /// Counts refreshes the reader asked for, so anything beside the sales (AI usage, say) can
    /// refresh along with them.
    public private(set) var refreshCount = 0

    public init(data: ACData? = nil, lastRefresh: Date? = nil) {
        self.data = data
        self.summary = data?.getPerformanceSummary()
        self.lastRefresh = lastRefresh
    }

    /// The reader's own currency, which is what the home screens display in.
    private var displayCurrency: Currency? {
        Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? "")
    }

    /// Whether Google Analytics has a website chosen, so a webpage can be set before it has any views.
    public var showsWebsite: Bool {
        !GoogleAnalytics.shared.websites.isEmpty
    }

    /// - Parameter useMemoization: `false` for a refresh the reader asked for, which should go past
    ///   the five-minute in-memory cache; `true` for a view simply appearing.
    public func load(account: Account?, useMemoization: Bool = true) async {
        guard let account else { return }

        if account != self.account {
            self.account = account
        }
        let api = AppStoreConnectAPI(apiKey: account)
        do {
            let data = try await api.getData(currency: displayCurrency, useMemoization: useMemoization)
            self.data = data
            self.summary = data.getPerformanceSummary()
            lastRefresh = .now
            error = nil
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch is CancellationError {
        } catch let err as URLError where err.code == .cancelled {
        } catch let err {
            data = nil
            summary = nil
            error = APIError(err)
        }
    }

    /// A refresh the reader asked for: past the in-memory cache, and counted in `refreshCount`.
    public func refresh() async {
        refreshCount += 1
        await load(account: account, useMemoization: false)
    }

    // MARK: App Store Analytics

    /// What the App Store analytics depend on, so they reload when the account or its apps change.
    struct AppStoreAnalyticsQuery: Equatable {
        let accountID: String?
        let appIDs: [String]
    }

    var appStoreAnalyticsQuery: AppStoreAnalyticsQuery {
        AppStoreAnalyticsQuery(accountID: account?.id, appIDs: data?.apps.map(\.appleID) ?? [])
    }

    public func loadAppStoreAnalytics() async {
        guard let data else { return }
        let query = appStoreAnalyticsQuery
        // Coming back from an app's screen reappears the list; the reports only change daily.
        if let appStoreAnalyticsLoad, appStoreAnalyticsLoad.query == query, appStoreAnalyticsLoad.date.timeIntervalSinceNow > -5 * 60 { return }
        guard let account else { return }

        if appStoreAnalyticsLoad?.query.accountID != query.accountID {
            appStoreAnalytics = nil
        }
        isLoadingAppStoreAnalytics = true
        defer { isLoadingAppStoreAnalytics = false }
        // A failed fetch keeps the last figures rather than blanking every row.
        if let availability = try? await AnalyticsReportsAPI(account: account).getAnalytics(appleIDs: query.appIDs, sales: data) {
            appStoreAnalytics = availability
            appStoreAnalyticsLoad = (query, .now)
        }
    }

    // MARK: Website Traffic

    /// What the website traffic depends on, so it reloads when a website, a page, or the apps change.
    struct WebsiteTrafficQuery: Equatable {
        let websites: [GoogleAnalyticsProperty]
        let pageURLs: [String: URL]
        let appIDs: [String]
    }

    var websiteTrafficQuery: WebsiteTrafficQuery {
        let googleAnalytics = GoogleAnalytics.shared
        return WebsiteTrafficQuery(websites: googleAnalytics.websites, pageURLs: googleAnalytics.pageURLs, appIDs: summary?.apps.map(\.appleID) ?? [])
    }

    public func loadWebsiteTraffic() async {
        let googleAnalytics = GoogleAnalytics.shared
        guard GoogleSignIn.isAvailable, !googleAnalytics.websites.isEmpty, let apps = summary?.apps else {
            websiteTraffic = [:]
            return
        }

        // A failed fetch keeps the last figures rather than blanking every row.
        if let traffic = try? await googleAnalytics.traffic(for: apps.map { ($0.appleID, $0.name) }) {
            websiteTraffic = traffic
        }
    }

    // MARK: Figures

    /// The figures of each `sortsByCounts` sort, keyed by Apple ID. A sort is missing until it
    /// has figures, which leaves its column out of the app rows and out of `AppListOptions` (unless
    /// it is the chosen one, so the menu still shows what the list is sorted by).
    public var appCounts: [AppListSort: [String: Int]] {
        guard let apps = summary?.apps else { return [:] }

        var counts: [AppListSort: [String: Int]] = [.websiteViews: websiteTraffic.mapValues(\.views)]
        if case .ready(let analytics) = appStoreAnalytics {
            let totals = Dictionary(uniqueKeysWithValues: apps.map { ($0.appleID, analytics.totals(for: $0.appleID)) })
            counts[.impressions] = totals.mapValues(\.impressions)
            counts[.appStoreViews] = totals.mapValues(\.pageViews)
            counts[.activeDevices] = totals.mapValues(\.averageDailyActiveDevices)
        }
        return counts.filter { !$0.value.isEmpty }
    }

    /// From the webpage to active devices, leaving out whatever is not connected, each with its change
    /// on the 30 days before. Downloads are counted over the analytics reports' days when there are
    /// any, so each step compares like with like. Nil without a stage ahead of downloads, as there is
    /// no funnel.
    public var funnel: [FunnelStage]? {
        guard let data, let summary else { return nil }

        func change(_ previous: Int?, _ current: Int) -> Double? {
            previous.map { PerformanceSummary.percentageChange(from: Double($0), to: Double(current)) }
        }

        var stages: [FunnelStage] = []
        if showsWebsite, !websiteTraffic.isEmpty {
            let views = websiteTraffic.values.reduce(0) { $0 + $1.views }
            let previousViews = websiteTraffic.values.reduce(0) { $0 + $1.previousViews }
            stages.append(FunnelStage(stat: .websiteViews, color: .teal, count: views, change: change(previousViews, views)))
        }

        var downloads = FunnelStage(stat: .downloads, color: .blue, count: summary.downloads, change: summary.downloadsPercentageChange)
        var activeDevices: FunnelStage?
        if case .ready(let analytics) = appStoreAnalytics, !analytics.isEmpty {
            let totals = analytics.totals()
            let previous = analytics.previousTotals()
            let count = Int(data.getTotal(for: .downloads, in: analytics.range))
            downloads = FunnelStage(stat: .downloads, color: .blue, count: count,
                                    change: change(Int(data.getTotal(for: .downloads, in: analytics.previousRange)), count))
            activeDevices = FunnelStage(stat: .activeDevices, color: .orange, count: totals.averageDailyActiveDevices,
                                        change: change(previous?.averageDailyActiveDevices, totals.averageDailyActiveDevices))
            stages.append(FunnelStage(stat: .appStoreViews, color: .indigo, count: totals.pageViews,
                                      change: change(previous?.pageViews, totals.pageViews)))
        }
        guard !stages.isEmpty else { return nil }

        stages.append(downloads)
        if let activeDevices {
            stages.append(activeDevices)
        }
        return stages
    }
}

extension View {

    /// Keeps `loader` fetching `account`'s sales — on appear, when the account changes, and back in
    /// the foreground — then its App Store analytics and webpage views once the sales are in. Put it
    /// once on whatever holds the sections reading from `loader`.
    public func loadsSales(_ loader: SalesDataLoader, account: Account?) -> some View {
        self
            .task(id: account) {
                await loader.load(account: account, useMemoization: true)
            }
            .task(id: loader.appStoreAnalyticsQuery) {
                await loader.loadAppStoreAnalytics()
            }
            .task(id: loader.websiteTrafficQuery) {
                await loader.loadWebsiteTraffic()
            }
            #if canImport(UIKit) && !os(watchOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await loader.load(account: account) }
            }
            #endif
    }
}
