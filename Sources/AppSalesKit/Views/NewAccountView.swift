#if !os(watchOS)
import SwiftUI

public struct NewAccountView: View {

    public init() {}
    
    @Environment(\.dismiss) var dismiss
    private var accountManager: AccountManager { .shared }
    @State private var alert: AddAPIKeyAlert?

    @State private var name: String = ""
    @State private var issuerID: String = ""
    @State private var keyID: String = ""
    @State private var key: String = ""
    @State private var vendor: String = ""

    @State private var errorFields: Set<Fields> = .init()

    public var body: some View {
        ScrollView {
            VStack {
                TextField(String(localized: "Account Name", bundle: #bundle), text: $name)
                    .textFieldStyle(.roundedBorder)
                
                VStack {
                    Text("If you haven't created an API key yet, now is the time to do it.", bundle: #bundle)
                        .multilineTextAlignment(.center)
                    
                    Link(destination: URL(string: "https://developer.apple.com/documentation/appstoreconnectapi/creating_api_keys_for_app_store_connect_api")!) {
                        HStack {
                            Text("How to create an API key", bundle: #bundle)
                            Image(systemName: "arrow.up.forward.app")
                        }
                    }
                }
                .padding(.vertical)
                
                VStack {
                    HStack {
                        Text("Issuer ID", bundle: #bundle)
                            .font(.headline)
                        Spacer()
                        infoCard(title: "On the top of the keys page in App Store Connect, it will state your 'Issuer ID'.")
                    }

                    TextField(String(localized: "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX", bundle: #bundle), text: $issuerID)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.issuerID) ? .red : nil))
                }
                VStack {
                    HStack {
                        Text("Private Key ID", bundle: #bundle)
                            .font(.headline)
                        Spacer()
                        infoCard(title: "In the third column of the table on the keys page in App Store Connect.")
                    }

                    TextField(String(localized: "XXXXXXXXXX", bundle: #bundle), text: $keyID)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.keyID) ? .red : nil))
                }
                VStack {
                    HStack {
                        Text("Private Key", bundle: #bundle)
                            .font(.headline)
                        Spacer()
                        infoCard(title: "You should have gotten the key right after creating it. Once you close the window, there unfortunately is no way to show it again. You'll have to create a new one.")
                    }

                    TextEditor(text: $key)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.key) ? .red : nil))
                        .frame(height: 150)
                }
                VStack {
                    HStack {
                        Text("Vendor Number", bundle: #bundle)
                            .font(.headline)
                        Spacer()
                        infoCard(title: "You can find it on App Store Connect in your 'Reports' tab. In the top left it should state your 'Vendor #'.")
                    }

                    TextField(String(localized: "XXXXXXXX", bundle: #bundle), text: $vendor)
                        .modifier(TextFieldStyle(borderColor: errorFields.contains(.vendor) ? .red : nil))
                }
            }
            .scenePadding()
        }
        .navigationTitle(Text("Sign In to App Store Connect", bundle: #bundle))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .alert(alert?.title ?? "", item: $alert) { alertType in
            Button(alertType.confirmLabel) { }
        } message: { alertType in
            Text(alertType.message)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel", bundle: #bundle)) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Sign In", bundle: #bundle)) {
                    if name.isEmpty || issuerID.isEmpty || keyID.isEmpty || key.isEmpty || vendor.isEmpty {
                        errorFields.removeAll()
                        if name.isEmpty { errorFields.insert(.name) }
                        if issuerID.isEmpty { errorFields.insert(.issuerID) }
                        if key.isEmpty { errorFields.insert(.key) }
                        if keyID.isEmpty { errorFields.insert(.keyID) }
                        if vendor.isEmpty { errorFields.insert(.vendor) }
                        if key.isEmpty { errorFields.insert(.key) }
                    } else {
                        onFinishPressed()
                    }
                }
                .disabled(name.isEmpty || issuerID.isEmpty || keyID.isEmpty || key.isEmpty || vendor.isEmpty)
                .onChange(of: name + issuerID + keyID + key + vendor) { errorFields.removeAll() }
            }
        }
    }

    private func onFinishPressed() {
        let apiKey = Account(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
            vendorNumber: vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if accountManager.getApiKey(apiKeyId: apiKey.id) != nil {
            alert = .duplicateKey
            return
        }
        
        if accountManager.accounts.contains(where: { $0.name == name }) {
            alert = .duplicateName
            return
        }

        Task(priority: .userInitiated) {
            do {
                try await apiKey.checkKey()
                try accountManager.addApiKey(apiKey: apiKey)
                finishOnboarding()
                let api = AppStoreConnectAPI(apiKey: apiKey)
                _ = try? await api.getData(useCache: true, useMemoization: false)
            } catch let err {
                let apiErr = APIError(err)
                if apiErr == .invalidCredentials {
                    alert = .invalidKey
                }
            }
        }
    }

    private func finishOnboarding() {
        dismiss()
    }

    private enum OnboardingSection: Identifiable {
        case naming, key

        public var id: Self { self }
    }

    // MARK: Alert
    private enum AddAPIKeyAlert {
        case invalidKey
        case duplicateKey
        case duplicateName

        public var title: String {
            switch self {
            case .invalidKey: String(localized: "Invalid Account", bundle: #bundle)
            case .duplicateKey: String(localized: "Duplicate Account", bundle: #bundle)
            case .duplicateName: String(localized: "Duplicate Name", bundle: #bundle)
            }
        }
        public var message: String {
            switch self {
            case .invalidKey: String(localized: "Some or all of the information entered is incorrect.", bundle: #bundle)
            case .duplicateKey: String(localized: "These credentials have already been added.", bundle: #bundle)
            case .duplicateName: String(localized: "Choose a unique name.", bundle: #bundle)
            }
        }
        public var confirmLabel: String {
            switch self {
            case .duplicateKey: String(localized: "Check Again", bundle: #bundle)
            default: String(localized: "OK", bundle: #bundle)
            }
        }
    }

    public func infoCard(title: LocalizedStringKey) -> some View {
        DisclosureGroup {
            Text(title, bundle: #bundle).frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(String(localized: "How to find it", bundle: #bundle), systemImage: "questionmark.circle")
        }
    }

    private struct TextFieldStyle: ViewModifier {
        public init(borderColor: Color? = nil, borderWidth: CGFloat = 1, cornerRadius: CGFloat = 5) {
            #if canImport(UIKit)
            self.borderColor = borderColor ?? Color(UIColor.systemGray5)
            #else
            self.borderColor = borderColor ?? Color(NSColor.systemGray)
            #endif
            self.borderWidth = borderWidth
            self.cornerRadius = cornerRadius
        }

        public let borderColor: Color
        public let borderWidth: CGFloat
        public let cornerRadius: CGFloat

        public func body(content: Content) -> some View {
            content
                .buttonStyle(.plain)
                .padding(5)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(borderColor, lineWidth: borderWidth))
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
        }
    }

    public enum Fields {
        case name, issuerID, keyID, key, vendor
    }
}

#Preview {
    NewAccountView()
        .preferredColorScheme(.dark)
}
#endif
