import Foundation

extension UserDefaults {
    
    /// The preferences AppSalesKit keeps in `UserDefaults.shared`. A host can add its own in an extension.
    public struct Key {
        public static let includeRedownloads = "includeRedownloads"
        public static let homeSelectedKey = "homeSelectedKey"
        public static let appListSort = "appListSort"
        public static let appListHiddenStats = "appListHiddenStats"
        public static let homeChartSort = "homeChartSort"
        public static let homeChartShowsActiveDevices = "homeChartShowsActiveDevices"
    }

}
