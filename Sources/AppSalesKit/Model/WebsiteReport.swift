import Foundation

/// One website's last 30 days from Google Analytics: its totals against the 30 days before, its
/// daily views, who visited and from where, and its most viewed pages.
public struct WebsiteReport: Identifiable, Hashable, Sendable {

    public let property: GoogleAnalyticsProperty
    /// The host most of its views landed on, for its icon and to open it; `nil` before any views.
    public let host: String?
    public let totals: Totals
    public let previousTotals: Totals
    /// Oldest first, with days without views left out.
    public let days: [Day]
    /// Active users by ISO country code; `(not set)` for those Google could not place.
    public let countries: [String: Int]
    /// Active users by operating system, as Google names them (`iOS`, `Macintosh`, …).
    public let operatingSystems: [String: Int]
    /// Most sessions first.
    public let sources: [Source]
    /// Most views first.
    public let pages: [Page]

    public var id: String { property.id }
    public var name: String { property.name }
    /// None for the demo's reserved `.example` hosts.
    public var url: URL? {
        guard let host, !host.hasSuffix(".example") else { return nil }
        return URL(string: "https://" + host)
    }

    /// Page views' symbol on every website screen. Not the globe, which elsewhere stands for a
    /// website as a whole.
    public static let viewsSymbol = "eye"

    public struct Totals: Hashable, Sendable {
        public var views = 0
        public var users = 0
        public var sessions = 0
    }

    public struct Day: Hashable, Sendable {
        public let date: Date
        public let views: Int
        public let users: Int
    }

    /// Where a visit came from: `google / organic`, `(direct) / (none)`, `chatgpt.com / referral`.
    public struct Source: Hashable, Sendable {
        public let source: String
        public let medium: String
        public let channel: WebsiteChannel
        public let sessions: Int
    }

    public struct Page: Hashable, Sendable {
        public let title: String
        public let views: Int
    }

    public var viewsChange: Double? {
        previousTotals.views > 0 ? PerformanceSummary.percentageChange(from: Double(previousTotals.views), to: Double(totals.views)) : nil
    }

    public var usersChange: Double? {
        previousTotals.users > 0 ? PerformanceSummary.percentageChange(from: Double(previousTotals.users), to: Double(totals.users)) : nil
    }

    /// Sessions by channel, from `sources`.
    public var channels: [WebsiteChannel: Int] {
        sources.reduce(into: [:]) { $0[$1.channel, default: 0] += $1.sessions }
    }
}

/// How a visit reached a website: one of Google Analytics' default channel groups — Direct,
/// Organic Search, AI Assistant, Referral, and so on — named as Google names it, so the figures
/// match its own reports.
public struct WebsiteChannel: Hashable, Sendable {
    public let name: String

    /// - Parameter defaultChannelGroup: The `sessionDefaultChannelGroup` Google reported; empty or
    ///   `(not set)` is Unassigned, as Google shows it.
    public init(defaultChannelGroup group: String) {
        self.name = group.isEmpty || group == "(not set)" ? "Unassigned" : group
    }

    public static let unassigned = WebsiteChannel(defaultChannelGroup: "Unassigned")
}

// MARK: Reading

extension GoogleAnalytics {

    /// Every chosen website's report, in the order they were chosen. A website that cannot be read
    /// is left out, unless none can.
    public func websiteReports() async throws -> [WebsiteReport] {
        let websites = connectedWebsites
        guard !websites.isEmpty else { throw GoogleSignInError.notConnected(service: "Google Analytics") }

        var reports: [String: WebsiteReport] = [:]
        var failure: Error?
        await withTaskGroup(of: Result<WebsiteReport, Error>.self) { group in
            for (account, property) in websites {
                group.addTask {
                    do { return .success(try await self.report(of: property, as: account)) } catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let report): reports[report.id] = report
                case .failure(let error): failure = error
                }
            }
        }
        if reports.isEmpty, let failure { throw failure }
        return websites.compactMap { reports[$0.property.id] }
    }

    private func report(of property: GoogleAnalyticsProperty, as account: GoogleAccount) async throws -> WebsiteReport {
        let current: [String: Any] = ["startDate": "30daysAgo", "endDate": "today", "name": "current"]
        let previous: [String: Any] = ["startDate": "61daysAgo", "endDate": "31daysAgo", "name": "previous"]
        func request(_ dimensions: [String], _ metrics: [String], ranges: [[String: Any]] = [current], limit: Int = 250) -> [String: Any] {
            [
                "dateRanges": ranges,
                "dimensions": dimensions.map { ["name": $0] },
                "metrics": metrics.map { ["name": $0] },
                "orderBys": metrics.isEmpty ? [] : [["metric": ["metricName": metrics[0]], "desc": true]],
                "limit": limit,
            ]
        }

        // A batch holds five at most, so two go at once.
        let firstBody = try JSONSerialization.data(withJSONObject: ["requests": [
            request([], ["screenPageViews", "activeUsers", "sessions"], ranges: [current, previous]),
            request(["date"], ["screenPageViews", "activeUsers"], limit: 100),
            request(["countryId"], ["activeUsers"]),
            request(["operatingSystem"], ["activeUsers"]),
            request(["sessionSource", "sessionMedium", "sessionDefaultChannelGroup"], ["sessions"], limit: 1000),
        ]])
        let secondBody = try JSONSerialization.data(withJSONObject: ["requests": [
            request(["pageTitle"], ["screenPageViews"], limit: 100),
            request(["hostName"], ["screenPageViews"], limit: 1),
        ]])
        async let first = batch(firstBody, of: property, as: account)
        async let second = batch(secondBody, of: property, as: account)
        let reports = try await first + second
        guard reports.count == 7 else { throw GoogleSignInError.google("Google Analytics sent an incomplete report.") }

        var totals = WebsiteReport.Totals()
        var previousTotals = WebsiteReport.Totals()
        for row in reports[0].rows {
            let figures = WebsiteReport.Totals(views: row.metric(0), users: row.metric(1), sessions: row.metric(2))
            if row.dimension(0) == "previous" { previousTotals = figures } else { totals = figures }
        }

        let days = reports[1].rows
            .compactMap { row in
                Self.day(row.dimension(0)).map { WebsiteReport.Day(date: $0, views: row.metric(0), users: row.metric(1)) }
            }
            .sorted { $0.date < $1.date }

        func counts(_ report: ReportResponse) -> [String: Int] {
            Dictionary(report.rows.map { ($0.dimension(0), $0.metric(0)) }, uniquingKeysWith: +)
        }

        let sources = reports[4].rows.map { row in
            WebsiteReport.Source(
                source: row.dimension(0),
                medium: row.dimension(1),
                channel: WebsiteChannel(defaultChannelGroup: row.dimension(2)),
                sessions: row.metric(0))
        }
        let pages = reports[5].rows
            .map { WebsiteReport.Page(title: $0.dimension(0), views: $0.metric(0)) }
            .filter { !$0.title.isEmpty && $0.title != "(not set)" }

        return WebsiteReport(
            property: property,
            host: reports[6].rows.first.map { $0.dimension(0) }.flatMap { $0.isEmpty || $0 == "(not set)" ? nil : $0 },
            totals: totals,
            previousTotals: previousTotals,
            days: days,
            countries: counts(reports[2]),
            operatingSystems: counts(reports[3]),
            sources: sources.sorted { $0.sessions > $1.sessions },
            pages: pages)
    }

    /// A `date` dimension's `YYYYMMDD`, as the start of that day here.
    private static func day(_ value: String) -> Date? {
        guard value.count == 8, let number = Int(value) else { return nil }
        return Calendar.autoupdatingCurrent.date(from: DateComponents(year: number / 10_000, month: number / 100 % 100, day: number % 100))
    }

    private struct BatchResponse: Decodable {
        let reports: [ReportResponse]?
    }

    fileprivate struct ReportResponse: Decodable {
        struct Row: Decodable {
            struct Value: Decodable { let value: String? }
            let dimensionValues: [Value]?
            let metricValues: [Value]?

            func dimension(_ index: Int) -> String {
                guard let values = dimensionValues, values.indices.contains(index) else { return "" }
                return values[index].value ?? ""
            }

            func metric(_ index: Int) -> Int {
                guard let values = metricValues, values.indices.contains(index) else { return 0 }
                return Int(values[index].value ?? "") ?? 0
            }
        }

        private let rows_: [Row]?
        var rows: [Row] { rows_ ?? [] }

        enum CodingKeys: String, CodingKey {
            case rows_ = "rows"
        }
    }

    /// - Parameter body: A `batchRunReports` request: up to five reports.
    private func batch(_ body: Data, of property: GoogleAnalyticsProperty, as account: GoogleAccount) async throws -> [ReportResponse] {
        var request = URLRequest(url: URL(string: "https://analyticsdata.googleapis.com/v1beta/\(property.id):batchRunReports") ?? URL(filePath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let response: BatchResponse = try await send(request, as: account)
        return response.reports ?? []
    }
}
