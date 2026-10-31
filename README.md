# AppSalesKit

App Store Connect sales, App Store analytics, reviews, Google Analytics webpage views, and AdMob
earnings — the model and the views — for any of 256 Arts' apps. Extracted from
[App Sales](https://github.com/256Arts/App-Sales).

iOS, macOS, and visionOS 27; watchOS 26 (model only — the views are `#if !os(watchOS)`).

## What's in it

- **Model** — `Account` / `AccountManager` (synchronizable Keychain), `AppStoreConnectAPI` (daily
  sales reports, cached in the App Group), `AnalyticsReportsAPI`, `CustomerReviewsAPI`,
  `GoogleAnalytics`, `AdMob`, and `SalesDataLoader`, the `@Observable` every view reads from.
- **Summary sections** (each a `List` `Section`, empty until the sales load) —
  `SalesSummarySection` (figures + chart), `SharePiesSection`, `FunnelSection`, `InsightsView`.
- **Apps** — `AppDetailView` (pass `AppReviewsSection` as its `reviews` to show them),
  `AppReviewsSection`, `AppRow`, `AppListOptions`.
- **Accounts** — `AccountsList` (App Store Connect, Google Analytics, AdMob, and AIUsageKit's
  Claude/Codex sign-ins).
- `AppSalesKitPackage`, for the host's App Intents metadata (`Account` is an `AppEntity`, `InfoType`
  an `AppEnum`).

## Adopting it

1. Add the package; link `AppSalesKit` to the app and each widget extension.
2. Every one of those targets' Info.plist:
   ```xml
   <key>AppSalesKit</key>
   <dict>
       <key>AppGroup</key>
       <string>group.com.example.app</string>
       <key>KeychainService</key>
       <string>com.example.app</string>
       <key>GoogleClientID</key>
       <string>….apps.googleusercontent.com</string>
   </dict>
   ```
   The targets need that App Group and a shared Keychain access group. `GoogleClientID` is an
   iOS-type OAuth client; register its reversed ID as a URL scheme. Leave it out to hide Google
   Analytics and AdMob.
3. Include `AppSalesKitPackage.self` in each target's `AppIntentsPackage.includedPackages`.
4. Hold one loader and keep it fetching:
   ```swift
   @State private var loader = SalesDataLoader()

   List {
       SalesSummarySection(loader: loader)
       SharePiesSection(loader: loader)
       FunnelSection(loader: loader)
       InsightsView(loader: loader)
   }
   .refreshable { await loader.refresh() }
   .loadsSales(loader, account: AccountManager.shared.accounts.first)

   AppDetailView(app: app, loader: loader) {
       AppReviewsSection(account: loader.account, appleID: app.appleID)
   }

   NavigationStack { AccountsList() }   // in a sheet
   ```
   The account the reader picks in `AccountsList` is stored under `UserDefaults.Key.homeSelectedKey`
   in `UserDefaults.shared`.

A `-screenshotMode` launch argument serves demo accounts and `ACData.example`, and stays off the
Keychain (`ScreenshotMode`).
