import Foundation

private final class CatalogBundleAnchor: NSObject {}

/// A catalog of tracking query-parameter rules, loaded once from the bundled
/// `tracking-rules.json` resource (see `scripts/update_tracking_rules.py`
/// for provenance: derived from ClearURLs/Rules, LGPL-3.0, plus a small
/// hand-maintained set of global additions).
///
/// Rule strings that are plain identifiers (letters/digits/underscore) are
/// matched as exact names via `Set` lookup; anything else is compiled once
/// as a case-insensitive, fully-anchored regex.
///
/// The rules file is treated strictly as data: parsed with `JSONDecoder`
/// into plain `[String]` arrays, never interpreted or executed as code.
/// Loading validates the file's size and shape before trusting it (see
/// `isCatalogWithinSafeBounds`) and fails safely to an empty catalog -- not
/// a crash -- on anything malformed, oversized, or otherwise unexpected.
struct TrackingRuleCatalog {

    /// Upper bound on the bundled resource file's raw byte size. The real
    /// file is ~18KB as of this writing; this leaves generous headroom for
    /// legitimate catalog growth while rejecting a corrupted or tampered
    /// file before it's even JSON-decoded.
    static let maxResourceFileSizeBytes = 5_000_000

    /// Upper bound on the total number of rule pattern strings across every
    /// section of the file combined. The real catalog has ~770 as of this
    /// writing.
    static let maxTotalRuleCount = 20_000

    /// Upper bound on any single rule pattern string's length. The longest
    /// real pattern is 37 characters.
    static let maxRulePatternLength = 500

    /// Query parameter names longer than this are never checked against the
    /// catalog at all (treated as "not a known tracking parameter", i.e.
    /// left untouched) -- no legitimate tracking-parameter name is
    /// remotely this long. Defense-in-depth against a pathologically long,
    /// attacker-controlled parameter name being run through every regex
    /// rule on every clean() call.
    static let maxParameterNameLength = 512

    private struct DomainEntry {
        let domain: String
        let literal: Set<String>
        let regexes: [NSRegularExpression]
    }

    /// A provider whose rules apply across any subdomain and any TLD chain
    /// of a base label (e.g. base "amazon" covers amazon.com, amazon.us,
    /// amazon.co.uk, ...), matched generically via
    /// `HostMatching.WildcardBase` instead of an enumerated TLD list.
    private struct WildcardDomainEntry {
        let wildcardBase: HostMatching.WildcardBase
        let literal: Set<String>
        let regexes: [NSRegularExpression]
    }

    /// Rules selected for one host. Constructing this once per URL avoids
    /// repeating domain matching for every query item in that URL.
    struct ApplicableRules {
        let literal: Set<String>
        let regexes: [NSRegularExpression]

        func contains(_ name: String) -> Bool {
            guard name.utf8.count <= TrackingRuleCatalog.maxParameterNameLength else { return false }
            let lower = name.lowercased()
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            return literal.contains(lower) || regexes.contains {
                $0.firstMatch(in: lower, options: [], range: range) != nil
            }
        }
    }

    private struct CatalogFile: Decodable {
        let global: [String]
        let localGlobalAdditions: [String]?
        let domains: [String: [String]]
        let wildcardTLDDomains: [String: [String]]?
    }

    private let globalLiteral: Set<String>
    private let globalRegex: [NSRegularExpression]
    private let domainEntries: [DomainEntry]
    private let wildcardDomainEntries: [WildcardDomainEntry]

    static let shared = TrackingRuleCatalog.loadBundled()

    static let empty = TrackingRuleCatalog(
        globalLiteral: [],
        globalRegex: [],
        domainEntries: [],
        wildcardDomainEntries: []
    )

    /// Returns true if `name` is a known tracking parameter, either
    /// globally or specifically for `host` (and its subdomains).
    func isTrackingParameter(_ name: String, host: String?) -> Bool {
        return rules(for: host).contains(name)
    }

    /// Selects global and host-specific rules once for a URL. The returned
    /// value is intentionally short-lived; no URL or host cache is retained.
    func rules(for host: String?) -> ApplicableRules {
        var literal = globalLiteral
        var regexes = globalRegex

        guard let host = host?.lowercased() else {
            return ApplicableRules(literal: literal, regexes: regexes)
        }

        for entry in domainEntries where HostMatching.matches(host: host, domain: entry.domain) {
            literal.formUnion(entry.literal)
            regexes.append(contentsOf: entry.regexes)
        }

        for entry in wildcardDomainEntries where entry.wildcardBase.matches(host: host) {
            literal.formUnion(entry.literal)
            regexes.append(contentsOf: entry.regexes)
        }

        return ApplicableRules(literal: literal, regexes: regexes)
    }

    private static func loadBundled() -> TrackingRuleCatalog {
        // The packaged .app places tracking-rules.json in the standard
        // Contents/Resources location (see scripts/build_app.sh), which
        // keeps the whole bundle under Contents/ so it can be properly
        // code-signed and sealed. Bundle.main.url is safe to call
        // unconditionally: on any failure it returns nil, never crashes.
        if let url = resourceURL(),
            let data = try? Data(contentsOf: url) {
            return load(from: data)
        }
        return .empty
    }

    /// Locates the resource without touching SwiftPM's generated
    /// `Bundle.module` accessor: that accessor traps when its generated
    /// absolute build path no longer exists (for example after moving a
    /// custom scratch build). Packaged apps and SwiftPM builds are both
    /// covered by searching the main bundle and executable's nearby bundle
    /// directories.
    // Internal for regression tests, so alternate SwiftPM scratch paths can
    // verify the same lookup used by loadBundled().
    static func resourceURL(
        mainBundle: Bundle = .main,
        executableURL: URL? = Bundle(for: CatalogBundleAnchor.self).executableURL
    ) -> URL? {
        let bundleName = "ClipboardCleaner_ClipboardCleanerCore.bundle"
        var candidates = [URL]()
        if let url = mainBundle.url(forResource: "tracking-rules", withExtension: "json") {
            candidates.append(url)
        }
        candidates.append(mainBundle.bundleURL
            .appendingPathComponent("Contents/Resources/tracking-rules.json"))
        // A packaged app must never fall through to a neighboring build
        // bundle if its own resource is missing or damaged.
        if mainBundle.bundleURL.pathExtension == "app" {
            return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
        }
        // SwiftPM places the target resource bundle beside the executable.
        // Test executables live below an .xctest bundle, so include only the
        // known enclosing directories rather than searching arbitrary parents
        // (which could accidentally load an unrelated file).
        if let executable = executableURL {
            let executableDirectory = executable.deletingLastPathComponent()
            var roots = [executableDirectory]
            let contentsDirectory = executableDirectory.deletingLastPathComponent()
            let enclosingBundle = contentsDirectory.deletingLastPathComponent()
            if executableDirectory.lastPathComponent == "MacOS",
                contentsDirectory.lastPathComponent == "Contents",
                enclosingBundle.pathExtension == "xctest" {
                roots.append(enclosingBundle.deletingLastPathComponent())
            }
            for root in roots {
                let bundle = root.appendingPathComponent(bundleName)
                candidates.append(bundle.appendingPathComponent("tracking-rules.json"))
                candidates.append(bundle.appendingPathComponent("Contents/Resources/tracking-rules.json"))
            }
        }
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Parses and validates `data` as a rules catalog, returning `.empty`
    /// (never crashing) if it's oversized, malformed JSON, or doesn't match
    /// the expected shape. Exposed (not private) so this fail-safe behavior
    /// can be exercised directly in tests without needing to swap out the
    /// bundled resource file.
    static func load(from data: Data) -> TrackingRuleCatalog {
        guard data.count <= maxResourceFileSizeBytes,
            let file = try? JSONDecoder().decode(CatalogFile.self, from: data)
        else {
            return .empty
        }

        let allPatterns =
            file.global
            + (file.localGlobalAdditions ?? [])
            + file.domains.values.flatMap { $0 }
            + (file.wildcardTLDDomains ?? [:]).values.flatMap { $0 }

        guard isCatalogWithinSafeBounds(allPatterns: allPatterns) else {
            return .empty
        }

        let (globalLiteral, globalRegex) = classify(file.global + (file.localGlobalAdditions ?? []))
        let domainEntries = file.domains.map { domain, patterns -> DomainEntry in
            let (literal, regex) = classify(patterns)
            return DomainEntry(domain: domain, literal: literal, regexes: regex)
        }
        let wildcardDomainEntries = (file.wildcardTLDDomains ?? [:]).compactMap {
            base, patterns -> WildcardDomainEntry? in
            guard let wildcardBase = HostMatching.WildcardBase(base) else { return nil }
            let (literal, regex) = classify(patterns)
            return WildcardDomainEntry(wildcardBase: wildcardBase, literal: literal, regexes: regex)
        }

        return TrackingRuleCatalog(
            globalLiteral: globalLiteral,
            globalRegex: globalRegex,
            domainEntries: domainEntries,
            wildcardDomainEntries: wildcardDomainEntries
        )
    }

    /// True if `allPatterns` is small enough, and each individual pattern
    /// short enough, to be safe to compile and hold in memory. Guards
    /// against a corrupted or tampered resource file causing pathological
    /// load-time cost (there is no cryptographic integrity check on the
    /// bundled resource, so this is the load-time backstop).
    static func isCatalogWithinSafeBounds(allPatterns: [String]) -> Bool {
        guard allPatterns.count <= maxTotalRuleCount else { return false }
        return allPatterns.allSatisfy { $0.utf8.count <= maxRulePatternLength }
    }

    /// Splits patterns into plain identifiers (exact-match set) and
    /// everything else (compiled regex, case-insensitive, fully anchored).
    private static func classify(_ patterns: [String]) -> (Set<String>, [NSRegularExpression]) {
        var literal = Set<String>()
        var regex = [NSRegularExpression]()

        for pattern in patterns {
            let lower = pattern.lowercased()
            if lower.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil {
                literal.insert(lower)
            } else if let compiled = try? NSRegularExpression(
                pattern: "^(?:\(pattern))$",
                options: [.caseInsensitive]
            ) {
                regex.append(compiled)
            }
        }

        return (literal, regex)
    }
}
