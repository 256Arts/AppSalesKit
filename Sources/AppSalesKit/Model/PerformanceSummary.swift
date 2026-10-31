import Foundation
import SwiftUI

public struct PerformanceSummary {
    public let downloads: Int
    public let prevDownloads: Int
    public let proceeds: Double
    public let prevProceeds: Double
    /// The part of `proceeds` that is AdMob earnings rather than App Store sales.
    public let adProceeds: Double
    public let prevAdProceeds: Double
    /// Every app, best-selling first. Views that only have room for a few take `topApps`.
    public let apps: [AppPerformanceSummary]

    /// The handful of apps the chart and the widget graphics have room for.
    public var topApps: [AppPerformanceSummary] {
        Array(apps.prefix(6))
    }
    
    public var downloadsPercentageChange: Double {
        PerformanceSummary.percentageChange(from: Double(prevDownloads), to: Double(downloads))
    }
    public var proceedsPercentageChange: Double {
        PerformanceSummary.percentageChange(from: prevProceeds, to: proceeds)
    }

    /// Fractional change between two windows, capped at +999% so a first sale out of nothing cannot
    /// print an arrow the width of the row. Shared with the intents, which report metrics this
    /// summary does not carry.
    public static func percentageChange(from previous: Double, to current: Double) -> Double {
        guard previous > 0 else { return current == 0 ? 0 : 9.99 }

        return min(current / previous - 1, 9.99)
    }
}

public struct AppPerformanceSummary: Identifiable {
    public let appleID: String
    public var id: String { appleID }
    public let name: String
    public let iconURL: URL?
    public let downloads: Int
    public let proceeds: Double
    /// The part of `proceeds` that is AdMob earnings.
    public let adProceeds: Double
    public let price: Double

    public var url: URL {
        URL(string: "https://apps.apple.com/app/id" + appleID) ?? URL(filePath: "/")
    }
    public var cachedIconURL: URL? {
        guard let groupURL = AppSalesKit.containerURL else { return nil }
        
        return groupURL.appending(path: appleID).appendingPathExtension("jpg")
    }
    
    public var cachedIcon: Image? {
        guard let path = cachedIconURL?.path(percentEncoded: false), let data = FileManager.default.contents(atPath: path) else { return nil }
        
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}

/// The orders the home screen's app list can be sorted into, in the order each app row shows them.
public enum AppListSort: String, CaseIterable, Identifiable {
    case name
    case price
    case websiteViews
    case impressions
    case appStoreViews
    case downloads
    case activeDevices
    case proceeds

    public var id: Self { self }

    public var title: String {
        switch self {
        case .name: String(localized: "Name", bundle: #bundle)
        case .price: String(localized: "Price", bundle: #bundle)
        case .websiteViews: String(localized: "Webpage Views", bundle: #bundle)
        case .impressions: String(localized: "Impressions", bundle: #bundle)
        case .appStoreViews: String(localized: "App Store Views", bundle: #bundle)
        case .downloads: String(localized: "Downloads", bundle: #bundle)
        case .activeDevices: String(localized: "Daily Active Devices", bundle: #bundle)
        case .proceeds: String(localized: "Proceeds", bundle: #bundle)
        }
    }

    public var systemImage: String {
        switch self {
        case .name: "textformat"
        case .price: "tag"
        case .websiteViews: "globe"
        case .impressions: "eye"
        case .appStoreViews: "doc.text.magnifyingglass"
        case .downloads: "arrow.down.app"
        case .activeDevices: "person.2"
        case .proceeds: "dollarsign.circle"
        }
    }

    /// Whether the sort orders by figures from outside the sales reports, which the caller passes in.
    public var sortsByCounts: Bool {
        [.websiteViews, .impressions, .appStoreViews, .activeDevices].contains(self)
    }

    /// Highest first for the numbers, and A–Z for the name.
    /// `counts` are the figures a `sortsByCounts` sort orders by, keyed by Apple ID; apps tied on
    /// them — every app, while they have not loaded — fall back to downloads.
    public func sort(_ apps: [AppPerformanceSummary], counts: [String: Int] = [:]) -> [AppPerformanceSummary] {
        switch self {
        case .name: apps.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
        case .price: apps.sorted(by: { $0.price > $1.price })
        case .downloads: apps.sorted(by: { $0.downloads > $1.downloads })
        case .proceeds: apps.sorted(by: { $0.proceeds > $1.proceeds })
        case .websiteViews, .impressions, .appStoreViews, .activeDevices:
            apps.sorted { a, b in
                let (aCount, bCount) = (counts[a.appleID] ?? 0, counts[b.appleID] ?? 0)
                return aCount == bCount ? a.downloads > b.downloads : aCount > bCount
            }
        }
    }
}
