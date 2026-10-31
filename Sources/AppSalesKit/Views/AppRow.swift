#if !os(watchOS)
import SwiftUI

/// One app in an app list: its icon, name and price, then its figures in
/// `AppListSort` order, so they read the same way as the view options menu. An app no longer on the App
/// Store shows none of them.
public struct AppRow: View {

    let app: AppPerformanceSummary
    let iconLength: CGFloat
    /// The figures of each `sortsByCounts` sort, keyed by Apple ID, from `SalesDataLoader.appCounts`.
    let counts: [AppListSort: [String: Int]]
    let hiddenStats: Set<AppListSort>

    /// - Parameter hiddenStats: Those the reader turned off in `AppListOptions`, read with
    ///   `AppListOptions.hiddenStats(in:)` from `UserDefaults.Key.appListHiddenStats`.
    public init(app: AppPerformanceSummary, iconLength: CGFloat, counts: [AppListSort: [String: Int]], hiddenStats: Set<AppListSort>) {
        self.app = app
        self.iconLength = iconLength
        self.counts = counts
        self.hiddenStats = hiddenStats
    }

    public var body: some View {
        HStack {
            AppIconView(app: app, length: iconLength)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(app.name)
                        .accessibilityIdentifier("AppRow.\(app.name)")
                    if !hiddenStats.contains(.price) {
                        price
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .labelStyle(StatLabelStyle())
                    }
                }
                .lineLimit(1)

                HStack(spacing: 8) {
                    ForEach(AppListSort.allCases.filter { !hiddenStats.contains($0) }) { sort in
                        stat(for: sort)
                    }
                    // Soaks up the width the row has spare, so the stats stay grouped
                    // at the leading edge rather than spreading across the row.
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(StatLabelStyle())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
    }

    /// The name and price sit on the line above, so they have no stat here.
    @ViewBuilder
    private func stat(for sort: AppListSort) -> some View {
        switch sort {
        case .downloads: downloads
        case .proceeds: proceeds
        case .name, .price: EmptyView()
        case .websiteViews, .impressions, .appStoreViews, .activeDevices:
            // Each column is as wide as its widest row's figure, so the stats after it line up.
            if let values = counts[sort], let widest = values.values.max() {
                ViewsColumn(views: values[app.appleID], widest: widest, systemImage: sort.systemImage) {
                    spokenLabel(for: sort, count: $0)
                }
            }
        }
    }

    private func spokenLabel(for sort: AppListSort, count: Int) -> Text {
        switch sort {
        case .impressions: Text("\(count) App Store impressions in the last 30 days", bundle: #bundle)
        case .appStoreViews: Text("\(count) App Store product page views in the last 30 days", bundle: #bundle)
        case .activeDevices: Text("\(count) active devices a day over the last 30 days", bundle: #bundle)
        default: Text("\(count) webpage views in the last 30 days", bundle: #bundle)
        }
    }

    /// Downloads and proceeds are both over the last 30 days, matching the summary above the list.
    private var downloads: some View {
        Label(app.downloads.formatted(), systemImage: "arrow.down.app")
            .accessibilityLabel(Text("\(app.downloads) downloads in the last 30 days", bundle: #bundle))
    }
    /// Bare, the way the summary above the list prints its total: the currency symbol says enough.
    private var proceeds: some View {
        Text(proceedsString)
            .accessibilityLabel(Text("\(proceedsString) proceeds in the last 30 days", bundle: #bundle))
    }
    private var price: some View {
        Label(priceString, systemImage: "tag")
            .accessibilityLabel(Text("Priced at \(priceString)", bundle: #bundle))
    }

    private var proceedsString: String {
        NumberFormatter.currency.string(from: NSNumber(value: app.proceeds)) ?? ""
    }
    private var priceString: String {
        guard app.price > 0 else { return String(localized: "Free", bundle: #bundle) }

        return NumberFormatter.currency.string(from: NSNumber(value: app.price)) ?? ""
    }
}

/// A view count, as wide as the widest row's figure whether or not this app has one, so the
/// column holds.
private struct ViewsColumn: View {

    let views: Int?
    let widest: Int
    let systemImage: String
    /// What VoiceOver reads for a count, since the icon alone says nothing spoken.
    let spokenLabel: (Int) -> Text

    var body: some View {
        ZStack(alignment: .leading) {
            Label(widest.formatted(), systemImage: systemImage)
                .hidden()
            if let views {
                Label(views.formatted(), systemImage: systemImage)
                    .accessibilityLabel(spokenLabel(views))
            }
        }
        .accessibilityHidden(views == nil)
    }
}

/// Which stats the app rows show and what they are sorted by, as menu contents: for a view options
/// menu beside the app list, and for the menu bar's View menu. A stat without figures yet is left out of both, unless it is the
/// chosen sort, so the menu still shows what the list is in.
public struct AppListOptions: View {

    /// The `sortsByCounts` stats that have figures yet.
    let countedStats: Set<AppListSort>
    /// Longer submenu titles, for the menu bar's View menu, where they sit beside other choices.
    var inMenuBar = false

    /// - Parameter countedStats: The keys of `SalesDataLoader.appCounts`.
    public init(countedStats: Set<AppListSort>, inMenuBar: Bool = false) {
        self.countedStats = countedStats
        self.inMenuBar = inMenuBar
    }

    @AppStorage(UserDefaults.Key.appListSort, store: UserDefaults.shared) private var sort: AppListSort = .downloads
    /// The stats hidden from the app rows, as comma-separated `AppListSort` raw values.
    @AppStorage(UserDefaults.Key.appListHiddenStats, store: UserDefaults.shared) private var hiddenStatsValue = AppListOptions.defaultHiddenStats

    /// Impressions and App Store views are more than most readers want on every row, so they start hidden.
    public static let defaultHiddenStats = [AppListSort.impressions, .appStoreViews].map(\.rawValue).joined(separator: ",")

    public static func hiddenStats(in value: String) -> Set<AppListSort> {
        Set(value.split(separator: ",").compactMap { AppListSort(rawValue: String($0)) })
    }

    private func isShowing(_ stat: AppListSort) -> Binding<Bool> {
        Binding {
            !Self.hiddenStats(in: hiddenStatsValue).contains(stat)
        } set: { isShowing in
            var hidden = Self.hiddenStats(in: hiddenStatsValue)
            if isShowing { hidden.remove(stat) } else { hidden.insert(stat) }
            hiddenStatsValue = AppListSort.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
        }
    }

    private var stats: some View {
        ForEach(AppListSort.allCases.filter { $0 != .name && (!$0.sortsByCounts || countedStats.contains($0)) }) { stat in
            Toggle(isOn: isShowing(stat)) {
                Label(stat.title, systemImage: stat.systemImage)
            }
        }
    }

    private var sorts: some View {
        ForEach(AppListSort.allCases.filter { !$0.sortsByCounts || countedStats.contains($0) || $0 == sort }) { sort in
            Label(sort.title, systemImage: sort.systemImage)
                .tag(sort)
        }
    }

    public var body: some View {
        Menu {
            stats
        } label: {
            Label(inMenuBar ? String(localized: "Show in App List", bundle: #bundle) : String(localized: "Show", bundle: #bundle), systemImage: "checklist")
        }
        Picker(selection: $sort) {
            sorts
        } label: {
            Label(inMenuBar ? String(localized: "Sort Apps By", bundle: #bundle) : String(localized: "Sort By", bundle: #bundle), systemImage: "arrow.up.arrow.down")
        }
        .pickerStyle(.menu)
    }
}

/// A stat's icon hard against its figure, so the gaps in the row fall between stats instead.
private struct StatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon
            configuration.title
        }
    }
}
#endif
