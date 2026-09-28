import Foundation

/// Locally unwraps a small, explicit list of known "wrapper" URLs whose
/// true destination is embedded directly in one of their own query
/// parameters -- as opposed to opaque shorteners (bit.ly, t.co, tinyurl,
/// etc.), whose destination only exists on the shortener's own server and
/// can't be recovered without making an HTTP request. This app never makes
/// network requests, so opaque shorteners are deliberately not handled;
/// only wrappers that carry their destination in plain text are.
enum RedirectUnwrapper {

    /// The result of unwrapping: the final URL string (or the original
    /// input, unchanged, if it wasn't a recognized wrapper), and how many
    /// query parameters were discarded along the way -- every query
    /// parameter on every wrapper hop that got replaced (not just the one
    /// holding the destination), since the wrapper's entire query string is
    /// discarded when it's replaced by its destination.
    struct UnwrapResult {
        let result: String
        let parametersRemoved: Int
    }

    private struct WrapperRule {
        let matchesHost: (String) -> Bool
        let matchesPath: (String) -> Bool
        /// Query parameter names to check, in order; the first one present
        /// with a valid http(s) URL value wins. Empty for wrappers that put
        /// the destination directly in their raw query string.
        let parameterNames: [String]
        let usesRawQueryAsDestination: Bool
    }

    // Immutable after initialization; the compiler can't prove function
    // values are Sendable, but there's no shared mutable state here.
    nonisolated(unsafe) private static let rules: [WrapperRule] = [
        // Facebook share/redirect links: https://l.facebook.com/l.php?u=<destination>&h=...
        WrapperRule(
            matchesHost: { $0 == "l.facebook.com" },
            matchesPath: { $0 == "/l.php" },
            parameterNames: ["u"],
            usesRawQueryAsDestination: false
        ),
        // Google search-result / redirect links:
        // https://www.google.com/url?q=<destination>&sa=...
        // (also seen with `url=` instead of `q=`, e.g. in cache/AMP contexts)
        WrapperRule(
            matchesHost: {
                HostMatching.matches(host: $0, reviewedDomains: HostMatching.googleOwnedDomains)
            },
            matchesPath: { $0 == "/url" },
            parameterNames: ["url", "q"],
            usesRawQueryAsDestination: false
        ),
        // BusinessWire external-link redirects embed the final URL directly
        // in `url=`. This is locally recoverable, unlike an opaque shortener.
        WrapperRule(
            matchesHost: { $0 == "cts.businesswire.com" },
            matchesPath: { _ in true },
            parameterNames: ["url"],
            usesRawQueryAsDestination: false
        ),
        // href.li is a referrer-hiding redirector that places the complete
        // destination in the raw query string: https://href.li/?https://…
        WrapperRule(
            matchesHost: { $0 == "href.li" },
            matchesPath: { $0 == "/" },
            parameterNames: [],
            usesRawQueryAsDestination: true
        ),
    ]

    private static let maxUnwrapDepth = 3

    /// If `url` matches a known wrapper pattern, returns its destination
    /// URL string plus the number of query parameters the wrapper URL had
    /// (all of which are discarded by the replacement). Returns nil if
    /// `url` isn't a recognized wrapper.
    private static func validHTTPDestination(_ value: String) -> String? {
        guard let destination = URL(string: value),
            let scheme = destination.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            destination.host != nil
        else {
            return nil
        }
        return value
    }

    private static func unwrap(_ url: URL) -> (destination: String, parameterCount: Int)? {
        guard let host = url.host?.lowercased(),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let queryItems = components.queryItems
        else {
            return nil
        }

        for rule in rules where rule.matchesHost(host) && rule.matchesPath(url.path) {
            if rule.usesRawQueryAsDestination,
                let rawQuery = components.percentEncodedQuery
            {
                // href.li's query is itself a URL. Try the percent-encoded
                // spelling first so escapes belonging to the destination
                // (for example `%26` inside a query value) are not decoded
                // into wrapper-level separators. Fully encoded destinations
                // are handled by the second candidate.
                var candidates = [rawQuery]
                if let decodedQuery = rawQuery.removingPercentEncoding,
                   decodedQuery != rawQuery {
                    candidates.append(decodedQuery)
                }

                // An unescaped fragment belongs to the href.li destination
                // syntactically, but URLComponents exposes it as the
                // wrapper's fragment because the query has no delimiter
                // separating the two. Reattach its encoded spelling.
                if let encodedFragment = components.percentEncodedFragment {
                    candidates = candidates.map { "\($0)#\(encodedFragment)" }
                }

                if let destination = candidates.compactMap({ validHTTPDestination($0) }).first {
                    // href.li has no named wrapper parameters; its raw query is
                    // the destination itself, so this hop contributes zero to
                    // the aggregate parameter-removal count.
                    return (destination, 0)
                }
            }

            for name in rule.parameterNames {
                if let value = queryItems.first(where: { $0.name == name })?.value,
                    let destination = validHTTPDestination(value)
                {
                    return (destination, queryItems.count)
                }
            }
        }

        return nil
    }

    /// Repeatedly unwraps `input` (in case a wrapper points at another
    /// wrapper), up to a small fixed depth to guard against loops.
    static func fullyUnwrap(_ input: String) -> UnwrapResult {
        var current = input
        var totalParametersRemoved = 0

        for _ in 0..<maxUnwrapDepth {
            // Wrapper recognition is only valid for an HTTP(S) input at
            // every hop. In particular, never turn an ftp:// or file:// URL
            // that happens to resemble a known wrapper into an HTTPS URL.
            guard let url = URL(string: current),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil,
                  let unwrapped = unwrap(url) else {
                break
            }
            current = unwrapped.destination
            totalParametersRemoved += unwrapped.parameterCount
        }

        return UnwrapResult(result: current, parametersRemoved: totalParametersRemoved)
    }
}
