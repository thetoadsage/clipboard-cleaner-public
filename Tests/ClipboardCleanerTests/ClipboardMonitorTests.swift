import AppKit
import Foundation
import Testing

@testable import ClipboardCleaner
@testable import ClipboardCleanerCore

@MainActor
private final class MockPasteboard: ClipboardPasteboard {
    var changeCount = 0
    var numberOfItems = 1
    var types: [NSPasteboard.PasteboardType]? = [.string]
    var text: String?
    var setStringResult = true
    var onStringRead: (() -> Void)?

    private(set) var stringReadCount = 0
    private(set) var clearCount = 0
    private(set) var setStringCount = 0

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        stringReadCount += 1
        onStringRead?()
        return text
    }

    func clearContents() -> Int {
        clearCount += 1
        changeCount += 1
        text = nil
        types = nil
        numberOfItems = 0
        return changeCount
    }

    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        setStringCount += 1
        guard setStringResult else { return false }
        text = string
        types = [.string]
        numberOfItems = 1
        changeCount += 1
        return true
    }

    func simulateExternalWrite(
        _ string: String,
        types: [NSPasteboard.PasteboardType] = [.string],
        numberOfItems: Int = 1
    ) {
        text = string
        self.types = types
        self.numberOfItems = numberOfItems
        changeCount += 1
    }
}

@MainActor
struct ClipboardMonitorTests {
    private func makeStore() -> (StatisticsStore, String) {
        let suite = "ClipboardMonitorTests.\(UUID().uuidString)"
        return (StatisticsStore(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    private func removeSuite(_ suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    @Test func realPlainTextPasteboardCanBeAutomaticallyCleaned() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.clearContents()
        try #require(pasteboard.setString("https://example.com/?utm_source=test", forType: .string))
        monitor.pollPasteboard()
        #expect(pasteboard.string(forType: .string) == "https://example.com/", "Types: \(pasteboard.types ?? [])")
        #expect(store.linksCleaned == 1)
    }

    @Test func failedWritesDoNotIncrementStatisticsAndAreNotRetried() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.setStringResult = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()
        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 1)
        #expect(pasteboard.setStringCount == 1)
        #expect(store.linksCleaned == 0)
        #expect(store.parametersRemoved == 0)
    }

    @Test func changedChangeCountAbortsTheWrite() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")
        pasteboard.onStringRead = { pasteboard.changeCount += 1 }

        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 0)
        #expect(pasteboard.setStringCount == 0)
        #expect(store.linksCleaned == 0)
    }

    @Test func selfWritesAreNotProcessedAgain() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()
        monitor.pollPasteboard()

        #expect(pasteboard.stringReadCount == 1)
        #expect(pasteboard.setStringCount == 1)
        #expect(store.linksCleaned == 1)
    }

    @Test func disabledMonitoringDoesNothing() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        monitor.isEnabled = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(pasteboard.stringReadCount == 0)
        #expect(pasteboard.setStringCount == 0)
        #expect(store.linksCleaned == 0)
    }

    @Test func automaticCleaningSkipsRichTextPayloads() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite(
            "https://example.com/?utm_source=test",
            types: [.string, NSPasteboard.PasteboardType("public.rtf")]
        )

        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 0)
        #expect(pasteboard.setStringCount == 0)
        #expect(pasteboard.text == "https://example.com/?utm_source=test")
        #expect(store.linksCleaned == 0)
    }

    @Test(arguments: [
        [
            NSPasteboard.PasteboardType.string,
            NSPasteboard.PasteboardType.URL,
            NSPasteboard.PasteboardType("public.url-name"),
        ],
        [
            NSPasteboard.PasteboardType.string,
            NSPasteboard.PasteboardType.URL,
            NSPasteboard.PasteboardType("NSStringPboardType"),
            NSPasteboard.PasteboardType("com.apple.linkpresentation.metadata"),
            NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x75726C20"),
            NSPasteboard.PasteboardType("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu"),
            NSPasteboard.PasteboardType("Apple URL pasteboard type"),
        ],
    ])
    func automaticCleaningAcceptsBrowserURLRepresentations(types: [NSPasteboard.PasteboardType]) {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite(
            "https://www.amazon.com/AOHI-Charging-Transfer-Display-MacBook/dp/B0FH96SJCK/?_encoding=UTF8&pd_rd_w=9uB7v&ref_=pd_hp_d_r_btf_bmx_gp&th=1",
            types: types
        )

        monitor.pollPasteboard()

        #expect(pasteboard.text == "https://www.amazon.com/dp/B0FH96SJCK")
        #expect(pasteboard.setStringCount == 1)
        #expect(store.linksCleaned == 1)
    }

    @Test(arguments: [
        NSPasteboard.PasteboardType.html,
        NSPasteboard.PasteboardType.rtf,
        NSPasteboard.PasteboardType.png,
        NSPasteboard.PasteboardType.fileURL,
    ])
    func automaticCleaningSkipsContentBearingURLRepresentations(type: NSPasteboard.PasteboardType) {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite(
            "https://www.amazon.com/dp/B01EWNUUUA?ref=emc_s_m_5_i_atc&th=1",
            types: [.string, .URL, type]
        )

        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 0)
        #expect(pasteboard.text == "https://www.amazon.com/dp/B01EWNUUUA?ref=emc_s_m_5_i_atc&th=1")
        #expect(store.linksCleaned == 0)
    }

    @Test func automaticCleaningSkipsUnknownCompanionRepresentationsWithoutURLType() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite(
            "https://example.com/?utm_source=test",
            types: [.string, NSPasteboard.PasteboardType("com.example.custom-data")]
        )

        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 0)
        #expect(pasteboard.text == "https://example.com/?utm_source=test")
        #expect(store.linksCleaned == 0)
    }

    @Test func automaticCleaningSkipsMultipleItems() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite(
            "https://example.com/?utm_source=test",
            numberOfItems: 2
        )

        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 0)
        #expect(pasteboard.setStringCount == 0)
        #expect(store.linksCleaned == 0)
    }

    @Test func manualCleaningStillHandlesRichTextPayloads() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        pasteboard.simulateExternalWrite(
            "https://example.com/?utm_source=test",
            types: [.string, NSPasteboard.PasteboardType("public.rtf")]
        )

        #expect(monitor.cleanCurrentClipboard())
        #expect(pasteboard.text == "https://example.com/")
        #expect(store.linksCleaned == 1)
    }

    @Test func reEnablingMonitoringBaselinesCurrentClipboard() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        monitor.isEnabled = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.isEnabled = true
        monitor.pollPasteboard()

        #expect(pasteboard.clearCount == 0)
        #expect(store.linksCleaned == 0)
    }

    @Test func disablingMonitoringStopsPollingAndReenablingResumesStartedMonitor() {
        let pasteboard = MockPasteboard()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)

        monitor.start()
        #expect(monitor.isPolling)

        monitor.isEnabled = false
        #expect(!monitor.isPolling)

        monitor.isEnabled = true
        #expect(monitor.isPolling)
        monitor.stop()
    }

    @Test func togglingAfterStopDoesNotRestartPolling() {
        let pasteboard = MockPasteboard()
        let monitor = ClipboardMonitor(pasteboard: pasteboard)

        monitor.start()
        monitor.stop()
        monitor.isEnabled = false
        monitor.isEnabled = true

        #expect(!monitor.isPolling)
    }

    @Test func manualCleaningWorksWhileMonitoringIsDisabled() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        monitor.isEnabled = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        #expect(monitor.cleanCurrentClipboard())
        #expect(pasteboard.text == "https://example.com/")
        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 1)
    }

    // MARK: - History recording

    @Test func successfulPollRecordsAHistoryEntry() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let history = HistoryStore()
        history.isEnabled = true
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store, historyStore: history)
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(history.entries.count == 1)
        #expect(history.entries[0].original == "https://example.com/?utm_source=test")
        #expect(history.entries[0].cleaned == "https://example.com/")
    }

    @Test func manualCleanRecordsAHistoryEntry() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let history = HistoryStore()
        history.isEnabled = true
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store, historyStore: history)
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        #expect(monitor.cleanCurrentClipboard())

        #expect(history.entries.count == 1)
        #expect(history.entries[0].cleaned == "https://example.com/")
    }

    @Test func failedWritesDoNotRecordHistory() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let history = HistoryStore()
        history.isEnabled = true
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store, historyStore: history)
        pasteboard.setStringResult = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(history.entries.isEmpty)
    }

    @Test func unchangedURLsDoNotRecordHistory() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let history = HistoryStore()
        history.isEnabled = true
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store, historyStore: history)
        pasteboard.simulateExternalWrite("https://example.com/search?q=swift")

        monitor.pollPasteboard()

        #expect(history.entries.isEmpty)
    }

    @Test func disabledMonitoringDoesNotRecordHistory() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let history = HistoryStore()
        history.isEnabled = true
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store, historyStore: history)
        monitor.isEnabled = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(history.entries.isEmpty)
    }

    @Test func historyDisabledDoesNotPreventStatisticsFromBeingRecorded() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        // HistoryStore() defaults to isEnabled == false here -- Statistics
        // must keep working exactly as before regardless of that setting.
        let history = HistoryStore()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store, historyStore: history)
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(store.linksCleaned == 1)
        #expect(store.parametersRemoved == 1)
        #expect(history.entries.isEmpty)
    }

    // MARK: - onLinkCleaned callback (drives the menu-bar icon flash)

    @Test func successfulPollTriggersOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(callCount == 1)
    }

    @Test func manualCleanTriggersOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        #expect(monitor.cleanCurrentClipboard())

        #expect(callCount == 1)
    }

    @Test func nonURLClipboardContentDoesNotTriggerOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.simulateExternalWrite("just some plain text, not a url")

        monitor.pollPasteboard()

        #expect(callCount == 0)
    }

    @Test func urlWithNothingToCleanDoesNotTriggerOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.simulateExternalWrite("https://example.com/search?q=swift")

        monitor.pollPasteboard()

        #expect(callCount == 0)
    }

    @Test func failedWriteDoesNotTriggerOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.setStringResult = false
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(callCount == 0)
    }

    @Test func abortedWriteFromAChangedChangeCountDoesNotTriggerOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")
        pasteboard.onStringRead = { pasteboard.changeCount += 1 }

        monitor.pollPasteboard()

        #expect(callCount == 0)
    }

    @Test func disabledMonitoringDoesNotTriggerOnLinkCleaned() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        monitor.isEnabled = false
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }
        pasteboard.simulateExternalWrite("https://example.com/?utm_source=test")

        monitor.pollPasteboard()

        #expect(callCount == 0)
    }

    @Test func rapidSuccessiveCleansEachTriggerOnLinkCleanedExactlyOnce() {
        let pasteboard = MockPasteboard()
        let (store, suite) = makeStore()
        defer { removeSuite(suite) }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, statisticsStore: store)
        var callCount = 0
        monitor.onLinkCleaned = { callCount += 1 }

        pasteboard.simulateExternalWrite("https://example.com/a?utm_source=test")
        monitor.pollPasteboard()
        pasteboard.simulateExternalWrite("https://example.com/b?utm_source=test")
        monitor.pollPasteboard()
        pasteboard.simulateExternalWrite("https://example.com/c?utm_source=test")
        monitor.pollPasteboard()

        #expect(callCount == 3)
    }
}
