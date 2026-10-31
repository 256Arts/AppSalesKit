// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppSalesKit",
    defaultLocalization: "en",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
        .watchOS("26.0"),
        .visionOS("27.0"),
    ],
    products: [
        // App Store Connect sales, analytics, reviews, and the accounts behind them — the model for an
        // app or extension, plus the views (not on watchOS).
        .library(name: "AppSalesKit", targets: ["AppSalesKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AvdLee/appstoreconnect-swift-sdk.git", from: "4.4.3"),
        .package(url: "https://github.com/1024jp/GzipSwift", from: "5.1.1"),
        .package(url: "https://github.com/swiftcsv/SwiftCSV", from: "0.6.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/256Arts/AIUsageKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AppSalesKit",
            dependencies: [
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
                .product(name: "Gzip", package: "GzipSwift"),
                "SwiftCSV",
                "KeychainAccess",
                "AIUsageKit",
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5), .enableUpcomingFeature("BareSlashRegexLiterals")]),
    ]
)
