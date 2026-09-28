import Foundation

/// Host-matching helpers shared by `TrackingRuleCatalog`, `CanonicalURLRules`,
/// and `RedirectUnwrapper`.
enum HostMatching {

    /// Domains reviewed for aggressive whole-URL transformations. Unlike
    /// `WildcardBase`, these lists intentionally do not trust a brand name
    /// under an arbitrary registry-controlled suffix.
    static let googleOwnedDomains: Set<String> = [
        "google.com", "google.ca", "google.co.uk", "google.com.au",
        "google.co.nz", "google.co.in", "google.co.jp", "google.de",
        "google.fr", "google.es", "google.it", "google.nl", "google.pl",
        "google.com.br", "google.com.mx",
    ]

    static let amazonOwnedDomains: Set<String> = [
        "amazon.com", "amazon.ca", "amazon.com.mx", "amazon.com.br",
        "amazon.co.uk", "amazon.de", "amazon.fr", "amazon.it", "amazon.es",
        "amazon.nl", "amazon.se", "amazon.pl", "amazon.com.be",
        "amazon.co.jp", "amazon.in", "amazon.com.au", "amazon.sg",
        "amazon.ae", "amazon.sa", "amazon.eg", "amazon.com.tr",
        "amazon.cn", "amazon.ie", "amazon.co.za",
    ]

    static let aliExpressOwnedDomains: Set<String> = [
        "aliexpress.com", "aliexpress.us", "aliexpress.ru",
    ]

    /// True if `host` equals `domain`, or is a subdomain of it
    /// (e.g. "www.example.com" matches domain "example.com").
    static func matches(host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    static func matches(host: String, reviewedDomains: Set<String>) -> Bool {
        reviewedDomains.contains { matches(host: host, domain: $0) }
    }

    /// A base label (e.g. "amazon") with its wildcard-TLD matching regex
    /// compiled once at construction, rather than re-compiling an
    /// `NSRegularExpression` from a pattern string on every match. Matches
    /// `host` against `base` (or a subdomain of it) under any TLD chain of
    /// one or more 2+ letter labels -- e.g. base "amazon" matches
    /// "amazon.com", "www.amazon.co.uk", "smile.amazon.de", etc.
    struct WildcardBase {
        let base: String
        private let regex: NSRegularExpression

        /// Fails only if `base`, once escaped, can't be embedded in a valid
        /// regex -- not expected to happen for any input, but this stays
        /// failable (rather than a forced try) since `base` values loaded
        /// from the bundled rules resource are external data, not fixed
        /// source-code literals, and malformed rule data must never crash
        /// the app.
        init?(_ base: String) {
            let escaped = NSRegularExpression.escapedPattern(for: base)
            let pattern = "^(?:[a-z0-9-]+\\.)*\(escaped)(?:\\.[a-z]{2,}){1,}$"
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else {
                return nil
            }
            self.base = base
            self.regex = compiled
        }

        func matches(host: String) -> Bool {
            let range = NSRange(host.startIndex..<host.endIndex, in: host)
            return regex.firstMatch(in: host, options: [], range: range) != nil
        }
    }
}
