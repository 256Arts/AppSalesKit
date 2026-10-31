# AppSalesKit

App Store Connect sales/analytics/reviews model and views for 256 Arts apps. README.md has the
feature rundown and adoption steps. Host: App Sales (`Repos/App Sales`).

## Build

Swift package, no Xcode project. Platforms: iOS / macOS / visionOS 27, watchOS 26. Swift language
mode 5. No unit tests. Verify:
`xcodebuild -scheme AppSalesKit -destination generic/platform=<macOS|iOS|watchOS|visionOS> build`.

## Conventions

- Configuration comes from the host's Info.plist `AppSalesKit` dict (`AppSalesKit.swift`), never code:
  widget timelines and intents run before any host code.
- Every user-facing string takes `bundle: #bundle` (SwiftUI title inits use the
  `String(localized:bundle:)` overload); strings live in `Resources/Localizable.xcstrings`. App
  Intents metadata strings resolve against the host's main bundle.
- `Views/` files are `#if !os(watchOS)` except `AppIconView` and `PercentChange`; `Model/` stays
  watchOS-clean.
- Views read a `SalesDataLoader`; fetching logic belongs in it, not in a view.
- Keychain keys, cache file names, and defaults keys are persisted — renaming them signs readers out
  or drops their caches.

## Model (`Model/`)

- `Account` — credentials for one App Store Connect API key (issuerID, privateKeyID, privateKey, vendorNumber). `id` is the privateKeyID. Also conforms to `AppEntity` so the widget configuration intent can pick an account. `Account.demoAccount` short-circuits the whole pipeline to return `ACData.example` mock data.
- `AccountManager` — `@Observable` singleton (`AccountManager.shared`) that persists `[Account]` in the **Keychain** (service from the `AppSalesKit` Info.plist dict, iCloud-synchronizable), *not* UserDefaults despite some method-name wording. The host injects it with `.environment(...)`; the package's views read `.shared`. Mutations call `WidgetCenter.reloadAllTimelines()`.
- `AppStoreConnectAPI` — the core fetcher. `getData(...)` is the entry point. It uses `AvdLee/appstoreconnect-swift-sdk` (4.x; `Account.apiProvider()` builds the client and `APIError.init(_:)` maps its failures, shared with `AnalyticsReportsAPI`) to download **daily SALES summary reports** (one request per missing day, gzipped TSV), gunzips them (`GzipSwift`), parses the TSV (`SwiftCSV`) into `[Event]`, converts currency, then enriches with app metadata via the public **iTunes lookup API** (`itunes.apple.com/lookup`). Has two layers of caching: in-memory memoization (`lastData`, 5-min TTL, keyed by `Account`) and on-disk cache via `ACDataCache`. HTTP status codes map to `APIError` cases (401→invalidCredentials, 429→exceededLimit, 403→wrongPermissions, 404 with no results→noDataAvailable).
- `ACData` — the parsed dataset: `[Event]` + `[ACApp]` + a `displayCurrency`. All the aggregation/analytics logic lives here as `getRawData`/`getDevices`/`getChange`/`getPerformanceSummary`/`getAppSummaries`, sliced by `InfoType` (`.proceeds`, `.downloads`, `.updates`, `.iap`). Currency conversion is non-destructive via `changeCurrency(to:)`.
- `ACDataCache` — JSON file (`cache.json`) in the **App Group container** (`AppSalesKit.appGroupID`), which is how the app and widget share fetched data. Merges new entries with cached ones and prunes to the last ~35 days.
- `AnalyticsReportsAPI` — App Store impressions, page views, sessions, and active devices from the Analytics Reports API. Asynchronous: the first fetch per app creates an `ONGOING` report request (Admin keys only) and reports arrive a day or two later; summarized daily instances are cached in `analytics-cache.json` (`AnalyticsCache`), each day taken from its latest instance. `AppStoreAnalytics` is the result; `AppStoreAnalyticsSection` (main app only) shows it on the home screen and hands it up to `HomeView`, whose app rows show and sort by each app's product page views.
- `GoogleAnalytics` — `@Observable` singleton for the optional Google Analytics 4 link: OAuth (PKCE, iOS-type client, no secret), any number of Google sign-ins (a work site often sits behind a managed account) each with its chosen properties (`websites`), and any page URLs the reader set by hand, all in the synchronizable Keychain (key `google-analytics`). `traffic(for:)` runs one all-pages report per chosen website, pools them, and returns each app's 30-day page views, from its set URL or else the most-viewed page whose last path component slugs to the app's name (`/spritepencil` → Sprite Pencil); the app rows (`AppRow`) show them first, with a globe icon, and their context menu opens the `websitePageEditor` override. Nothing else is shown on the home screen — connecting, picking websites, and disconnecting live in `AccountsList`, whose one Accounts section lists every sign-in (long-press or swipe to sign out) above a single Add Account menu. Its OAuth (one client, a PKCE sign-in per service, `GoogleAccount` named by its ID token's email) and `GoogleAccessTokens` live in `GoogleSignIn`. **Every Google service is hidden while `GoogleSignIn.clientID` is empty.**
- `AdMob` — the optional AdMob link, one sign-in per publisher account (any number), signed in separately (`admob.readonly`, Keychain key `admob`) from `AccountsList`. `earnings()` runs one network report (date × app × country, USD) per distinct publisher, cached an hour in `admob-cache.json`; `AppStoreConnectAPI.getDataFromAPI` appends them as `.ad` `Event`s *after* `ACDataCache.saveData` and the app lookup, matched by the AdMob app's linked App Store ID or else its name, so every proceeds figure includes ads. `latestReportingDate()` ignores `.ad` events, since ads report same-day.
- `Event` — one row of a sales report. `ACApp` — app metadata + icon caching. `CurrencyConverter` — exchange-rate fetch/convert. `PerformanceSummary` — the 30-day-vs-prior-30-day rollup the widget displays.
- `SalesDataLoader` — the `@Observable` every view reads: sales, summary, App Store analytics, webpage traffic, `appCounts`, `funnel`; `.loadsSales(_:account:)` keeps it fetching.
