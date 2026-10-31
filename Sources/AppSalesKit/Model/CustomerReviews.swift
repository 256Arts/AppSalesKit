import Foundation
import AppStoreConnect_Swift_SDK

/// An app's written reviews: how many there are at each star rating, and the latest few.
///
/// App Store Connect's API has only written reviews, so the average is of those — star-only
/// ratings, which the App Store's own average includes, are not counted.
public struct CustomerReviews: Codable {

    public struct Review: Codable, Identifiable {
        public let id: String
        public let rating: Int
        public let title: String?
        public let body: String?
        public let nickname: String?
        public let date: Date?
        /// ISO 3166-1 alpha-3, as App Store Connect sends it.
        public let territory: String?

        public var territoryName: String? {
            territory.flatMap { Locale.current.localizedString(forRegionCode: $0) }
        }
    }

    /// Reviews by star rating: the first is one star, the last five.
    public let counts: [Int]
    /// Newest first.
    public let recent: [Review]
    public let fetched: Date

    public var total: Int { counts.reduce(0, +) }

    public var average: Double? {
        guard total > 0 else { return nil }

        return Double(counts.enumerated().reduce(0) { $0 + ($1.offset + 1) * $1.element }) / Double(total)
    }

    public func count(stars: Int) -> Int {
        counts.indices.contains(stars - 1) ? counts[stars - 1] : 0
    }
}

/// What App Store Connect could give back for an app's reviews.
public enum CustomerReviewsAvailability {
    case ready(CustomerReviews)
    /// Reading reviews needs the Customer Support role, or one above it.
    case needsCustomerSupportKey
}

/// Fetches an app's customer reviews from App Store Connect.
public final class CustomerReviewsAPI {

    /// How long a fetch is shown before it is fetched again.
    public static let freshness: TimeInterval = 60 * 60

    private let account: Account

    public init(account: Account) {
        self.account = account
    }

    /// The last fetch for the app, however old, to show while a new one loads.
    public func cached(appleID: String) -> CustomerReviews? {
        account.isDemo ? .example(appleID: appleID) : CustomerReviewsCache.reviews(account: account, appleID: appleID)
    }

    public func getReviews(appleID: String) async throws -> CustomerReviewsAvailability {
        if account.isDemo { return .ready(.example(appleID: appleID)) }
        if let cached = cached(appleID: appleID), cached.fetched.timeIntervalSinceNow > -Self.freshness {
            return .ready(cached)
        }

        do {
            let reviews = try await fetch(appleID: appleID)
            CustomerReviewsCache.save(reviews, account: account, appleID: appleID)
            return .ready(reviews)
        } catch let error where APIError(error) == .wrongPermissions {
            return .needsCustomerSupportKey
        } catch {
            throw APIError(error)
        }
    }

    /// One request for the latest reviews, and one per star rating for its count, which comes back
    /// as the paging total of a single-review page.
    private func fetch(appleID: String) async throws -> CustomerReviews {
        let provider = try account.apiProvider()
        let endpoint = APIEndpoint.v1.apps.id(appleID).customerReviews
        let fields: [APIEndpoint.V1.Apps.WithID.CustomerReviews.GetParameters.FieldsCustomerReviews] = [.rating, .title, .body, .reviewerNickname, .createdDate, .territory]

        async let latest = provider.request(endpoint.get(parameters: .init(sort: [.minuscreatedDate], fieldsCustomerReviews: fields, limit: 10)))
        let counts = try await withThrowingTaskGroup(of: (stars: Int, count: Int).self) { group in
            for stars in 1...5 {
                group.addTask {
                    let page = try await provider.request(endpoint.get(parameters: .init(filterRating: [String(stars)], fieldsCustomerReviews: [.rating], limit: 1)))
                    return (stars, page.meta?.paging.total ?? page.data.count)
                }
            }
            return try await group.reduce(into: Array(repeating: 0, count: 5)) { $0[$1.stars - 1] = $1.count }
        }

        let recent = try await latest.data.compactMap { review -> CustomerReviews.Review? in
            guard let attributes = review.attributes, let rating = attributes.rating else { return nil }
            return CustomerReviews.Review(
                id: review.id,
                rating: rating,
                title: attributes.title,
                body: attributes.body,
                nickname: attributes.reviewerNickname,
                date: attributes.createdDate,
                territory: attributes.territory?.rawValue)
        }
        return CustomerReviews(counts: counts, recent: recent, fetched: .now)
    }
}

// MARK: - Cache

/// The last fetch per app, per account, in the App Group container beside the sales cache.
public enum CustomerReviewsCache {

    private typealias Storage = [String: [String: CustomerReviews]]

    private static var url: URL? {
        AppSalesKit.containerURL?.appending(path: "reviews-cache.json")
    }

    private static let lock = NSLock()

    public static func reviews(account: Account, appleID: String) -> CustomerReviews? {
        lock.withLock { load()[account.id]?[appleID] }
    }

    public static func save(_ reviews: CustomerReviews, account: Account, appleID: String) {
        lock.withLock {
            var storage = load()
            storage[account.id, default: [:]][appleID] = reviews
            write(storage)
        }
    }

    public static func clear(account: Account) {
        lock.withLock {
            var storage = load()
            storage[account.id] = nil
            write(storage)
        }
    }

    private static func load() -> Storage {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }

        return (try? JSONDecoder().decode(Storage.self, from: data)) ?? [:]
    }

    private static func write(_ storage: Storage) {
        guard let url, let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: url)
    }
}

// MARK: - Demo

extension CustomerReviews {

    /// Reviews for the demo account's apps, the same few for each, with counts varied by app.
    public static func example(appleID: String) -> CustomerReviews {
        // Not `hashValue`, which changes every launch and would change the screenshots with it.
        let seed = appleID.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 40
        let calendar = Calendar.autoupdatingCurrent
        func daysAgo(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: -days, to: .now) }

        return CustomerReviews(
            counts: [3, 2, 6, 24 + seed / 2, 118 + seed * 3],
            recent: [
                Review(id: "demo-1", rating: 5, title: String(localized: "Exactly what I needed", bundle: #bundle), body: String(localized: "Simple, fast, and it does one thing really well. The widgets are a lovely touch.", bundle: #bundle), nickname: "Maple Toast", date: daysAgo(1), territory: "USA"),
                Review(id: "demo-2", rating: 5, title: String(localized: "Beautifully designed", bundle: #bundle), body: String(localized: "Feels right at home on my iPhone and iPad. Worth every penny.", bundle: #bundle), nickname: "kiwi_kat", date: daysAgo(3), territory: "NZL"),
                Review(id: "demo-3", rating: 4, title: String(localized: "Great, one request", bundle: #bundle), body: String(localized: "Love it so far. Would be perfect with an option to export my data.", bundle: #bundle), nickname: "Lukas R.", date: daysAgo(6), territory: "DEU"),
                Review(id: "demo-4", rating: 2, title: String(localized: "Crashes on launch", bundle: #bundle), body: String(localized: "Since the last update it closes right after opening. Please fix!", bundle: #bundle), nickname: "sam", date: daysAgo(12), territory: "GBR")
            ],
            fetched: .now)
    }
}
