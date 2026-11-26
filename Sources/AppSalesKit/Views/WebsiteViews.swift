#if !os(watchOS)
import SwiftUI
import Charts

// MARK: Setting

/// Shows the websites in the sidebar, each with its own page beneath a summary of them all. Offer
/// it only while `SalesDataLoader.websites` has some.
public struct ShowWebsitesToggle: View {

    public init() {}

    @AppStorage(UserDefaults.Key.showsWebsites, store: UserDefaults.shared) private var showsWebsites = false

    public var body: some View {
        Toggle(isOn: $showsWebsites) {
            Label(String(localized: "Show Websites", bundle: #bundle), systemImage: "globe")
        }
    }
}

// MARK: Sidebar

/// A website's favicon, or a globe until it has one.
public struct WebsiteIcon: View {

    let host: String?
    let length: CGFloat

    public init(host: String?, length: CGFloat) {
        self.host = host
        self.length = length
    }

    /// None for the demo's reserved `.example` hosts, which have no icon to find.
    private var faviconURL: URL? {
        guard let host, !host.hasSuffix(".example") else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }

    public var body: some View {
        AsyncImage(url: faviconURL) { image in
            image
                .resizable()
                .scaledToFit()
                .padding(length * 0.14)
        } placeholder: {
            Image(systemName: "globe")
                .resizable()
                .scaledToFit()
                .fontWeight(.medium)
                .foregroundStyle(.teal)
                .padding(length * 0.2)
        }
        .frame(width: length, height: length)
        .background(.background.secondary, in: .rect(cornerRadius: length * 0.225))
        .overlay {
            RoundedRectangle(cornerRadius: length * 0.225)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// One website in the sidebar: its icon and name over its last 30 days' views and their change.
public struct WebsiteRow: View {

    let website: GoogleAnalyticsProperty
    let report: WebsiteReport?
    let iconLength: CGFloat

    public init(website: GoogleAnalyticsProperty, report: WebsiteReport?, iconLength: CGFloat) {
        self.website = website
        self.report = report
        self.iconLength = iconLength
    }

    public var body: some View {
        HStack {
            WebsiteIcon(host: report?.host, length: iconLength)

            VStack(alignment: .leading, spacing: 2) {
                Text(website.name)
                    .lineLimit(1)

                if let report {
                    HStack(spacing: 8) {
                        Label(report.totals.views.formatted(), systemImage: WebsiteReport.viewsSymbol)
                            .labelStyle(TightLabelStyle())
                            .accessibilityLabel(Text("\(report.totals.views) views in the last 30 days", bundle: #bundle))
                        Label(report.totals.users.formatted(), systemImage: "person.2")
                            .labelStyle(TightLabelStyle())
                            .accessibilityLabel(Text("\(report.totals.users) users in the last 30 days", bundle: #bundle))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }
}

// MARK: Summary

/// The websites' lead section: their total views and users over a chart comparing each one's views,
/// the way the app summary leads with downloads and proceeds.
public struct WebsiteSummarySection: View {

    let reports: [WebsiteReport]

    public init(reports: [WebsiteReport]) {
        self.reports = reports
    }

    @State private var isWide = false

    private var sorted: [WebsiteReport] {
        reports.sorted { $0.totals.views > $1.totals.views }
    }

    private func change(_ previous: Int, _ current: Int) -> Double? {
        previous > 0 ? PerformanceSummary.percentageChange(from: Double(previous), to: Double(current)) : nil
    }

    public var body: some View {
        let views = reports.reduce(0) { $0 + $1.totals.views }
        let previousViews = reports.reduce(0) { $0 + $1.previousTotals.views }
        let users = reports.reduce(0) { $0 + $1.totals.users }
        let previousUsers = reports.reduce(0) { $0 + $1.previousTotals.users }
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: isWide ? 32 : 16) {
                    SummaryStat(
                        name: "Views",
                        value: views.formatted(),
                        systemImage: WebsiteReport.viewsSymbol,
                        color: .teal,
                        isLarge: isWide,
                        change: change(previousViews, views))
                    SummaryStat(
                        name: "Users",
                        value: users.formatted(),
                        systemImage: "person.2",
                        color: .indigo,
                        isLarge: isWide,
                        change: change(previousUsers, users))
                    Spacer(minLength: 0)
                }

                WebsiteViewsChart(reports: sorted)
            }
            .padding(.vertical)
            .onGeometryChange(for: Bool.self) { $0.size.width >= 600 } action: { isWide = $0 }
        } footer: {
            if reports.count > 1 {
                Text("Last 30 days. Users are counted once per website.", bundle: #bundle)
            } else {
                Text("Last 30 days.", bundle: #bundle)
            }
        }
    }
}

/// Each website's views and users as a pair of bars, its name above and an arrow past each bar's
/// end for its change on the 30 days before, as on the app summary's chart. The colours are the
/// figures' above it, which stand in for the legend.
private struct WebsiteViewsChart: View {

    let reports: [WebsiteReport]

    var body: some View {
        let views = String(localized: "Views", bundle: #bundle)
        let users = String(localized: "Users", bundle: #bundle)
        Chart(reports) { report in
            bar(for: report, series: views, value: report.totals.views, change: report.viewsChange)
                .annotation(position: .top, alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        WebsiteIcon(host: report.host, length: 16)
                        Text(report.name)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            bar(for: report, series: users, value: report.totals.users, change: report.usersChange)
        }
        .chartForegroundStyleScale([views: Color.teal, users: Color.indigo])
        .chartLegend(.hidden)
        .chartYScale(domain: reports.map(\.id))
        .chartYAxis(.hidden)
        .frame(height: CGFloat(reports.count) * 76 + 32)
    }

    private func bar(for report: WebsiteReport, series: String, value: Int, change: Double?) -> some ChartContent {
        BarMark(x: .value(series, value), y: .value(String(localized: "Website", bundle: #bundle), report.id), height: .fixed(16))
            .foregroundStyle(by: .value(String(localized: "Data Type", bundle: #bundle), series))
            .position(by: .value(String(localized: "Data Type", bundle: #bundle), series))
            .cornerRadius(4)
            .accessibilityLabel(Text("\(report.name), \(series)", bundle: #bundle))
            .accessibilityValue(Text(value, format: .number))
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

/// Users by country and operating system, and sessions by channel: every website's on the
/// summary, one website's on its page.
public struct WebsitePiesSection: View {

    let reports: [WebsiteReport]

    public init(reports: [WebsiteReport]) {
        self.reports = reports
    }

    public var body: some View {
        SharePieRow(cards: [
            SharePieCard(title: String(localized: "Users by Country", bundle: #bundle), shares: reports.usersByCountry(), value: .count),
            SharePieCard(title: String(localized: "Users by OS", bundle: #bundle), shares: reports.usersByOS(), value: .count),
            SharePieCard(title: String(localized: "Sessions by Channel", bundle: #bundle), shares: reports.sessionsByChannel(), value: .count),
        ].filter { $0.shares.count > 1 })
    }
}

// MARK: Detail

/// Everything about one website: its last 30 days by day, who visited, where they came from, and
/// which pages they read.
public struct WebsiteDetailView: View {

    let website: GoogleAnalyticsProperty
    let loader: SalesDataLoader

    public init(website: GoogleAnalyticsProperty, loader: SalesDataLoader) {
        self.website = website
        self.loader = loader
    }

    @State private var showsAllSources = false
    @State private var showsAllPages = false
    @Environment(\.openURL) private var openURL

    private static let shortListLength = 10

    public var body: some View {
        Group {
            if let report = loader.websiteReport(id: website.id) {
                content(report)
            } else if let error = loader.websiteReportsError {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
            } else if loader.isLoadingWebsiteReports {
                ProgressView()
            } else {
                Text("This website could not be read.", bundle: #bundle)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(website.name)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func content(_ report: WebsiteReport) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    WebsiteIcon(host: report.host, length: 64)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.name)
                            .font(.title2.bold())
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if let host = report.host {
                            Text(host)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section {
                dailyChart(report)
                    .frame(height: 180)
                    .padding(.vertical, 4)

                figure(String(localized: "Views", bundle: #bundle), systemImage: WebsiteReport.viewsSymbol, value: report.totals.views, change: report.viewsChange)
                figure(String(localized: "Users", bundle: #bundle), systemImage: "person.2", value: report.totals.users, change: report.usersChange)
                figure(String(localized: "Sessions", bundle: #bundle), systemImage: "hand.tap", value: report.totals.sessions, change: nil)
            } header: {
                Text("Last 30 Days", bundle: #bundle)
            }

            WebsitePiesSection(reports: [report])

            let sources = report.sourceRows
            if !sources.isEmpty {
                Section {
                    ForEach(showsAllSources ? sources : Array(sources.prefix(Self.shortListLength))) { row in
                        LabeledContent {
                            Text(row.sessions, format: .number)
                                .monospacedDigit()
                        } label: {
                            Label {
                                if let medium = row.medium {
                                    Text("\(row.name) \(Text(medium).foregroundStyle(.secondary))", bundle: #bundle)
                                        .lineLimit(1)
                                } else {
                                    Text(row.name)
                                        .lineLimit(1)
                                }
                            } icon: {
                                Image(systemName: row.channel.symbol)
                                    .foregroundStyle(row.channel.color)
                            }
                        }
                    }
                    showAllButton(isOn: $showsAllSources, count: sources.count)
                } header: {
                    Text("Sources", bundle: #bundle)
                } footer: {
                    Text("Sessions by source and medium.", bundle: #bundle)
                }
            }

            if !report.pages.isEmpty {
                Section {
                    ForEach(Array((showsAllPages ? report.pages : Array(report.pages.prefix(Self.shortListLength))).enumerated()), id: \.element.title) { index, page in
                        LabeledContent {
                            Text(page.views, format: .number)
                                .monospacedDigit()
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(index + 1, format: .number)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 20, alignment: .trailing)
                                Text(page.title)
                                    .lineLimit(2)
                            }
                        }
                    }
                    showAllButton(isOn: $showsAllPages, count: report.pages.count)
                } header: {
                    Text("Pages", bundle: #bundle)
                } footer: {
                    Text("Views by page title.", bundle: #bundle)
                }
            }
        }
        .toolbar {
            if let url = report.url {
                ToolbarItem {
                    Button(String(localized: "Open Website", bundle: #bundle), systemImage: "safari") {
                        openURL(url)
                    }
                    .help(Text("Open Website", bundle: #bundle))
                }
            }
        }
    }

    @ViewBuilder
    private func showAllButton(isOn: Binding<Bool>, count: Int) -> some View {
        if count > Self.shortListLength {
            Button {
                withAnimation { isOn.wrappedValue.toggle() }
            } label: {
                Text(isOn.wrappedValue ? String(localized: "Show Less", bundle: #bundle) : String(localized: "Show All \(count)", bundle: #bundle))
            }
            .buttonStyle(.borderless)
        }
    }

    private func figure(_ title: String, systemImage: String, value: Int, change: Double?) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let change {
                    PercentChange(change: change)
                        .font(.subheadline)
                }
                Text(value, format: .number)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    /// The same 30 days as the figures beneath, with days without views at zero rather than skipped.
    private func dailyChart(_ report: WebsiteReport) -> some View {
        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let byDay = Dictionary(report.days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { $1 })
        let dates = (0...30).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let views = String(localized: "Views", bundle: #bundle)
        let users = String(localized: "Users", bundle: #bundle)
        return Chart {
            ForEach(dates, id: \.self) { date in
                LineMark(x: .value(String(localized: "Day", bundle: #bundle), date, unit: .day), y: .value(views, byDay[date]?.views ?? 0))
                    .foregroundStyle(by: .value(String(localized: "Data Type", bundle: #bundle), views))
                    .interpolationMethod(.monotone)
                LineMark(x: .value(String(localized: "Day", bundle: #bundle), date, unit: .day), y: .value(users, byDay[date]?.users ?? 0))
                    .foregroundStyle(by: .value(String(localized: "Data Type", bundle: #bundle), users))
                    .interpolationMethod(.monotone)
            }
        }
        .chartForegroundStyleScale([views: Color.teal, users: Color.indigo])
        .chartXScale(domain: start...end)
    }
}

/// A row of the Sources list: one source and medium.
private struct SourceRow: Identifiable {
    let name: String
    let medium: String?
    let channel: WebsiteChannel
    let sessions: Int

    var id: String { name + "/" + (medium ?? "") }
}

extension WebsiteReport {
    /// Sessions by source and medium, most first, with Google's placeholders in words.
    fileprivate var sourceRows: [SourceRow] {
        struct Key: Hashable { let name: String; let medium: String? }
        var sessions: [Key: Int] = [:]
        var channels: [Key: WebsiteChannel] = [:]
        for source in sources where source.sessions > 0 {
            let isDirect = source.source == "(direct)"
            let name = isDirect ? String(localized: "Direct", bundle: #bundle) : (source.source == "(not set)" ? String(localized: "Unknown", bundle: #bundle) : source.source)
            let medium = isDirect || ["(none)", "(not set)", ""].contains(source.medium) ? nil : source.medium
            let key = Key(name: name, medium: medium)
            sessions[key, default: 0] += source.sessions
            channels[key] = channels[key] ?? source.channel
        }
        return sessions
            .map { SourceRow(name: $0.key.name, medium: $0.key.medium, channel: channels[$0.key] ?? .unassigned, sessions: $0.value) }
            .sorted { $0.sessions > $1.sessions }
    }
}

// MARK: Shares

extension WebsiteChannel {
    public var symbol: String {
        switch name {
        case "Direct": "link"
        case "Organic Search": "magnifyingglass"
        case "AI Assistant": "sparkles"
        case "Organic Social": "bubble.left.and.bubble.right.fill"
        case "Organic Video": "play.rectangle.fill"
        case "Organic Shopping": "bag.fill"
        case "Referral": "arrowshape.turn.up.right.fill"
        case "Email": "envelope.fill"
        case "Unassigned": "questionmark"
        default: name.hasPrefix("Paid") || ["Display", "Cross-network", "Affiliates"].contains(name) ? "megaphone.fill" : "ellipsis"
        }
    }

    public var color: Color {
        switch name {
        case "Direct": .blue
        case "Organic Search": .green
        case "AI Assistant": .purple
        case "Organic Social": .pink
        case "Organic Video": .red
        case "Organic Shopping": .mint
        case "Referral": .teal
        case "Email": .yellow
        case "Unassigned": .gray
        default: name.hasPrefix("Paid") || ["Display", "Cross-network", "Affiliates"].contains(name) ? .orange : .gray
        }
    }
}

extension [WebsiteReport] {

    private static let countryColors: [Color] = [.blue, .red, .green, .orange, .purple, .teal]

    /// The most users' countries, each in its own colour and flag, then everyone else as Other.
    public func usersByCountry() -> [PieShare] {
        let other = PieShare(name: String(localized: "Other", bundle: #bundle), badge: .emoji("🌐"), color: .gray, value: 0)
        let byCountry = reduce(into: [String: Int]()) { $0.merge($1.countries, uniquingKeysWith: +) }
        let total = byCountry.values.reduce(0, +)
        var shares = byCountry
            .filter { $0.key.count == 2 && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(Self.countryColors.count)
            .enumerated()
            .map { index, country in
                PieShare(
                    name: Locale.autoupdatingCurrent.localizedString(forRegionCode: country.key) ?? country.key,
                    badge: .emoji(Self.flag(country.key)),
                    color: Self.countryColors[index],
                    value: Double(country.value))
            }
        let rest = Double(total) - shares.reduce(0) { $0 + $1.value }
        if rest > 0 {
            shares.append(PieShare(name: other.name, badge: other.badge, color: other.color, value: rest))
        }
        return shares.slices(foldingInto: other)
    }

    private static func flag(_ countryCode: String) -> String {
        String(String.UnicodeScalarView(countryCode.uppercased().unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }

    public func usersByOS() -> [PieShare] {
        let byOS = reduce(into: [String: Int]()) { $0.merge($1.operatingSystems, uniquingKeysWith: +) }
        let other = PieShare(name: String(localized: "Other", bundle: #bundle), badge: .symbol("questionmark"), color: .gray, value: 0)
        let byName = Dictionary(byOS.map { (Self.os(named: $0.key)?.name ?? other.name, $0.value) }, uniquingKeysWith: +)
        let shares = byName
            .filter { $0.value > 0 }
            .map { name, users in
                let share = Self.knownOperatingSystems.first { $0.name == name } ?? other
                return PieShare(name: share.name, badge: share.badge, color: share.color, value: Double(users))
            }
        return shares.slices(foldingInto: other)
    }

    /// Google's operating system names as Apple writes them, with a symbol each; `nil` for the rest.
    private static func os(named name: String) -> PieShare? {
        let index: Int? = switch name {
        case "iOS", "iPadOS": 0
        case "Macintosh", "macOS", "Mac OS X": 1
        case "Windows": 2
        case "Android": 3
        case "Linux": 4
        case "Chrome OS", "ChromeOS": 5
        default: nil
        }
        return index.map { knownOperatingSystems[$0] }
    }

    private static let knownOperatingSystems = [
        PieShare(name: "iOS", badge: .symbol("iphone"), color: .blue, value: 0),
        PieShare(name: "macOS", badge: .symbol("laptopcomputer"), color: .teal, value: 0),
        PieShare(name: "Windows", badge: .symbol("pc"), color: .indigo, value: 0),
        PieShare(name: "Android", badge: .symbol("candybarphone"), color: .green, value: 0),
        PieShare(name: "Linux", badge: .symbol("terminal.fill"), color: .orange, value: 0),
        PieShare(name: "ChromeOS", badge: .symbol("globe"), color: .yellow, value: 0),
    ]

    public func sessionsByChannel() -> [PieShare] {
        let byChannel = reduce(into: [WebsiteChannel: Int]()) { $0.merge($1.channels, uniquingKeysWith: +) }
        return byChannel
            .filter { $0.value > 0 }
            .map { PieShare(name: $0.key.name, badge: .symbol($0.key.symbol), color: $0.key.color, value: Double($0.value)) }
            .slices(foldingInto: PieShare(name: String(localized: "Other", bundle: #bundle), badge: .symbol("ellipsis"), color: .gray, value: 0))
    }
}

/// An icon hard against its figure.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon
            configuration.title
        }
    }
}
#endif
