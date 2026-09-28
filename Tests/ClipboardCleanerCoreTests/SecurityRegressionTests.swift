import Foundation
import Testing

@testable import ClipboardCleanerCore

/// Regression coverage from the privacy/security audit: input-size guards,
/// malformed/adversarial URLs, redirect-unwrap loop protection, regex
/// performance (ReDoS) sanity, rules-catalog validation, and the
/// non-URL-passthrough guarantee. These exist to keep verified behavior
/// verified, not to newly assert it's secure -- see the audit report for
/// what remains unverified/assumed.
struct SecurityRegressionTests {

    // MARK: - Input length guard

    @Test func inputOverMaxLengthIsReturnedUnchangedEvenIfItWouldOtherwiseClean() {
        let padding = String(repeating: "a", count: URLCleaner.maxInputLengthBytes)
        let input = "https://example.com/?utm_source=test&pad=\(padding)"
        #expect(input.utf8.count > URLCleaner.maxInputLengthBytes)
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func inputAtExactlyMaxLengthIsStillProcessedNormally() {
        // Build a valid, cleanable URL and pad an unrelated legitimate
        // parameter's value so the whole string is exactly at the cap --
        // the guard is "> max", not "== max", so this must still be cleaned.
        let base = "https://example.com/?utm_source=test&note="
        let padding = String(repeating: "a", count: URLCleaner.maxInputLengthBytes - base.utf8.count)
        let input = base + padding
        #expect(input.utf8.count == URLCleaner.maxInputLengthBytes)
        #expect(URLCleaner.clean(input) == "https://example.com/?note=\(padding)")
    }

    @Test func hugeNonURLTextIsLeftCompletelyUntouched() {
        let input = String(repeating: "the quick brown fox. ", count: 10_000)
        #expect(URLCleaner.clean(input) == input)
    }

    // MARK: - Parameter-name length guard

    @Test func absurdlyLongParameterNameIsNeverStrippedEvenIfItWouldRegexMatch() {
        // "gs_[a-z]*" is a real Google-search-scoped regex rule that would
        // match this shape if the length guard didn't short-circuit first.
        let longName = "gs_" + String(repeating: "a", count: 600)
        #expect(longName.utf8.count > TrackingRuleCatalog.maxParameterNameLength)
        #expect(TrackingRuleCatalog.shared.isTrackingParameter(longName, host: "www.google.com") == false)

        let input = "https://www.google.com/search?\(longName)=x&q=swift"
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func reasonableLengthParameterNamesAreUnaffectedByTheGuard() {
        let input = "https://www.google.com/search?q=swift&ved=abc"
        #expect(URLCleaner.clean(input) == "https://www.google.com/search?q=swift")
    }

    // MARK: - Regex performance / ReDoS sanity (empirical, not just reasoned)

    private func assertCompletesQuickly(seconds: Double = 2.0, _ body: () -> Void) {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < seconds, "took \(elapsed)s, expected under \(seconds)s")
    }

    @Test func adversarialHostWithManyLabelsDoesNotHangWildcardMatching() {
        let manyLabels = String(repeating: "a.", count: 2000)
        let input = "https://\(manyLabels)notarealtld/page?utm_source=x"
        assertCompletesQuickly {
            _ = URLCleaner.clean(input)
        }
    }

    @Test func adversarialParameterNameDoesNotHangRegexMatching() {
        // Shape chosen to resemble classic ReDoS patterns (repeated group
        // containing a starred inner class); kept just under the
        // parameter-name length guard so this actually exercises the regex
        // engine rather than being short-circuited by that guard.
        let adversarial = "vn" + String(repeating: "_a", count: 200)
        #expect(adversarial.utf8.count <= TrackingRuleCatalog.maxParameterNameLength)
        assertCompletesQuickly {
            _ = TrackingRuleCatalog.shared.isTrackingParameter(adversarial, host: "example.com")
        }
    }

    @Test func manyQueryParametersDoNotHangCleaning() {
        let items = (0..<500).map { "p\($0)=v\($0)" }.joined(separator: "&")
        let input = "https://example.com/?\(items)&utm_source=x"
        assertCompletesQuickly {
            let result = URLCleaner.clean(input)
            #expect(!result.contains("utm_source"))
        }
    }

    // MARK: - Redirect-unwrap loop protection

    @Test func chainedWrappersDoNotHangAndTerminateAtBoundedDepth() {
        // Five Google wrappers nested inside each other -- more than
        // maxUnwrapDepth (3) -- must not loop forever.
        var innermost = "https://example.com/final?utm_source=x"
        for _ in 0..<5 {
            let encoded = innermost.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            innermost = "https://www.google.com/url?q=\(encoded)&sa=t"
        }
        assertCompletesQuickly {
            _ = URLCleaner.clean(innermost)
        }
    }

    // MARK: - Malformed / malicious URLs: no crash

    @Test(
        arguments: [
            "http://",
            "https://",
            "http://[::1]",
            "http://user:pass@example.com:8080/path?q=1#frag",
            "https://example.com/%",
            "https://example.com/%zz",
            "https://example.com/%25%25%25%25%25%25%25%25",
            "https://example.com/\u{0000}\u{0001}\u{0002}",
            "https://example.com/\u{200B}\u{200C}path",
            "https://xn--e1aybc.xn--p1ai/page",
            "https://example.com/?a=1&a=2&a=3",
            "https://example.com/??q=1",
            "https://example.com/?=novalue",
            "https://example.com/?&&&",
            "not a url at all, just text with http in it",
            "http://example.com/l\u{0301}\u{0301}\u{0301}\u{0301}\u{0301}\u{0301}\u{0301}\u{0301}",
        ]
    )
    func malformedOrUnusualURLsDoNotCrash(input: String) {
        _ = URLCleaner.clean(input)
        _ = URLCleaner.isURL(input)
    }

    @Test func facebookWrapperWithNonURLValueIsNotTreatedAsAWrapper() {
        let input = "https://l.facebook.com/l.php?u=notarealurl&h=abc"
        // Must not crash, and since "notarealurl" isn't http(s), the
        // wrapper must not fire -- the string is left as an ordinary
        // (non-matching) URL and falls through to the blocklist untouched.
        #expect(URLCleaner.clean(input) == input)
    }

    @Test func googleWrapperWithEmptyValueIsNotTreatedAsAWrapper() {
        // An empty `q=` must not be treated as a wrapper destination (no
        // crash, no nonsensical empty-URL extraction). Separately, `sa` is
        // a legitimate Google-scoped tracking parameter in its own right
        // (independent of the redirect-unwrap layer), so it's still
        // expected to be stripped by the ordinary blocklist layer.
        let input = "https://www.google.com/url?q=&sa=t"
        #expect(URLCleaner.clean(input) == "https://www.google.com/url?q=")
    }

    // MARK: - Non-URL clipboard content is always left untouched

    @Test(
        arguments: [
            "",
            "   ",
            "\n\n\n",
            "just some plain text",
            "user@example.com",
            "/usr/local/bin/foo",
            "check out http://example.com sometime, it's neat",
            "{\"key\": \"value\", \"url\": \"http://example.com\"}",
            "func clean(_ input: String) -> String { return input }",
            "😀 emoji text 🎉 not a url 🚀",
            "ftp://example.com/file.txt",
            "mailto:someone@example.com",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "data:text/plain;base64,SGVsbG8=",
        ]
    )
    func nonURLContentIsAlwaysLeftUntouched(input: String) {
        #expect(URLCleaner.clean(input) == input)
    }

    // MARK: - Rules catalog: validated, fails safely, never executes as code

    @Test func malformedJSONFallsBackToEmptyCatalogWithoutCrashing() {
        let data = Data("this is not json { [ malformed".utf8)
        let catalog = TrackingRuleCatalog.load(from: data)
        // "utm_source" is a real global rule in the actual catalog; if this
        // is false, we've proven the fallback is genuinely empty, not
        // partially loaded.
        #expect(catalog.isTrackingParameter("utm_source", host: nil) == false)
    }

    @Test func emptyDataFallsBackToEmptyCatalogWithoutCrashing() {
        let catalog = TrackingRuleCatalog.load(from: Data())
        #expect(catalog.isTrackingParameter("utm_source", host: nil) == false)
    }

    @Test func validJSONWithWrongShapeFallsBackToEmptyCatalog() {
        let data = Data(#"{"totally": "unexpected", "shape": 42}"#.utf8)
        let catalog = TrackingRuleCatalog.load(from: data)
        #expect(catalog.isTrackingParameter("utm_source", host: nil) == false)
    }

    @Test func oversizedRuleCountFallsBackToEmptyCatalog() {
        let manyRules = (0..<(TrackingRuleCatalog.maxTotalRuleCount + 1)).map { "rule\($0)" }
        #expect(TrackingRuleCatalog.isCatalogWithinSafeBounds(allPatterns: manyRules) == false)

        let json: [String: Any] = ["global": manyRules, "domains": [String: [String]]()]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let catalog = TrackingRuleCatalog.load(from: data)
        #expect(catalog.isTrackingParameter("rule0", host: nil) == false)
    }

    @Test func oversizedSinglePatternFallsBackToEmptyCatalog() {
        let longPattern = String(repeating: "a", count: TrackingRuleCatalog.maxRulePatternLength + 1)
        #expect(TrackingRuleCatalog.isCatalogWithinSafeBounds(allPatterns: [longPattern]) == false)

        let json: [String: Any] = ["global": [longPattern], "domains": [String: [String]]()]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let catalog = TrackingRuleCatalog.load(from: data)
        #expect(catalog.isTrackingParameter(longPattern, host: nil) == false)
    }

    @Test func oversizedFileFallsBackToEmptyCatalog() {
        let json: [String: Any] = ["global": ["utm_source"], "domains": [String: [String]]()]
        var data = try! JSONSerialization.data(withJSONObject: json)
        data.append(Data(repeating: 0x20, count: TrackingRuleCatalog.maxResourceFileSizeBytes + 1))
        let catalog = TrackingRuleCatalog.load(from: data)
        #expect(catalog.isTrackingParameter("utm_source", host: nil) == false)
    }

    @Test func wellFormedInBoundsJSONLoadsCorrectly() {
        let json: [String: Any] = [
            "global": ["utm_source"],
            "domains": ["example.com": ["exampleparam"]],
            "wildcardTLDDomains": ["widgetco": ["widgetparam"]],
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let catalog = TrackingRuleCatalog.load(from: data)

        #expect(catalog.isTrackingParameter("utm_source", host: nil) == true)
        #expect(catalog.isTrackingParameter("exampleparam", host: "www.example.com") == true)
        #expect(catalog.isTrackingParameter("exampleparam", host: "other.com") == false)
        #expect(catalog.isTrackingParameter("widgetparam", host: "widgetco.us") == true)
        #expect(catalog.isTrackingParameter("legitparam", host: "www.example.com") == false)
    }

    @Test func realBundledCatalogLoadsSuccessfullyAndIsNonEmpty() {
        // Regression guard for the loading fallback chain itself (Bundle.main
        // vs Bundle.module vs SwiftPM-managed-process detection) -- proves
        // the real shipped rules data is actually reachable in whatever
        // environment the test suite is currently running under.
        #expect(TrackingRuleCatalog.shared.isTrackingParameter("utm_source", host: nil) == true)
        #expect(TrackingRuleCatalog.shared.isTrackingParameter("si", host: "youtu.be") == true)
    }
}
