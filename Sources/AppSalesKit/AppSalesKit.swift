import Foundation
import AppIntents

/// Where AppSalesKit keeps what it shares between an app, its extensions, and the reader's other
/// devices.
///
/// Read from an `AppSalesKit` dictionary in the Info.plist of every target that links the package —
/// the app and each widget extension — rather than set in code, because a widget timeline or an App
/// Intent can run before any of the host's own code has:
///
///     <key>AppSalesKit</key>
///     <dict>
///         <key>AppGroup</key>
///         <string>group.com.example.app</string>
///         <key>KeychainService</key>
///         <string>com.example.app</string>
///         <key>GoogleClientID</key>
///         <string>…apps.googleusercontent.com</string>
///     </dict>
///
/// The App Group holds the caches, the app icons, and the preferences; the Keychain service,
/// synchronizable, holds the sign-ins so they reach the reader's other devices. `GoogleClientID` is
/// an iOS-type OAuth client whose reversed ID the app registers as a URL scheme; without one, Google
/// Analytics and AdMob are not offered.
public enum AppSalesKit {

    private static let configuration = Bundle.main.object(forInfoDictionaryKey: "AppSalesKit") as? [String: String] ?? [:]

    /// `nil` without one configured, which leaves every process to itself: nothing is cached for the
    /// others, and preferences fall back to their defaults.
    public static let appGroupID = configuration["AppGroup"]

    static let keychainService = configuration["KeychainService"] ?? Bundle.main.bundleIdentifier ?? "AppSalesKit"

    static let googleClientID = configuration["GoogleClientID"] ?? ""

    /// The App Group container, for the caches and the app icons.
    public static var containerURL: URL? {
        appGroupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }
}

/// Makes this package's App Intents types — the account entity and the metric enum — visible to a
/// host's App Intents metadata. Include it in the host's own `AppIntentsPackage`.
public struct AppSalesKitPackage: AppIntentsPackage { }
