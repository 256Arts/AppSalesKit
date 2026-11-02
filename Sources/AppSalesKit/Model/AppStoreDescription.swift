import Foundation
import AppStoreConnect_Swift_SDK

extension Account {
    /// The app's product page description from App Store Connect: its newest version's, in
    /// English where it has one, else its first language. `nil` when the app has no version or
    /// description yet.
    public func appStoreDescription(appleID: String) async throws -> String? {
        let provider = try apiProvider()
        do {
            let versions = try await provider.request(APIEndpoint.v1.apps.id(appleID).appStoreVersions.get(parameters: .init(limit: 10)))
            guard let newest = versions.data.max(by: { ($0.attributes?.createdDate ?? .distantPast) < ($1.attributes?.createdDate ?? .distantPast) }) else { return nil }
            let localizations = try await provider.request(APIEndpoint.v1.appStoreVersions.id(newest.id).appStoreVersionLocalizations.get(parameters: .init(limit: 200))).data
            let chosen = localizations.first { $0.attributes?.locale == "en-US" }
                ?? localizations.first { $0.attributes?.locale?.hasPrefix("en") == true }
                ?? localizations.first
            return chosen?.attributes?.description.flatMap { $0.isEmpty ? nil : $0 }
        } catch {
            throw APIError(error)
        }
    }
}
