#if !os(watchOS)
import SwiftUI
import AuthenticationServices
import AIUsageKit

/// Every account the app reads from, in one list, above the one place to add another: App Store
/// Connect keys, Google Analytics and AdMob sign-ins, and AIUsageKit's Claude and Codex. Has a Done
/// button, so present it in a `NavigationStack` in a sheet.
public struct AccountsList: View {

    public init() {}

    @AppStorage(UserDefaults.Key.includeRedownloads, store: UserDefaults.shared) var includeRedownloads: Bool = false
    @AppStorage(UserDefaults.Key.homeSelectedKey, store: UserDefaults.shared) private var keyID: String = ""
    @Environment(\.dismiss) private var dismiss
    private var accountManager: AccountManager { .shared }
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var assistants = AIAssistants.shared
    @State private var connectingAssistant: AIAssistant?
    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var adMob = AdMob.shared

    @State private var showingAddAccount: Bool = false
    /// An App Store Connect key asked to be removed. Its private key cannot be downloaded again, so
    /// removing it is confirmed.
    @State private var removingAccount: Account?
    @State private var signInError: Error?

    public var body: some View {
        List {
            if accountManager.accounts.count > 1 {
                Section {
                    Picker(String(localized: "Current Account", bundle: #bundle), selection: currentAccount) {
                        ForEach(accountManager.accounts) { account in
                            Text(account.name).tag(account.id)
                        }
                    }
                }
            }

            if !isEmpty {
                Section {
                    ForEach(accountManager.accounts) { account in
                        NavigationLink(destination: AccountDetailView(account)) {
                            LabeledContent {
                                AccountStatusSymbol(account: account)
                            } label: {
                                AccountLabel(account.name, service: "App Store Connect") {
                                    Image(.logoAppstore)
                                }
                            }
                        }
                        .contextMenu {
                            signOutButton { removingAccount = account }
                        }
                    }
                    .onDelete { offsets in
                        removingAccount = offsets.first.map { accountManager.accounts[$0] }
                    }

                    ForEach(googleAnalytics.accounts) { account in
                        NavigationLink(destination: GoogleAnalyticsWebsitesView(account: account)) {
                            LabeledContent {
                                Text(googleAnalytics.websites(of: account).map(\.name).formatted(.list(type: .and)))
                            } label: {
                                AccountLabel(service: "Google Analytics", email: account.email) {
                                    Image(systemName: "chart.bar.xaxis")
                                }
                            }
                        }
                        .contextMenu {
                            signOutButton { googleAnalytics.disconnect(account) }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { googleAnalytics.accounts[$0] }.forEach(googleAnalytics.disconnect)
                    }

                    ForEach(adMob.accounts) { account in
                        AccountLabel(service: "AdMob", email: account.email) {
                            Image(systemName: "rectangle.stack.badge.play")
                        }
                        .contextMenu {
                            signOutButton { adMob.disconnect(account) }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { adMob.accounts[$0] }.forEach(adMob.disconnect)
                    }

                    ForEach(assistants.connected) { assistant in
                        AccountLabel(assistant.name, service: "Usage Limits") {
                            Image(systemName: assistant.systemImage)
                        }
                        .contextMenu {
                            signOutButton { assistants.disconnect(assistant) }
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { assistants.connected[$0] }.forEach(assistants.disconnect)
                    }
                }
            }

            Section {
                addAccountMenu

                if let signInError {
                    Text(signInError.localizedDescription)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Text("Accounts", bundle: #bundle))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done", bundle: #bundle), systemImage: "checkmark") {
                    dismiss()
                }
            }
        }
        .confirmationDialog(String(localized: "Sign out of \(removingAccount?.name ?? "")?", bundle: #bundle), isPresented: Binding(get: { removingAccount != nil }, set: { if !$0 { removingAccount = nil } }), presenting: removingAccount) { account in
            Button(String(localized: "Sign Out", bundle: #bundle), role: .destructive) {
                ACDataCache.clearCache(apiKey: account)
                accountManager.deleteApiKeys(keys: [account])
            }
        } message: { _ in
            Text("Signing in again needs the API key's private key file, which App Store Connect does not let you download twice.", bundle: #bundle)
        }
        .sheet(isPresented: $showingAddAccount) {
            NavigationStack {
                NewAccountView()
            }
        }
        .sheet(item: $connectingAssistant) { assistant in
            AIUsageSignInSheet(assistant: assistant)
        }
    }

    private var isEmpty: Bool {
        accountManager.accounts.isEmpty && !googleAnalytics.isConnected && !adMob.isConnected && assistants.connected.isEmpty
    }

    /// The one sign-out every account row offers on a long press, beside its swipe to delete.
    private func signOutButton(action: @escaping () -> Void) -> some View {
        Button(String(localized: "Sign Out", bundle: #bundle), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: action)
    }

    private var addAccountMenu: some View {
        Menu {
            Button {
                showingAddAccount = true
            } label: {
                Text("App Store Connect", bundle: #bundle)
                Text("Sales, downloads, and proceeds", bundle: #bundle)
                Image(.logoAppstore)
            }

            // Google services enrich App Store Connect data, so they wait for an account.
            if GoogleSignIn.isAvailable, !accountManager.accounts.isEmpty {
                Button {
                    Task { await signIn(request: GoogleAnalytics.signInRequest(), connect: googleAnalytics.connect) }
                } label: {
                    Text("Google Analytics", bundle: #bundle)
                    Text("Views of each app's webpage", bundle: #bundle)
                    Image(systemName: "chart.bar.xaxis")
                }
                Button {
                    Task { await signIn(request: AdMob.signInRequest(), connect: adMob.connect) }
                } label: {
                    Text("AdMob", bundle: #bundle)
                    Text("Estimated ad earnings count toward proceeds", bundle: #bundle)
                    Image(systemName: "rectangle.stack.badge.play")
                }
            }

            ForEach(AIAssistant.allCases.filter { !assistants.connected.contains($0) }) { assistant in
                Button {
                    connectingAssistant = assistant
                } label: {
                    Text(assistant.name)
                    Text("Usage limits", bundle: #bundle)
                    Image(systemName: assistant.systemImage)
                }
            }

            // The demo is for a first look, so it goes once anything is signed in, itself included.
            if isEmpty {
                Divider()
                Button(String(localized: "Demo Account", bundle: #bundle), systemImage: "theatermasks") {
                    try? accountManager.addApiKey(apiKey: Account.demoAccount)
                }
            }
        } label: {
            Label(String(localized: "Add Account", bundle: #bundle), systemImage: "plus")
        }
    }

    /// The account the home screen shows, which is the first one until the reader picks another.
    private var currentAccount: Binding<String> {
        Binding {
            accountManager.getApiKey(apiKeyId: keyID)?.id ?? accountManager.accounts.first?.id ?? ""
        } set: {
            keyID = $0
        }
    }

    /// Runs a Google sign-in in a browser session and hands its callback to the service.
    private func signIn(request: (url: URL, verifier: String), connect: (URL, String) async throws -> Void) async {
        signInError = nil
        do {
            let callback = try await webAuthenticationSession.authenticate(using: request.url, callback: .customScheme(GoogleSignIn.callbackScheme), additionalHeaderFields: [:])
            try await connect(callback, request.verifier)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            signInError = error
        }
    }
}

/// An account's name over the service it signs in to, or for a Google sign-in, the service over its email.
private struct AccountLabel<Icon: View>: View {
    public let title: Text
    public let subtitle: Text
    @ViewBuilder public let icon: Icon

    public init(_ name: String, service: LocalizedStringKey, @ViewBuilder icon: () -> Icon) {
        self.title = Text(name)
        self.subtitle = Text(service, bundle: #bundle)
        self.icon = icon()
    }

    public init(service: LocalizedStringKey, email: String, @ViewBuilder icon: () -> Icon) {
        self.title = Text(service, bundle: #bundle)
        self.subtitle = Text(email)
        self.icon = icon()
    }

    public var body: some View {
        Label {
            title
            subtitle
        } icon: {
            icon
        }
    }
}

#Preview {
    AccountsList()
}

// MARK: - AccountStatusSymbol

public struct AccountStatusSymbol: View {
    public let account: Account

    public init(account: Account) {
        self.account = account
    }

    @State private var status: APIError?
    @State private var loading = true

    public var body: some View {
        Group {
            if loading {
                Image(systemName: "icloud")
                    .foregroundStyle(.gray)
            } else if status == nil {
                Image(systemName: "checkmark.icloud")
                    .foregroundStyle(.green)
            } else if status == .invalidCredentials {
                Image(systemName: "xmark.icloud")
                    .foregroundStyle(.red)
            } else {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
        }
        .task(priority: .background) {
            do {
                try await account.checkKey()
            } catch let err {
                status = APIError(err)
            }
            loading = false
        }
    }
}

/// Which of one Google account's Analytics properties are websites the reader writes about their apps on.
private struct GoogleAnalyticsWebsitesView: View {

    public let account: GoogleAccount

    @Environment(\.dismiss) private var dismiss
    @State private var googleAnalytics = GoogleAnalytics.shared
    @State private var properties: [GoogleAnalyticsProperty]?
    @State private var error: Error?

    public var body: some View {
        List {
            if let properties {
                ForEach(Dictionary(grouping: properties, by: \.accountName).sorted { $0.key < $1.key }, id: \.key) { accountName, properties in
                    Section(accountName) {
                        ForEach(properties) { property in
                            let isChosen = googleAnalytics.websites(of: account).contains { $0.id == property.id }
                            Button {
                                googleAnalytics.setWebsite(property, isChosen: !isChosen, of: account)
                            } label: {
                                LabeledContent(property.name) {
                                    if isChosen {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let error {
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }

            Section {
                Button(String(localized: "Sign Out", bundle: #bundle), role: .destructive) {
                    googleAnalytics.disconnect(account)
                    dismiss()
                }
            }
        }
        .navigationTitle(account.email)
        .task {
            do {
                properties = try await googleAnalytics.properties(of: account)
            } catch {
                self.error = error
            }
        }
    }
}
#endif
