import Foundation
import Testing

@testable import ClipboardCleanerCore

@MainActor
struct HistoryStoreTests {

    /// Most tests below are about recording behavior, not the default-off
    /// preference itself (that's covered separately below), so they opt in
    /// explicitly rather than relying on (or masking) the default.
    private func makeEnabledStore() -> HistoryStore {
        let store = HistoryStore()
        store.isEnabled = true
        return store
    }

    @Test func startsEmpty() {
        let store = makeEnabledStore()
        #expect(store.entries.isEmpty)
    }

    @Test func recordingAddsAnEntryWithOriginalAndCleaned() {
        let store = makeEnabledStore()
        store.record(original: "https://example.com/?utm_source=x", cleaned: "https://example.com/")

        #expect(store.entries.count == 1)
        #expect(store.entries[0].original == "https://example.com/?utm_source=x")
        #expect(store.entries[0].cleaned == "https://example.com/")
    }

    @Test func newestEntryIsFirst() {
        let store = makeEnabledStore()
        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")
        store.record(original: "https://b.example/?x=1", cleaned: "https://b.example/")
        store.record(original: "https://c.example/?x=1", cleaned: "https://c.example/")

        #expect(store.entries.map(\.cleaned) == [
            "https://c.example/",
            "https://b.example/",
            "https://a.example/",
        ])
    }

    @Test func capsAtMaxEntriesAndEvictsTheOldest() {
        let store = makeEnabledStore()
        for i in 1...7 {
            store.record(original: "https://example.com/\(i)?x=1", cleaned: "https://example.com/\(i)")
        }

        #expect(store.entries.count == HistoryStore.maxEntries)
        // Newest (7) first, oldest kept is 3 -- 1 and 2 were evicted.
        #expect(store.entries.map(\.cleaned) == [
            "https://example.com/7",
            "https://example.com/6",
            "https://example.com/5",
            "https://example.com/4",
            "https://example.com/3",
        ])
    }

    @Test func clearEmptiesAllEntries() {
        let store = makeEnabledStore()
        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")
        store.record(original: "https://b.example/?x=1", cleaned: "https://b.example/")

        store.clear()

        #expect(store.entries.isEmpty)
    }

    @Test func recordingAgainAfterClearWorksNormally() {
        let store = makeEnabledStore()
        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")
        store.clear()
        store.record(original: "https://b.example/?x=1", cleaned: "https://b.example/")

        #expect(store.entries.count == 1)
        #expect(store.entries[0].cleaned == "https://b.example/")
    }

    // MARK: - The isEnabled preference gate (default OFF, enable, disable, re-enable)

    @Test func newHistoryStoreDefaultsToDisabled() {
        let store = HistoryStore()
        #expect(store.isEnabled == false)
    }

    @Test func recordingDoesNothingWhileDisabled() {
        let store = HistoryStore()
        #expect(store.isEnabled == false)

        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")

        #expect(store.entries.isEmpty)
    }

    @Test func enablingAllowsRecordingToStart() {
        let store = HistoryStore()
        store.isEnabled = true

        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")

        #expect(store.entries.count == 1)
    }

    @Test func disablingImmediatelyClearsExistingEntries() {
        let store = HistoryStore()
        store.isEnabled = true
        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")
        #expect(store.entries.count == 1)

        store.isEnabled = false

        #expect(store.entries.isEmpty)
    }

    @Test func disablingWhileAlreadyEmptyIsHarmless() {
        let store = HistoryStore()
        store.isEnabled = true

        store.isEnabled = false

        #expect(store.entries.isEmpty)
        #expect(store.isEnabled == false)
    }

    @Test func reEnablingDoesNotRestorePreviousEntries() {
        let store = HistoryStore()
        store.isEnabled = true
        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")
        store.isEnabled = false

        store.isEnabled = true

        #expect(store.entries.isEmpty)
    }

    @Test func recordingAfterReEnablingStartsFresh() {
        let store = HistoryStore()
        store.isEnabled = true
        store.record(original: "https://a.example/?x=1", cleaned: "https://a.example/")
        store.isEnabled = false
        store.isEnabled = true

        store.record(original: "https://b.example/?x=1", cleaned: "https://b.example/")

        #expect(store.entries.count == 1)
        #expect(store.entries[0].cleaned == "https://b.example/")
    }
}
