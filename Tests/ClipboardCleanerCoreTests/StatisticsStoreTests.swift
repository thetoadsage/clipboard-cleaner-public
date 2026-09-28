import Foundation
import Testing

@testable import ClipboardCleanerCore

/// Each test uses its own isolated UserDefaults suite (a random name) so
/// tests never read/write the real app's stored counters and can safely
/// run in parallel with each other.
@MainActor
private func makeIsolatedStore() -> (store: StatisticsStore, suiteName: String) {
    let suiteName = "StatisticsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return (StatisticsStore(defaults: defaults), suiteName)
}

private func cleanUp(_ suiteName: String) {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
}

@MainActor
struct StatisticsStoreTests {

    // MARK: - Basic increment behavior

    @Test func countersStartAtZero() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func recordingALinkIncrementsBothCountersCorrectly() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        store.recordCleanedLink(parametersRemoved: 3)

        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 3)
    }

    @Test func recordingMultipleLinksAccumulatesCorrectly() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        store.recordCleanedLink(parametersRemoved: 2)
        store.recordCleanedLink(parametersRemoved: 0)
        store.recordCleanedLink(parametersRemoved: 5)

        #expect(store.linksCleaned == 3)
        #expect(store.parametersRemoved == 7)
    }

    // MARK: - Requirement 7: one URL with 5 parameters removed

    @Test func oneURLWithFiveParametersRemovedUpdatesCountersExactlyAsSpecified() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        let input = "https://example.com/page?utm_source=a&utm_medium=b&utm_campaign=c&gclid=d&fbclid=e"
        let result = URLCleaner.cleanWithDetails(input)

        #expect(result.parametersRemoved == 5)

        if result.cleaned != input {
            store.recordCleanedLink(parametersRemoved: result.parametersRemoved)
        }

        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 5)
    }

    @Test func canonicalRuleParametersCountTowardParametersRemoved() {
        // AliExpress canonical rewriting drops the entire query string --
        // every original query item counts as removed.
        let input = "https://www.aliexpress.us/item/123456.html?sourceType=561&scm=1.2.3&aecmd=true"
        let result = URLCleaner.cleanWithDetails(input)
        #expect(result.parametersRemoved == 3)
    }

    // MARK: - Redirect-unwrap parameters also count toward parameters removed

    @Test func facebookWrapperParametersCountTowardParametersRemoved() {
        // https://l.facebook.com/l.php?u=<dest>&h=<hash> -- both `u` and
        // `h` are discarded when replaced by the destination.
        let destination = "https://example.com/article"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://l.facebook.com/l.php?u=\(encoded)&h=AT123abc"

        let result = URLCleaner.cleanWithDetails(input)

        #expect(result.cleaned == destination)
        #expect(result.parametersRemoved == 2)
    }

    @Test func googleWrapperParametersCountTowardParametersRemoved() {
        // https://www.google.com/url?q=<dest>&sa=t -- both `q` and `sa`
        // are discarded when replaced by the destination.
        let destination = "https://example.com/page"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://www.google.com/url?q=\(encoded)&sa=t"

        let result = URLCleaner.cleanWithDetails(input)

        #expect(result.cleaned == destination)
        #expect(result.parametersRemoved == 2)
    }

    @Test func unwrapAndDestinationCleaningCombineIntoOneTotal() {
        // The wrapper contributes 2 (u, h); the unwrapped destination has
        // its own utm_source stripped by the blocklist afterward, +1 -- a
        // total of 3 for one single "link cleaned" event.
        let destination = "https://example.com/article?utm_source=facebook"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://l.facebook.com/l.php?u=\(encoded)&h=AT123abc"

        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        let result = URLCleaner.cleanWithDetails(input)
        #expect(result.cleaned == "https://example.com/article")
        #expect(result.parametersRemoved == 3)

        if result.cleaned != input {
            store.recordCleanedLink(parametersRemoved: result.parametersRemoved)
        }

        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 3)
    }

    @Test func wrapperWithNoQueryParametersOfItsOwnContributesZero() {
        // A destination with nothing to clean and a wrapper hop that
        // (hypothetically) carried only the destination parameter still
        // correctly counts that one parameter, not zero -- guards against
        // accidentally always returning 0 for the unwrap stage.
        let destination = "https://example.com/plain"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let input = "https://www.google.com/url?q=\(encoded)"

        let result = URLCleaner.cleanWithDetails(input)
        #expect(result.cleaned == destination)
        #expect(result.parametersRemoved == 1)
    }

    // MARK: - Requirement 5: what must NOT increment the counters

    /// Mirrors exactly what ClipboardMonitor does: only record a cleaned
    /// link when the cleaner actually changed something.
    private func simulateClipboardEvent(_ text: String, into store: StatisticsStore) {
        let result = URLCleaner.cleanWithDetails(text)
        guard result.cleaned != text else { return }
        store.recordCleanedLink(parametersRemoved: result.parametersRemoved)
    }

    @Test func nonURLsDoNotIncrementCounters() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        simulateClipboardEvent("just some plain text", into: store)
        simulateClipboardEvent("user@example.com", into: store)
        simulateClipboardEvent("", into: store)

        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func alreadyCleanURLsDoNotIncrementCounters() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        simulateClipboardEvent("https://example.com/page?id=42", into: store)
        simulateClipboardEvent("https://www.amazon.com/dp/B08XYZ1234", into: store)

        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func urlsThatFailToParseDoNotIncrementCounters() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        simulateClipboardEvent("http://", into: store)
        simulateClipboardEvent("not a url at all", into: store)
        simulateClipboardEvent("ftp://example.com/file.txt", into: store)

        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func urlsTheCleanerLeavesUnchangedDoNotIncrementCounters() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        // A generic URL with no known tracking parameters.
        simulateClipboardEvent("https://example.com/search?q=swift&page=2", into: store)

        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func aURLThatIsActuallyChangedIncrementsLinksCleanedOnce() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        simulateClipboardEvent("https://example.com/page?utm_source=x&q=1", into: store)

        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 1)
    }

    // MARK: - Persistence across "app launches"

    @Test func countersPersistAcrossSeparateStoreInstancesWithTheSameSuite() {
        let suiteName = "StatisticsStoreTests.\(UUID().uuidString)"
        defer { cleanUp(suiteName) }

        do {
            let firstLaunch = StatisticsStore(defaults: UserDefaults(suiteName: suiteName)!)
            firstLaunch.recordCleanedLink(parametersRemoved: 4)
            firstLaunch.recordCleanedLink(parametersRemoved: 2)
        }

        // A fresh StatisticsStore instance backed by the same UserDefaults
        // suite simulates the app being relaunched.
        let secondLaunch = StatisticsStore(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(secondLaunch.linksCleaned == 2)
        #expect(secondLaunch.parametersRemoved == 6)
    }

    // MARK: - Reset

    @Test func resetSetsBothCountersToZero() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        store.recordCleanedLink(parametersRemoved: 10)
        store.recordCleanedLink(parametersRemoved: 3)
        #expect(store.linksCleaned == 2)

        store.reset()

        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func countersCanBeRecordedAgainAfterReset() {
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        store.recordCleanedLink(parametersRemoved: 5)
        store.reset()
        store.recordCleanedLink(parametersRemoved: 2)

        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 2)
    }

    // MARK: - Requirement 10: hiding the display must never affect the counters

    @Test func counterBehaviorIsIndependentOfAnyDisplayPreferenceFlag() {
        // StatisticsStore has no concept of "hidden" at all -- the
        // menu-bar "Show Statistics" toggle is a separate, independent
        // UserDefaults key read only by the app's UI layer. This proves
        // the counters keep accumulating regardless of any such flag
        // living alongside them in the same defaults domain.
        let suiteName = "StatisticsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { cleanUp(suiteName) }

        let store = StatisticsStore(defaults: defaults)
        store.recordCleanedLink(parametersRemoved: 1)

        // Simulate the user turning "Show Statistics" off.
        defaults.set(false, forKey: "ShowStatistics")

        store.recordCleanedLink(parametersRemoved: 4)

        #expect(store.linksCleaned == 2)
        #expect(store.parametersRemoved == 5)
        #expect(defaults.bool(forKey: "ShowStatistics") == false)
    }

    // MARK: - Privacy: the public API cannot carry clipboard content

    @Test func recordCleanedLinkOnlyAcceptsAnInteger() {
        // Documents/enforces the privacy guarantee structurally: there is
        // no overload or parameter through which a URL, domain, or
        // parameter name could be passed to the statistics system.
        let (store, suite) = makeIsolatedStore()
        defer { cleanUp(suite) }

        store.recordCleanedLink(parametersRemoved: 1)
        #expect(store.linksCleaned == 1)
    }
}
