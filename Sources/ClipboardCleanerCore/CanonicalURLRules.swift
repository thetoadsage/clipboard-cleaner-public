import Foundation

/// Explicit, opt-in "canonical form" rules for a small set of well-known,
/// heavily-parameterized product pages.
///
/// Unlike `TrackingRuleCatalog` (which removes known-bad parameter names
/// and leaves everything else untouched), these rules rewrite the URL to a
/// minimal canonical form -- but only when the host *and* path confidently
/// match an expected, well-documented shape for that specific site. If a
/// URL doesn't match, no rule applies here at all, and it falls straight
/// through to the tracking-parameter blocklist unchanged. There is no
/// generic "strip all query parameters" rule -- every entry below is scoped
/// to one specific site and one specific path shape.
///
/// This behavior is independently implemented from published, observable
/// URL structures (e.g. Amazon ASINs, Best Buy/Walmart product IDs). It is
/// not derived from, or copied out of, any third-party tool.
enum CanonicalURLRules {

    private struct Rule {
        let matchesHost: (String) -> Bool
        /// Matched against `url.path`. Capture group 1 must be the
        /// canonical product identifier.
        let pathPattern: NSRegularExpression
        let canonicalPath: (String) -> String
    }

    // Immutable after initialization; the compiler can't prove function
    // values are Sendable, but there's no shared mutable state here.
    nonisolated(unsafe) private static let rules: [Rule] = [
        // AliExpress product pages: the numeric item id in the path already
        // fully identifies the product; every observed query parameter
        // (scm*, pvid, sourceType, pdp_ext_f, aecmd, gatewayAdapt, ...) is
        // session/analytics noise.
        // https://www.aliexpress.us/item/3256812635547747.html?... -> https://www.aliexpress.us/item/3256812635547747.html
        Rule(
            matchesHost: {
                HostMatching.matches(host: $0, reviewedDomains: HostMatching.aliExpressOwnedDomains)
            },
            pathPattern: regex("^/item/(\\d+)\\.html$"),
            canonicalPath: { "/item/\($0).html" }
        ),

        // Amazon product pages: the ASIN (10-char alphanumeric id) after
        // /dp/, /gp/product/, or /d/ is the stable, canonical identifier;
        // the descriptive title slug and everything in the query string
        // (ref=, tracking ids, search context) are not needed to load the
        // product.
        // https://www.amazon.com/Some-Title/dp/B08XYZ1234/ref=sr_1_3?... -> https://www.amazon.com/dp/B08XYZ1234
        Rule(
            matchesHost: {
                HostMatching.matches(host: $0, reviewedDomains: HostMatching.amazonOwnedDomains)
            },
            pathPattern: regex("/(?:dp|gp/product|d)/([A-Z0-9]{10})(?:/|$)"),
            canonicalPath: { "/dp/\($0)" }
        ),

        // Best Buy product pages: ".../site/<slug>/<skuId>.p" (slug is
        // optional on Best Buy's own short-link form) -> "/site/<skuId>.p".
        Rule(
            matchesHost: { HostMatching.matches(host: $0, domain: "bestbuy.com") },
            pathPattern: regex("^/site/(?:.+/)?(\\d+)\\.p$"),
            canonicalPath: { "/site/\($0).p" }
        ),

        // Walmart product pages: ".../ip/<slug>/<id>" (slug optional) -> "/ip/<id>".
        Rule(
            matchesHost: { HostMatching.matches(host: $0, domain: "walmart.com") },
            pathPattern: regex("^/ip/(?:.+/)?(\\d+)$"),
            canonicalPath: { "/ip/\($0)" }
        ),

        // MakerWorld model pages: "/<locale>/models/<id>-<slug>" (the locale
        // segment and the trailing "-<slug>" are both optional). The numeric
        // model id plus its slug already fully identify the page; the only
        // things observed on these URLs beyond that are share/analytics noise
        // in the query string (e.g. ?from=search) and a fragment selecting a
        // sub-view (e.g. #profileId-...). Unlike the id-only rules above,
        // MakerWorld's own canonical form keeps the whole model path -- so
        // capture group 1 is the entire matched path and we return it
        // verbatim; canonicalize() then drops the query and fragment by
        // construction. A trailing slash, if present, is normalized away.
        // https://makerworld.com/en/models/1085885-climbing-plant-clip?from=search#profileId-2763032
        //   -> https://makerworld.com/en/models/1085885-climbing-plant-clip
        Rule(
            matchesHost: { HostMatching.matches(host: $0, domain: "makerworld.com") },
            pathPattern: regex("^(/(?:[a-z]{2}(?:-[a-z]{2})?/)?models/\\d+(?:-[^/]*)?)/?$"),
            canonicalPath: { $0 }
        ),
    ]

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // These patterns are fixed string literals defined above; a failed
        // compile here would be a programmer error caught immediately by
        // the test suite, not a runtime possibility worth guarding against.
        try! NSRegularExpression(pattern: pattern)
    }

    /// Returns a rewritten canonical URL string (scheme + original host +
    /// canonical path, no query, no fragment) if a rule confidently matches
    /// `url`; otherwise nil, meaning the caller should fall through to
    /// normal tracking-parameter cleaning.
    static func canonicalize(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        let pathRange = NSRange(path.startIndex..<path.endIndex, in: path)

        for rule in rules where rule.matchesHost(host) {
            guard let match = rule.pathPattern.firstMatch(in: path, options: [], range: pathRange),
                match.numberOfRanges > 1,
                let idRange = Range(match.range(at: 1), in: path)
            else {
                continue
            }

            var components = URLComponents()
            components.scheme = url.scheme
            components.host = url.host
            components.path = rule.canonicalPath(String(path[idRange]))
            return components.string
        }

        return nil
    }
}
