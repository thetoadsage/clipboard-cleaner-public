import Foundation

/// Cleans a URL through three layers, in order:
///
/// 1. `RedirectUnwrapper` -- locally unwraps a small set of known
///    redirect/wrapper links (e.g. Facebook share links, Google result
///    redirects) whose destination is embedded in their own query string.
/// 2. `CanonicalURLRules` -- explicit, opt-in rewrites to a minimal
///    canonical form for a small set of well-known product pages (e.g.
///    AliExpress, Amazon). Only applies when host *and* path confidently
///    match; otherwise falls through untouched.
/// 3. `TrackingRuleCatalog` -- the default: removes known tracking query
///    parameters by name, leaving everything else (including URLs that
///    didn't match layer 1 or 2 at all) untouched. This is what keeps the
///    app safe for the long tail of sites it hasn't specifically reviewed.
///
/// Non-URL text passes through every layer unchanged.
public enum URLCleaner {

    /// The result of a cleaning operation, including how many query
    /// parameters were actually removed (by canonical rewriting or
    /// blocklist filtering) -- used only for the aggregate statistics
    /// counters. Never carries the URL's content beyond the returned
    /// `cleaned` string itself; `parametersRemoved` is just a count.
    public struct CleaningResult: Equatable {
        public let cleaned: String
        public let parametersRemoved: Int
    }

    /// Clipboard content longer than this is returned unchanged without any
    /// parsing, unwrapping, or regex matching. Defense-in-depth against
    /// pathological-input CPU cost (e.g. regex worst cases) and simply
    /// correct behavior on its own merits: no real URL is anywhere near
    /// this long, and large clipboard content is essentially always
    /// non-URL text (a document, code, etc.) that must be left untouched
    /// anyway. Measured in UTF-8 bytes, not `String.count`, to avoid
    /// grapheme-cluster segmentation cost on adversarial Unicode before the
    /// length check itself has even run.
    static let maxInputLengthBytes = 8192

    /// Returns a cleaned version of `input`. If `input` is not a recognizable
    /// http/https URL, or has nothing to remove, `input` is returned
    /// unchanged (a redirect-unwrap on its own counts as a change).
    public static func clean(_ input: String) -> String {
        cleanWithDetails(input).cleaned
    }

    /// Same cleaning behavior as `clean(_:)`, but also reports how many
    /// query parameters were removed -- used to drive the statistics
    /// counters. This includes parameters discarded by redirect-unwrapping
    /// (every query parameter on a wrapper URL that got replaced by its
    /// destination -- not just the one holding the destination), by
    /// canonical rewriting, and by blocklist filtering. `parametersRemoved`
    /// is 0 only when nothing at all was stripped.
    public static func cleanWithDetails(_ input: String) -> CleaningResult {
        guard input.utf8.count <= maxInputLengthBytes else {
            return CleaningResult(cleaned: input, parametersRemoved: 0)
        }

        let unwrapped = RedirectUnwrapper.fullyUnwrap(input)
        let candidate = unwrapped.result

        guard let url = URL(string: candidate),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil,
            var components = URLComponents(string: candidate)
        else {
            return CleaningResult(cleaned: input, parametersRemoved: 0)
        }

        if let canonical = CanonicalURLRules.canonicalize(url) {
            // Canonical rules always drop the entire query string, so every
            // query item the URL had (if any) counts as removed, plus
            // whatever redirect-unwrapping already discarded.
            let removedCount = (components.queryItems?.count ?? 0) + unwrapped.parametersRemoved
            return CleaningResult(cleaned: canonical, parametersRemoved: removedCount)
        }

        guard let originalItems = components.queryItems, !originalItems.isEmpty else {
            return CleaningResult(cleaned: candidate, parametersRemoved: unwrapped.parametersRemoved)
        }

        let host = url.host?.lowercased()
        let applicableRules = TrackingRuleCatalog.shared.rules(for: host)
        let filteredItems = originalItems.filter {
            !applicableRules.contains($0.name)
        }

        guard filteredItems.count != originalItems.count else {
            return CleaningResult(cleaned: candidate, parametersRemoved: unwrapped.parametersRemoved)
        }

        let removedCount = (originalItems.count - filteredItems.count) + unwrapped.parametersRemoved
        components.queryItems = filteredItems.isEmpty ? nil : filteredItems
        return CleaningResult(cleaned: components.string ?? candidate, parametersRemoved: removedCount)
    }

    /// Returns true if `input` looks like a URL this cleaner would inspect
    /// (used to decide whether clipboard text should be touched at all).
    public static func isURL(_ input: String) -> Bool {
        guard let url = URL(string: input), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
