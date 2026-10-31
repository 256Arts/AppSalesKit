#if !os(watchOS)
import SwiftUI

/// An app's ratings and written reviews from App Store Connect: the average and a bar per star
/// rating, then the latest few. A `Section`, for a `List`; pass it to `AppDetailView` as its
/// `reviews`. Reading reviews needs a key with the Customer Support role or above, and says so
/// otherwise.
public struct AppReviewsSection: View {

    /// The account whose reviews are read; nothing is shown without one.
    let account: Account?
    let appleID: String

    public init(account: Account?, appleID: String) {
        self.account = account
        self.appleID = appleID
    }

    @State private var reviews: CustomerReviewsAvailability?
    @State private var reviewsError: String?

    public var body: some View {
        if account != nil {
            Section {
                switch reviews {
                case .ready(let reviews) where reviews.total == 0:
                    Text("No one has written a review yet.", bundle: #bundle)
                        .foregroundStyle(.secondary)
                case .ready(let reviews):
                    RatingsSummary(reviews: reviews)
                    ForEach(reviews.recent) { review in
                        ReviewRow(review: review)
                    }
                case .needsCustomerSupportKey:
                    Text("Reading reviews needs an API key with the Customer Support role, or one above it such as App Manager or Admin.", bundle: #bundle)
                        .foregroundStyle(.secondary)
                case nil:
                    if let reviewsError {
                        Text(reviewsError)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            } header: {
                Text("Ratings and Reviews", bundle: #bundle)
            } footer: {
                if case .ready(let reviews) = reviews, reviews.total > 0 {
                    Text("Written reviews from every country. Ratings left without a review are not included.", bundle: #bundle)
                }
            }
            .task(id: [account?.id, appleID]) {
                await loadReviews()
            }
        }
    }

    /// Shows the last fetch at once, then replaces it if it has gone stale.
    private func loadReviews() async {
        reviews = nil
        reviewsError = nil
        guard let account else { return }
        let api = CustomerReviewsAPI(account: account)
        if let cached = api.cached(appleID: appleID) {
            reviews = .ready(cached)
        }
        do {
            reviews = try await api.getReviews(appleID: appleID)
            reviewsError = nil
        } catch {
            reviewsError = error.localizedDescription
        }
    }
}

/// The average, and a bar per star rating showing its share, the way the App Store draws them.
private struct RatingsSummary: View {

    public let reviews: CustomerReviews

    public var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 0) {
                Text(reviews.average ?? 0, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Text("out of 5", bundle: #bundle)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .trailing, spacing: 3) {
                ForEach((1...5).reversed(), id: \.self) { stars in
                    HStack(spacing: 6) {
                        StarRating(rating: stars, showsEmptyStars: false)
                            .font(.system(size: 7))
                            .frame(width: 44, alignment: .trailing)
                        ProgressView(value: Double(reviews.count(stars: stars)), total: Double(max(reviews.total, 1)))
                            .tint(.secondary)
                    }
                }
                Text("^[\(reviews.total) Review](inflect: true)", bundle: #bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(reviews.average ?? 0, format: .number.precision(.fractionLength(1))) out of 5, from ^[\(reviews.total) review](inflect: true)", bundle: #bundle))
    }
}

private struct ReviewRow: View {

    public let review: CustomerReviews.Review

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StarRating(rating: review.rating)
                    .font(.caption)
                Spacer()
                if let date = review.date {
                    Text(date, format: .dateTime.month().day().year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let title = review.title, !title.isEmpty {
                Text(title)
                    .bold()
            }
            if let body = review.body, !body.isEmpty {
                Text(body)
            }
            let byline = [review.nickname, review.territoryName].compactMap(\.self).filter { !$0.isEmpty }
            if !byline.isEmpty {
                Text(byline.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct StarRating: View {

    public let rating: Int
    public var showsEmptyStars = true

    public var body: some View {
        HStack(spacing: 1) {
            ForEach(1...(showsEmptyStars ? 5 : rating), id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
            }
        }
        .foregroundStyle(.orange)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(rating) out of 5 stars", bundle: #bundle))
    }
}

#Preview {
    List {
        AppReviewsSection(account: .demoAccount, appleID: "1")
    }
}
#endif
