#if !os(watchOS)
import SwiftUI

extension View {
    /// Asks for the web address of the page about `app`, whose views its row in the home screen's app
    /// list counts. Attach it outside the `List`: an alert inside one is handed to every row, and none
    /// of them present it.
    public func websitePageEditor(for app: Binding<AppPerformanceSummary?>, currentURL: URL?) -> some View {
        modifier(WebsitePageEditor(app: app, currentURL: currentURL))
    }
}

private struct WebsitePageEditor: ViewModifier {

    @Binding var app: AppPerformanceSummary?
    public let currentURL: URL?

    @State private var pageURLText = ""

    public func body(content: Content) -> some View {
        content
            .alert(String(localized: "Website Page", bundle: #bundle), isPresented: Binding(get: { app != nil }, set: { if !$0 { app = nil } }), presenting: app) { app in
                TextField(String(localized: "https://example.com/app", bundle: #bundle), text: $pageURLText)
                    .textContentType(.URL)
                    #if canImport(UIKit)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                Button(String(localized: "Save", bundle: #bundle)) {
                    GoogleAnalytics.shared.setPageURL(pageURL, for: app.appleID)
                }
                Button(String(localized: "Cancel", bundle: #bundle), role: .cancel) { }
            } message: { app in
                Text("The page about \(app.name) on your website. Leave it empty to find the page by the app's name.", bundle: #bundle)
            }
            .onChange(of: app?.appleID) {
                pageURLText = currentURL?.absoluteString ?? ""
            }
    }

    /// Typed without a scheme reads as a web address rather than a relative path.
    private var pageURL: URL? {
        let text = pageURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return URL(string: text.contains("://") ? text : "https://" + text)
    }
}
#endif
