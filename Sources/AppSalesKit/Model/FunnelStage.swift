import SwiftUI

/// One step of the funnel: a count of people or devices.
public struct FunnelStage: Identifiable {
    public let stat: AppListSort
    public let color: Color
    public let count: Int
    /// The change on the 30 days before, when there is a figure to compare with.
    public var change: Double?

    public var id: AppListSort { stat }

    /// Grey stages tapering like a typical funnel, standing in while the analytics reports load.
    public static func placeholders(website: Bool) -> [FunnelStage] {
        let stages: [(AppListSort, Int)] = [(.websiteViews, 4_000), (.appStoreViews, 10_000), (.downloads, 3_000), (.activeDevices, 800)]
        return stages
            .filter { website || $0.0 != .websiteViews }
            .map { FunnelStage(stat: $0.0, color: .gray.opacity(0.3), count: $0.1) }
    }
}
