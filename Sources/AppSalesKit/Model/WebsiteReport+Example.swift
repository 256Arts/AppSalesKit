import Foundation

extension WebsiteReport {

    /// Two made-up websites for the demo account, to go with `ACData.example`. Built as day
    /// offsets from today, like the sales, so they never go stale. Hosts are on the reserved
    /// `.example` domain, so nothing looks them up.
    public static let examples: [WebsiteReport] = [
        example(
            id: "properties/demo-studio", name: "Studio Website", host: "studio.example",
            dailyViews: 140, growth: 1.18,
            countries: ["US": 610, "GB": 140, "CA": 120, "DE": 110, "JP": 90, "AU": 70, "FR": 60, "IN": 55, "BR": 40],
            operatingSystems: ["iOS": 520, "Macintosh": 330, "Windows": 260, "Android": 180, "Linux": 25],
            sources: [
                ("(direct)", "(none)", "Direct", 1_420),
                ("google", "organic", "Organic Search", 980),
                ("chatgpt.com", "ai-assistant", "AI Assistant", 260),
                ("perplexity.ai", "ai-assistant", "AI Assistant", 90),
                ("apps.apple.com", "referral", "Referral", 210),
                ("reddit.com", "referral", "Organic Social", 170),
                ("bing", "organic", "Organic Search", 120),
                ("duckduckgo", "organic", "Organic Search", 80),
                ("news.ycombinator.com", "referral", "Referral", 60),
                ("newsletter", "email", "Email", 45),
                ("mastodon.social", "referral", "Organic Social", 30),
            ],
            pages: [
                ("Studio — Apps for Explorers", 1_310), ("Forest Explorer", 920), ("Sunset Seeker", 540),
                ("Press Kit", 260), ("Support", 210), ("Privacy Policy", 150), ("About", 120), ("Contact", 90),
                ("Forest Explorer — What's New", 80), ("Careers", 40), ("Sunset Seeker — Tips", 30),
            ]),
        example(
            id: "properties/demo-forest", name: "Forest Explorer", host: "forestexplorer.example",
            dailyViews: 75, growth: 1.32,
            countries: ["US": 420, "CA": 110, "GB": 80, "DE": 60, "NL": 40, "SE": 35, "AU": 30],
            operatingSystems: ["iOS": 560, "Macintosh": 120, "Android": 60, "Windows": 50],
            sources: [
                ("google", "organic", "Organic Search", 760),
                ("(direct)", "(none)", "Direct", 520),
                ("chatgpt.com", "ai-assistant", "AI Assistant", 180),
                ("apps.apple.com", "referral", "Referral", 140),
                ("instagram.com", "referral", "Organic Social", 95),
                ("youtube.com", "referral", "Organic Video", 40),
            ],
            pages: [
                ("Forest Explorer — Hike Smarter", 1_020), ("Trail Maps", 480), ("Offline Mode", 260),
                ("Pricing", 190), ("FAQ", 150), ("Changelog", 70),
            ]),
    ]

    private static func example(
        id: String,
        name: String,
        host: String,
        dailyViews: Double,
        growth: Double,
        countries: [String: Int],
        operatingSystems: [String: Int],
        sources: [(String, String, String, Int)],
        pages: [(String, Int)]
    ) -> WebsiteReport {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        // A gentle climb, a weekly rhythm, and some wobble, the same every run.
        let days = (0...30).compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: offset - 30, to: today) else { return nil }
            let trend = 1 + (growth - 1) * Double(offset) / 30
            let weekly = calendar.isDateInWeekend(date) ? 0.72 : 1
            let wobble = 1 + 0.18 * sin(Double(offset) * 1.7 + dailyViews)
            let views = Int(dailyViews * trend * weekly * wobble)
            return Day(date: date, views: views, users: Int(Double(views) * 0.64))
        }
        let views = days.reduce(0) { $0 + $1.views }
        let users = Int(Double(views) * 0.58)
        let sessions = Int(Double(views) * 0.71)
        return WebsiteReport(
            property: GoogleAnalyticsProperty(id: id, name: name, accountName: "Demo"),
            host: host,
            totals: Totals(views: views, users: users, sessions: sessions),
            // Users grow a little slower than views: returning readers read more.
            previousTotals: Totals(views: Int(Double(views) / growth), users: Int(Double(users) / (growth * 0.95)), sessions: Int(Double(sessions) / growth)),
            days: days,
            countries: countries,
            operatingSystems: operatingSystems,
            sources: sources.map { Source(source: $0.0, medium: $0.1, channel: WebsiteChannel(defaultChannelGroup: $0.2), sessions: $0.3) },
            pages: pages.map { Page(title: $0.0, views: $0.1) })
    }
}
