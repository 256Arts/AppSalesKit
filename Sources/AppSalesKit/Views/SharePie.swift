#if !os(watchOS)
import SwiftUI
import Charts

/// One slice of a pie: a device, a region, or a source of income, and how much came from it.
public struct PieShare: Identifiable {
    public let name: String
    public let badge: Badge
    public let color: Color
    public let value: Double

    public var id: String { name }

    /// What stands for the share on its slice: an SF Symbol, or an emoji such as a flag.
    public enum Badge {
        case symbol(String)
        case emoji(String)
    }
}

/// A share's symbol or emoji, at the current font size.
public struct PieShareBadge: View {

    public let badge: PieShare.Badge

    public var body: some View {
        switch badge {
        case .symbol(let name):
            Image(systemName: name)
        case .emoji(let emoji):
            Text(verbatim: emoji)
        }
    }
}

/// Shares as a donut, each slice in its share's colour and marked with its badge, unless it is
/// too thin to hold one.
public struct SharePie: View {

    public let shares: [PieShare]
    public var showsBadges = true

    private static let innerRadius = 0.55

    private var total: Double {
        shares.reduce(0) { $0 + $1.value }
    }

    public var body: some View {
        Chart(shares) { share in
            SectorMark(angle: .value(String(localized: "Share", bundle: #bundle), share.value), innerRadius: .ratio(Self.innerRadius), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value(String(localized: "Name", bundle: #bundle), share.name))
                .accessibilityLabel(share.name)
                .accessibilityValue(Text(share.value / max(total, .leastNonzeroMagnitude), format: .percent.precision(.fractionLength(0))))
        }
        .chartForegroundStyleScale(domain: shares.map(\.name), range: shares.map(\.color))
        .chartLegend(.hidden)
        // Placed by hand: an overlay annotation sits out by the ring's outer edge, not across its middle.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if showsBadges, let plotFrame = proxy.plotFrame {
                    let frame = geometry[plotFrame]
                    let radius = min(frame.width, frame.height) / 2 * (1 + Self.innerRadius) / 2
                    ForEach(badges, id: \.share.id) { badge in
                        PieShareBadge(badge: badge.share.badge)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .position(
                                x: frame.midX + radius * sin(badge.angle),
                                y: frame.midY - radius * cos(badge.angle))
                    }
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// The slices wide enough to hold a badge, each with the angle through its middle, clockwise
    /// from the top, where the chart starts.
    private var badges: [(share: PieShare, angle: Double)] {
        var start = 0.0
        return shares.compactMap { share in
            let fraction = share.value / max(total, .leastNonzeroMagnitude)
            defer { start += fraction }
            return fraction >= 0.05 ? (share, (start + fraction / 2) * 2 * .pi) : nil
        }
    }
}

/// The last 30 days' income by source, downloads by device, downloads by region, and active
/// devices by OS version (over the analytics reports' 30 days), as cards in one horizontally scrolling row: every app's on the Summary, one app's on its detail page.
/// A pie with nothing to divide is left out, and one with a single slice too, as a full circle says
/// nothing.
public struct SharePiesSection: View {

    public let data: ACData
    public var filteredApps: [ACApp] = []
    public var analytics: AnalyticsAvailability?
    /// Holds the OS pie's place while the analytics reports load.
    public var isLoadingAnalytics = false

    /// - Parameter filteredApps: The apps to count, or every app when empty.
    public init(data: ACData, filteredApps: [ACApp] = [], analytics: AnalyticsAvailability? = nil, isLoadingAnalytics: Bool = false) {
        self.data = data
        self.filteredApps = filteredApps
        self.analytics = analytics
        self.isLoadingAnalytics = isLoadingAnalytics
    }

    private var cards: [SharePieCard] {
        var cards = [
            SharePieCard(title: String(localized: "Income by Source", bundle: #bundle), shares: data.incomeBySource(filteredApps: filteredApps), value: .currency),
            SharePieCard(title: String(localized: "Downloads by Device", bundle: #bundle), shares: data.downloadsByDevice(filteredApps: filteredApps), value: .count),
            SharePieCard(title: String(localized: "Downloads by Region", bundle: #bundle), shares: data.downloadsByRegion(filteredApps: filteredApps), value: .count)
        ]
        if case .ready(let analytics) = analytics {
            cards.append(SharePieCard(title: String(localized: "Daily Active Devices by OS", bundle: #bundle), shares: analytics.activeDevicesByOS(filteredApps: filteredApps), value: .count))
        } else if isLoadingAnalytics {
            cards.append(.placeholder(title: String(localized: "Daily Active Devices by OS", bundle: #bundle)))
        }
        return cards
        .filter { $0.shares.count > 1 }
    }

    public var body: some View {
        let cards = cards
        if !cards.isEmpty {
            Section {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(cards.enumerated()), id: \.element.title) { index, card in
                            if index > 0 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                            card
                                .containerRelativeFrame(.horizontal) { length, _ in
                                    cardWidth(in: length, count: cards.count)
                                }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.vertical, 16, for: .scrollContent)
                #if os(macOS)
                .background(PassVerticalScrollToParent())
                #endif
                .listRowInsets(EdgeInsets())
            }
        }
    }
}

#if os(macOS)
import AppKit

/// A horizontal `ScrollView` on the Mac swallows vertical wheel and trackpad events over it, so the
/// page stops scrolling while the pointer is on the row. Hands mostly-vertical events to the
/// enclosing scroll view instead.
private struct PassVerticalScrollToParent: NSViewRepresentable {
    final class Coordinator {
        var monitor: Any?
        deinit { monitor.map(NSEvent.removeMonitor) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak view] event in
            guard let view,
                  event.window === view.window,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil)),
                  let parent = view.enclosingScrollView
            else { return event }
            parent.scrollWheel(with: event)
            return nil
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

extension SharePiesSection {
    /// Each card's share of the row's width, up to `maxCardWidth`, where they all fit at
    /// `minCardWidth` or wider, else as many as fit at `minCardWidth` or a little wider, with
    /// `peek` of the next to show the row scrolls. `length` is already inside the content margins.
    private func cardWidth(in length: CGFloat, count: Int) -> CGFloat {
        let dividers = CGFloat(count - 1) * Self.dividerWidth
        let fitted = ((length - dividers) / CGFloat(count)).rounded(.down)
        if fitted >= Self.minCardWidth { return min(fitted, Self.maxCardWidth) }
        let shown = ((length - Self.peek * Self.minCardWidth) / (Self.minCardWidth + Self.dividerWidth)).rounded(.down)
        guard shown >= 1 else { return length * 0.72 }
        return ((length - shown * Self.dividerWidth) / (shown + Self.peek)).rounded(.down)
    }

    private static let minCardWidth: CGFloat = 160
    /// Past this, a legend's names and figures drift too far apart to read as pairs.
    private static let maxCardWidth: CGFloat = 220
    /// How much of the next card shows, as a fraction of a card.
    private static let peek: CGFloat = 0.4
    /// A divider's line and the padding either side of it.
    private static let dividerWidth: CGFloat = 33
}

/// A pie with a title above and a legend beneath giving each share's figure, since a badge does
/// not name its share on its own and a slice alone does not say how much.
public struct SharePieCard: View {

    public let title: String
    public let shares: [PieShare]
    public let value: Value
    public var isPlaceholder = false

    public enum Value {
        case currency
        case count
    }

    public init(title: String, shares: [PieShare], value: Value) {
        self.title = title
        self.shares = shares
        self.value = value
    }

    /// Grey slices and a redacted legend, standing in for a pie whose figures are on their way.
    public static func placeholder(title: String) -> SharePieCard {
        var card = SharePieCard(title: title, shares: [0.5, 0.3, 0.2].enumerated().map { index, value in
            PieShare(name: "Placeholder \(index)", badge: .symbol("circle.fill"), color: .gray.opacity(0.4 - Double(index) * 0.1), value: value * 1000)
        }, value: .count)
        card.isPlaceholder = true
        return card
    }

    /// Whole units: cents only crowd the names out of a legend.
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private func figure(_ share: PieShare) -> String {
        switch value {
        case .currency: Self.currencyFormatter.string(from: NSNumber(value: share.value)) ?? ""
        case .count: Int(share.value).formatted()
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            SharePie(shares: shares, showsBadges: !isPlaceholder)
                .accessibilityLabel(isPlaceholder ? Text("Loading", bundle: #bundle) : Text(title))
                .frame(height: 140)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(shares) { share in
                    HStack(spacing: 6) {
                        PieShareBadge(badge: share.badge)
                            .foregroundStyle(share.color)
                            .frame(width: 20)
                        Text(share.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Text(figure(share))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .accessibilityElement(children: .combine)
                }
            }
            .redacted(reason: isPlaceholder ? .placeholder : [])
            .accessibilityHidden(isPlaceholder)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Where proceeds come from.
public enum IncomeSource: CaseIterable {
    case paidApps
    case subscriptions
    case inAppPurchases
    case ads

    public init?(_ type: EventType) {
        switch type {
        case .download, .redownload: self = .paidApps
        case .subscription: self = .subscriptions
        case .iap, .restoredIap: self = .inAppPurchases
        case .ad: self = .ads
        case .update, .unknown: return nil
        }
    }

    public var share: (Double) -> PieShare {
        { PieShare(name: name, badge: .symbol(symbol), color: color, value: $0) }
    }

    public var name: String {
        switch self {
        case .paidApps: String(localized: "Paid Apps", bundle: #bundle)
        case .subscriptions: String(localized: "Subscriptions", bundle: #bundle)
        case .inAppPurchases: String(localized: "In-App Purchases", bundle: #bundle)
        case .ads: String(localized: "Ads", bundle: #bundle)
        }
    }

    public var symbol: String {
        switch self {
        case .paidApps: "square.and.arrow.down"
        case .subscriptions: "repeat"
        case .inAppPurchases: "cart.fill"
        case .ads: "megaphone.fill"
        }
    }

    public var color: Color {
        switch self {
        case .paidApps: .blue
        case .subscriptions: .purple
        case .inAppPurchases: .orange
        case .ads: .green
        }
    }
}

/// The App Store's own regions, the ones App Store Connect groups its storefronts under.
public enum SalesRegion: CaseIterable {
    case unitedStatesAndCanada
    case europe
    case asiaPacific
    case latinAmerica
    case africaMiddleEastAndIndia
    case unknown

    /// Sorts an ISO country code by the UN region Foundation knows it to sit in.
    public init(countryCode: String) {
        // Reports have used UK for the United Kingdom, which is not its ISO code.
        let region = Locale.Region(countryCode == "UK" ? "GB" : countryCode)
        let subregion = region.containingRegion?.identifier
        switch region.continent?.identifier {
        case "019" where subregion == "021":
            self = .unitedStatesAndCanada
        case "019":
            self = .latinAmerica
        case "150":
            self = .europe
        case "002":
            self = .africaMiddleEastAndIndia
        case "142" where subregion == "145" || region.identifier == "IN":
            self = .africaMiddleEastAndIndia
        case "142", "009":
            self = .asiaPacific
        default:
            self = .unknown
        }
    }

    public var name: String {
        switch self {
        case .unitedStatesAndCanada: String(localized: "U.S. and Canada", bundle: #bundle)
        case .europe: String(localized: "Europe", bundle: #bundle)
        case .asiaPacific: String(localized: "Asia Pacific", bundle: #bundle)
        case .latinAmerica: String(localized: "Latin America", bundle: #bundle)
        case .africaMiddleEastAndIndia: String(localized: "Africa, Middle East, and India", bundle: #bundle)
        case .unknown: String(localized: "Other", bundle: #bundle)
        }
    }

    /// A flag to stand for the region: one of its biggest markets', or Europe's own.
    public var flag: String {
        switch self {
        case .unitedStatesAndCanada: "🇺🇸"
        case .europe: "🇪🇺"
        case .asiaPacific: "🇯🇵"
        case .latinAmerica: "🇧🇷"
        case .africaMiddleEastAndIndia: "🇮🇳"
        case .unknown: "🌐"
        }
    }

    /// The main colour of the region's flag. The U.S. and Japan both fly red, so Japan takes the
    /// pinker crimson its flag actually is.
    public var color: Color {
        switch self {
        case .unitedStatesAndCanada: .red
        case .europe: .blue
        case .asiaPacific: .pink
        case .latinAmerica: .green
        case .africaMiddleEastAndIndia: .orange
        case .unknown: .gray
        }
    }
}

extension SalesRegion {
    public func share(downloads: Int = 0) -> PieShare {
        PieShare(name: name, badge: .emoji(flag), color: color, value: Double(downloads))
    }
}

extension ACDevice {
    public func share(downloads: Int = 0) -> PieShare {
        PieShare(name: name, badge: .symbol(symbol), color: color, value: Double(downloads))
    }

    public var color: Color {
        switch self {
        case .iPhone: .blue
        case .iPad: .purple
        case .desktop: .teal
        case .appleWatch: .pink
        case .appleTV: .indigo
        case .appleVision: .orange
        case .iPod: .mint
        case .unknown: .gray
        }
    }
}

extension ACData {
    /// Last 30 days' downloads by device, most first and "Unknown" (or "Other") last, with the report's device names folded into
    /// the ones App Sales knows. Every app's when `filteredApps` is empty.
    public func downloadsByDevice(filteredApps: [ACApp] = []) -> [PieShare] {
        let byDevice = Dictionary(getDevices(.downloads, lastNDays: 30, filteredApps: filteredApps).map { (ACDevice($0.0), Int($0.1)) }, uniquingKeysWith: +)
        return byDevice
            .filter { $0.value > 0 }
            .map { $0.key.share(downloads: $0.value) }
            .slices(foldingInto: ACDevice.unknown.share())
    }

    /// Last 30 days' downloads by App Store region, most first and "Other" last.
    public func downloadsByRegion(filteredApps: [ACApp] = []) -> [PieShare] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now
        let byRegion = Dictionary(getEntries(for: .downloads, startDate: startDate, filteredApps: filteredApps).map { (SalesRegion(countryCode: $0.countryCode), $0.units) }, uniquingKeysWith: +)
        return byRegion
            .filter { $0.value > 0 }
            .map { $0.key.share(downloads: $0.value) }
            .slices(foldingInto: SalesRegion.unknown.share())
    }
}

extension ACData {
    /// Last 30 days' proceeds by source, most first, in the display currency. Every source a pie
    /// would draw as a sliver is left out, as there is no "Other" to fold it into.
    public func incomeBySource(filteredApps: [ACApp] = []) -> [PieShare] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: .now) ?? .now
        let bySource = Dictionary(getEntries(for: .proceeds, startDate: startDate, filteredApps: filteredApps)
            .compactMap { entry in IncomeSource(entry.type).map { ($0, Double(entry.proceeds) * Double(entry.units)) } },
                                  uniquingKeysWith: +)
        let total = bySource.values.reduce(0, +)
        return bySource
            .filter { $0.value >= total * 0.02 && $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { $0.key.share($0.value) }
    }
}

extension AppStoreAnalytics {
    /// Average daily active devices by major OS version, most first and anything before the
    /// year-numbered releases last. Every app's when `filteredApps` is empty.
    public func activeDevicesByOS(filteredApps: [ACApp] = []) -> [PieShare] {
        let totals = filteredApps.isEmpty ? [totals()] : filteredApps.map { totals(for: $0.appleID) }
        let byOS = totals.reduce(into: [Int: Int]()) { $0.merge($1.averageDailyActiveDevicesByOS, uniquingKeysWith: +) }
        let colors: [Color] = [.blue, .indigo, .purple, .teal, .mint]
        let releases = byOS.keys.filter { $0 > 0 }.sorted(by: >)
        let shares = byOS.filter { $0.value > 0 }.map { os, devices in
            if os == 0 {
                return PieShare(name: String(localized: "Earlier", bundle: #bundle), badge: .symbol("clock.arrow.circlepath"), color: .gray, value: Double(devices))
            }
            let rank = releases.firstIndex(of: os) ?? 0
            return PieShare(name: String(localized: "OS \(os)", bundle: #bundle), badge: .symbol("\(os).circle.fill"), color: colors[rank % colors.count], value: Double(devices))
        }
        return shares.slices(foldingInto: PieShare(name: String(localized: "Earlier", bundle: #bundle), badge: .symbol("clock.arrow.circlepath"), color: .gray, value: 0))
    }
}

extension [PieShare] {
    /// The shares a pie can draw, most first. At the Summary's size, one under 2% is lost to the
    /// slices' insets and corner radius, so it shows as nothing but a wider gap; those fold into `other`, which is left out
    /// in turn if they still come to a sliver together. `other` keeps its own name while at least half of it is its own.
    func slices(foldingInto other: PieShare) -> [PieShare] {
        let total = reduce(0) { $0 + $1.value }
        let isSliver = { (value: Double) in value < total * 0.02 }
        let kept = filter { $0.id != other.id && !isSliver($0.value) }
            .sorted { $0.value > $1.value }
        let rest = total - kept.reduce(0) { $0 + $1.value }
        guard rest > 0, !isSliver(rest) else { return kept }

        let own = filter { $0.id == other.id }.reduce(0) { $0 + $1.value }
        let name = own * 2 >= rest ? other.name : String(localized: "Other", bundle: #bundle)
        return kept + [PieShare(name: name, badge: other.badge, color: other.color, value: rest)]
    }
}
#endif
