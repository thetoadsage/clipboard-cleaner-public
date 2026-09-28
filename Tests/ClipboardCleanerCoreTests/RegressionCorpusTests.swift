import Testing

@testable import ClipboardCleanerCore

/// A compact, curated corpus of representative real-world URLs run through
/// the full three-layer cleaning pipeline (`URLCleaner.clean`). This is
/// deliberately not exhaustive -- the detailed per-site/per-layer behavior
/// is already covered by `URLCleanerTests`, `SecurityRegressionTests`, etc.
/// This file exists purely as a broad, at-a-glance regression net: one line
/// per notable platform/shape, so a future change that quietly breaks one
/// of them fails loudly and specifically here.
struct RegressionCorpusTests {

    @Test(
        arguments: [
            // Generic utm_*/gclid/fbclid/msclkid stack -- global rules only,
            // no site-specific behavior involved.
            (
                "generic utm + click-id stack",
                "https://example.com/article?utm_source=twitter&utm_medium=social&utm_campaign=launch&gclid=abc123&fbclid=xyz789&msclkid=qrs456",
                "https://example.com/article"
            ),

            // YouTube's `si` share token is domain-scoped; `v` (the video
            // id) must survive.
            (
                "YouTube si",
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=AbCdEfGhIjKlMnOp",
                "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
            ),

            // Amazon affiliate/session noise on a non-product-page path (so
            // this exercises the blocklist layer, not the /dp/ canonical
            // rule) -- the search keyword `k` must survive.
            (
                "Amazon affiliate parameters",
                "https://www.amazon.com/s?k=running-shoes&ref=sr_pg_1&linkCode=ll2&ascsubtag=xyz789",
                "https://www.amazon.com/s?k=running-shoes"
            ),

            // Instagram's `igsh` share token.
            (
                "Instagram igsh",
                "https://www.instagram.com/reel/Cxyz123AbCd/?igsh=abc123XYZ",
                "https://www.instagram.com/reel/Cxyz123AbCd/"
            ),

            // TikTok's share/session parameters.
            (
                "TikTok tracking parameters",
                "https://www.tiktok.com/@someuser/video/7123456789012345678?_t=abc123&_r=1&share_app_name=copy&user_id=99887766",
                "https://www.tiktok.com/@someuser/video/7123456789012345678"
            ),

            // Reddit share/attribution parameters -- `context` (a real
            // Reddit comment-thread depth parameter) must survive.
            (
                "Reddit share/tracking parameters",
                "https://www.reddit.com/r/apple/comments/1abcde2/interesting_post/?utm_source=share&utm_medium=ios_app&context=3&rdt=12345",
                "https://www.reddit.com/r/apple/comments/1abcde2/interesting_post/?context=3"
            ),

            // X/Twitter's `s`/`t` share parameters.
            (
                "X/Twitter tracking parameters",
                "https://twitter.com/someuser/status/1234567890123456789?s=20&t=abcDEF123",
                "https://twitter.com/someuser/status/1234567890123456789"
            ),

            // eBay affiliate/session parameters -- no eBay canonical rule
            // exists, so this exercises the blocklist layer only.
            (
                "eBay affiliate/tracking parameters",
                "https://www.ebay.com/itm/123456789012?_trkparms=ao%3A1%7Camid%3A1&_trksid=p2349624.c101224&hash=item1c2d3e4f5g",
                "https://www.ebay.com/itm/123456789012"
            ),

            // Mixed #1: generic e-commerce page -- utm_* stripped, `id` and
            // `category` (ordinary product-page identifiers) survive.
            (
                "mixed tracking + legitimate params (generic e-commerce)",
                "https://shop.example.com/products/wireless-mouse?id=8842&utm_source=newsletter&utm_medium=email&category=electronics",
                "https://shop.example.com/products/wireless-mouse?id=8842&category=electronics"
            ),

            // Mixed #2: Google search results -- ei/ved/gs_lcp (Google's own
            // session/experiment parameters) stripped, `q` survives.
            (
                "mixed tracking + legitimate params (Google search)",
                "https://www.google.com/search?q=best-laptops-2024&ei=abc123XYZ&ved=2ahUKEwj0i8jGqL6AAxUJAAAAABQAAAAQ&gs_lcp=Cgdnd3Mtd2l6EAM",
                "https://www.google.com/search?q=best-laptops-2024"
            ),

            // Legitimate-only #1: a bare search query with nothing else --
            // must be returned completely unchanged.
            (
                "legitimate-only: search query",
                "https://www.google.com/search?q=swift-concurrency",
                "https://www.google.com/search?q=swift-concurrency"
            ),

            // Legitimate-only #2: ordinary listing/filter parameters.
            (
                "legitimate-only: category/sort/page",
                "https://example.com/products?category=shoes&sort=price_asc&page=2",
                "https://example.com/products?category=shoes&sort=price_asc&page=2"
            ),

            // Legitimate-only #3: short, easily-confused-for-tracking names
            // (`v`, `t`, `id`) that are not tracking parameters on a generic
            // domain.
            (
                "legitimate-only: v/t/id",
                "https://example.com/video?v=abc123&t=42&id=99",
                "https://example.com/video?v=abc123&t=42&id=99"
            ),

            // Z-Library's dsource parameter is site-specific share/source
            // noise and must not be treated as a global tracking parameter.
            (
                "Z-Library dsource",
                "https://z-lib.gd/book/wrmdOZlaPv/the-odyssey.html?dsource=mostpopular",
                "https://z-lib.gd/book/wrmdOZlaPv/the-odyssey.html"
            ),
        ]
    )
    func regressionCorpus(label: String, input: String, expected: String) {
        #expect(URLCleaner.clean(input) == expected, "\(label)")
    }

    @Test func zLibraryDsourceRuleIsDomainScoped() {
        let unrelated = "https://example.com/book?dsource=mostpopular"
        #expect(URLCleaner.clean(unrelated) == unrelated)
    }

    // MARK: - Embedded redirects

    @Test func redirectCorpusFacebookWrapperAroundATrackedDestination() {
        // Facebook's l.php wrapper unwraps to its destination, which itself
        // still carries utm_* noise that the blocklist then strips.
        let destination = "https://example.com/article?utm_source=facebook&utm_medium=share"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://l.facebook.com/l.php?u=\(encoded)&h=AT123abc"

        #expect(URLCleaner.clean(input) == "https://example.com/article")
    }

    @Test func redirectCorpusGoogleWrapperAroundAnAlreadyCleanDestination() {
        // Google's /url wrapper unwraps to an already-clean destination --
        // nothing left for the blocklist to do afterward.
        let destination = "https://example.com/page"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://www.google.com/url?q=\(encoded)&sa=t&ved=2ahUKEwj"

        #expect(URLCleaner.clean(input) == "https://example.com/page")
    }
}
