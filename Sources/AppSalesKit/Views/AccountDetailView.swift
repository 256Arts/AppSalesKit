#if !os(watchOS)
import SwiftUI

public struct AccountDetailView: View {
    
    @Environment(\.dismiss) var dismiss
    private var accountManager: AccountManager { .shared }

    public let account: Account
    @State private var keyName: String
    private var issuerID: String
    private var privateKeyID: String
    private var privateKey: String
    private var vendorNumber: String

    @State private var status: APIError?

    @State private var apps: [ACApp] = []
    @State private var cachedEntries: Int

    public init(_ key: Account) {
        self.account = key
        self._keyName = State(initialValue: key.name)
        self._cachedEntries = State(initialValue: ACDataCache.numberOfEntriesCached(apiKey: key))
        self.issuerID = key.issuerID
        self.privateKeyID = key.privateKeyID
        self.privateKey = key.privateKey
        self.vendorNumber = key.vendorNumber
    }

    public var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Account Name", bundle: #bundle)) {
                    TextField(String(localized: "Account Name", bundle: #bundle), text: $keyName)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                }

                Button(String(localized: "Save", bundle: #bundle), action: save)
            }
            
            if let status = status {
                Section {
                    Text(status.localizedDescription)
                }
            }
            
            Section {
                LabeledContent(String(localized: "Issuer ID", bundle: #bundle)) {
                    Text(issuerID)
                        .textSelection(.enabled)
                }
                LabeledContent(String(localized: "Private Key ID", bundle: #bundle)) {
                    Text(privateKeyID)
                        .textSelection(.enabled)
                }
                LabeledContent(String(localized: "Private Key", bundle: #bundle)) {
                    HStack {
                        Text("••••\(String(privateKey.suffix(4)))", bundle: #bundle)
                        Button(String(localized: "Copy", bundle: #bundle), systemImage: "doc.on.doc") {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = privateKey
                            #else
                            NSPasteboard.general.setString(privateKey, forType: .string)
                            #endif
                        }
                    }
                }
                LabeledContent(String(localized: "Vendor Number", bundle: #bundle)) {
                    Text(vendorNumber)
                        .textSelection(.enabled)
                }
            }
            
            Section {
                Button(String(localized: "Delete", bundle: #bundle), systemImage: "trash", role: .destructive) {
                    showingDeleteAlert.toggle()
                }
            }
            .alert(String(localized: "Delete Account?", bundle: #bundle), isPresented: $showingDeleteAlert) {
                Button(String(localized: "Delete", bundle: #bundle), role: .destructive) {
                    ACDataCache.clearCache(apiKey: account)
                    accountManager.deleteApiKeys(keys: [account])
                    dismiss()
                }
                Button(String(localized: "Cancel", bundle: #bundle), role: .cancel) { }
            }
        }
        .task {
            do {
                try await account.checkKey()
                try await loadApps()
            } catch let err {
                status = APIError(err)
            }
        }
        .navigationTitle(Text("Account", bundle: #bundle))
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done", bundle: #bundle), systemImage: "checkmark") {
                    dismiss()
                }
            }
        }
        #endif
    }

    private func loadApps() async throws {
        let api = AppStoreConnectAPI(apiKey: account)
        let data = try await api.getData(currency: Currency.USD, useCache: true)
        self.apps = data.apps
    }

    private func save() {
        try? accountManager.addApiKey(
            apiKey: Account(
                name: keyName,
                issuerID: issuerID,
                privateKeyID: privateKeyID,
                privateKey: privateKey,
                vendorNumber: vendorNumber))
    }

    @State var showingDeleteAlert = false
}

#Preview {
    AccountDetailView(Account.demoAccount)
}
#endif
