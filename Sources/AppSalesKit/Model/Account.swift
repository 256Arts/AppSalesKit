import SwiftUI
import AppIntents

public struct Account: Codable, Identifiable, Hashable, AppEntity {
    public var id: String { privateKeyID }
    public let name: String
    public let issuerID: String
    public let privateKeyID: String
    public let privateKey: String
    public let vendorNumber: String

    public init(name: String, issuerID: String, privateKeyID: String, privateKey: String, vendorNumber: String) {
        self.name = name
        self.issuerID = issuerID
        self.privateKeyID = privateKeyID
        self.vendorNumber = vendorNumber

        self.privateKey = privateKey
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .removeCharacters(from: .whitespacesAndNewlines)
    }
    
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    public static var defaultQuery = AccountQuery()
    
    public static let demoAccount = Account(name: "Demo", issuerID: "demo", privateKeyID: "demo", privateKey: "demo", vendorNumber: "demo")

    /// A demo account under another name, for the several a screenshot run seeds.
    public static func demoAccount(named name: String, id: String) -> Account {
        Account(name: name, issuerID: demoAccount.issuerID, privateKeyID: id, privateKey: "demo", vendorNumber: "demo")
    }

    /// Whether the fetch pipeline should serve `ACData.example` instead of reaching App Store
    /// Connect. Keyed on the issuer ID rather than the account's own, so the extra accounts a
    /// screenshot run seeds are covered too; a real issuer ID is a UUID and cannot collide.
    public var isDemo: Bool {
        issuerID == Account.demoAccount.issuerID
    }


    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

public struct AccountQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [Account.ID]) async throws -> [Account] {
        AccountManager.shared.accounts.filter { identifiers.contains($0.id) }
    }
    
    public func suggestedEntities() async throws -> [Account] {
        AccountManager.shared.accounts
    }
    
    public func defaultResult() async -> Account? {
        try? await suggestedEntities().first
    }
}

extension Account {
    public func equalsKeyDetails(other key: Account) -> Bool {
        return self.issuerID == key.issuerID && self.privateKeyID == key.privateKeyID && self.privateKey == key.privateKey && self.privateKeyID == key.privateKeyID
    }
}

@MainActor
extension Account {
    static private var lastChecks: [Account: LoaderStatus] = [:]
    private enum LoaderStatus {
        case inProgress(Task<Void, Error>)
        case loaded((error: Error?, date: Date))
    }

    public static func clearMemoization() {
        lastChecks.removeAll()
    }

    public func checkKey() async throws {
        if let check = Account.lastChecks[self] {
            switch check {
            case .loaded(let res):
                if res.date.timeIntervalSinceNow > -30 {
                    if let error = res.error {
                        throw error
                    } else {
                        return
                    }
                } else {
                    Account.lastChecks.removeValue(forKey: self)
                }
            case .inProgress(let task):
                try await task.value
                return
            }
        }

        let task: Task<Void, Error> = Task {
            let api = AppStoreConnectAPI(apiKey: self)
            do {
                _ = try await api.getData(numOfDays: 1, useCache: false)
            } catch APIError.noDataAvailable {
                return
            } catch {
                throw APIError(error)
            }
            return
        }

        Account.lastChecks[self] = .inProgress(task)

        do {
            try await task.value
            Account.lastChecks[self] = .loaded((error: nil, date: .now))
        } catch {
            Account.lastChecks[self] = .loaded((error: error, date: .now))
            throw error
        }

        return
    }
}
