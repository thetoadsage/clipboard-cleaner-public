import AppKit
import ClipboardCleanerCore

@MainActor
protocol ClipboardPasteboard: AnyObject {
    var changeCount: Int { get }
    var numberOfItems: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func clearContents() -> Int
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: ClipboardPasteboard {
    /// `NSPasteboard` exposes its item collection rather than a standalone
    /// count. Keep the adapter's count consistent with the current snapshot.
    var numberOfItems: Int { pasteboardItems?.count ?? 0 }
}

/// Polls the system pasteboard for new text content and, when enabled,
/// replaces URLs with a tracking-parameter-stripped version.
///
/// Loop prevention: every write this monitor makes to the pasteboard updates
/// `lastChangeCount` synchronously, so the next poll sees no unseen change
/// and never reprocesses its own output.
///
/// Write races: the pasteboard is a system-wide resource another process
/// can write to at any wall-clock moment, including in the window between
/// this monitor reading a value and writing the cleaned result back. Every
/// write re-checks `changeCount` immediately beforehand and aborts (does
/// not write) if it no longer matches what was read. This minimizes the
/// risk of replacing newer content, though the system pasteboard offers no
/// atomic compare-and-swap and therefore cannot eliminate the race.
///
/// Statistics: only recorded after a write actually succeeds (so an
/// aborted write, per the race guard above, never counts as a cleaned
/// link), and only as the two aggregate integers `StatisticsStore`
/// accepts -- never the URL or anything derived from it.
///
/// History: the before/after URL pair is also handed to `HistoryStore` at
/// the same point statistics are recorded, but `HistoryStore` only ever
/// holds it in memory (see its own doc comment) -- it is never persisted.
@MainActor
final class ClipboardMonitor {
    var isEnabled: Bool = true {
        didSet {
            guard oldValue != isEnabled else { return }

            if isEnabled {
                // Content written while monitoring was disabled is intentionally
                // treated as already observed. This avoids a burst of work when
                // monitoring is turned back on and avoids cleaning stale content.
                lastChangeCount = pasteboard.changeCount
                if isStarted { scheduleTimer() }
            } else {
                timer?.invalidate()
                timer = nil
            }
        }
    }

    /// Called at the same point statistics/history are recorded -- i.e.
    /// only after a URL was actually changed AND the pasteboard write
    /// actually succeeded. Purely a UI hook (see AppDelegate's menu-bar
    /// icon flash); carries no data, so it can't leak clipboard content.
    var onLinkCleaned: (() -> Void)?

    private let pasteboard: ClipboardPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private var isStarted = false
    private let pollInterval: TimeInterval
    private let statisticsStore: StatisticsStore
    private let historyStore: HistoryStore

    /// Exposed internally for lifecycle tests and diagnostics.
    var isPolling: Bool { timer != nil }

    init(
        pasteboard: ClipboardPasteboard = NSPasteboard.general,
        pollInterval: TimeInterval = 0.5,
        statisticsStore: StatisticsStore = StatisticsStore(),
        historyStore: HistoryStore = HistoryStore()
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.statisticsStore = statisticsStore
        self.historyStore = historyStore
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        isStarted = true
        guard isEnabled else {
            timer?.invalidate()
            timer = nil
            return
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollPasteboard()
            }
        }
        // Polling is background housekeeping; allowing the run loop to coalesce
        // nearby wakeups avoids unnecessary timer activity without changing the
        // monitor's observable behavior.
        timer?.tolerance = min(max(pollInterval * 0.1, 0.01), 0.1)
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
    }

    func pollPasteboard() {
        guard isEnabled else { return }
        guard pasteboard.changeCount != lastChangeCount else { return }

        // Record the observation immediately so a subsequent write below
        // doesn't get reprocessed by this same handler on the next tick.
        let observedChangeCount = pasteboard.changeCount
        lastChangeCount = observedChangeCount

        // Automatic cleaning is deliberately limited to a single URL-like
        // pasteboard item. Browsers commonly accompany the plain-text URL with
        // public.url and additional text/metadata representations. Metadata
        // type names vary between browsers and macOS releases, so a URL item
        // may carry types we have not seen before. When public.url is present,
        // allow metadata but explicitly reject rich or content-bearing types.
        // Multiple items are always skipped because they cannot be safely
        // rewritten after clearContents().
        let safeURLTypes: Set<NSPasteboard.PasteboardType> = [
            .string,
            .URL,
            NSPasteboard.PasteboardType("NSStringPboardType"),
            NSPasteboard.PasteboardType("NSUnicodePboardType"),
            NSPasteboard.PasteboardType("public.utf16-plain-text"),
            NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
            NSPasteboard.PasteboardType("public.url-name"),
        ]
        let contentBearingTypes: Set<NSPasteboard.PasteboardType> = [
            .html,
            .rtf,
            .rtfd,
            .tiff,
            .png,
            .pdf,
            .fileURL,
            .multipleTextSelection,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ]
        guard pasteboard.numberOfItems == 1,
              let types = pasteboard.types,
              !types.isEmpty,
              types.contains(.string) else { return }
        let isPlainTextOnly = types.allSatisfy({ safeURLTypes.contains($0) })
        let isURLWithMetadata = types.contains(.URL) && types.allSatisfy({ !contentBearingTypes.contains($0) })
        guard isPlainTextOnly || isURLWithMetadata else { return }
        guard let text = pasteboard.string(forType: .string) else { return }

        let result = URLCleaner.cleanWithDetails(text)
        guard result.cleaned != text else { return }

        if writeToPasteboard(result.cleaned, ifStillAt: observedChangeCount) {
            statisticsStore.recordCleanedLink(parametersRemoved: result.parametersRemoved)
            historyStore.record(original: text, cleaned: result.cleaned)
            onLinkCleaned?()
        }
    }

    /// Cleans whatever is currently on the pasteboard right now, regardless
    /// of `isEnabled`. Returns true if the pasteboard was modified.
    @discardableResult
    func cleanCurrentClipboard() -> Bool {
        let observedChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return false }
        let result = URLCleaner.cleanWithDetails(text)
        guard result.cleaned != text else { return false }

        let wrote = writeToPasteboard(result.cleaned, ifStillAt: observedChangeCount)
        if wrote {
            statisticsStore.recordCleanedLink(parametersRemoved: result.parametersRemoved)
            historyStore.record(original: text, cleaned: result.cleaned)
            onLinkCleaned?()
        }
        return wrote
    }

    @discardableResult
    private func writeToPasteboard(_ string: String, ifStillAt expectedChangeCount: Int) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            // Something else wrote to the pasteboard between our read and
            // this write -- don't overwrite it with a cleaned version of
            // content that's no longer current.
            return false
        }

        _ = pasteboard.clearContents()
        let succeeded = pasteboard.setString(string, forType: .string)
        // clearContents/setString bump changeCount; capture the new value so
        // this write (including a failed set after clear) is never mistaken
        // for external clipboard activity.
        lastChangeCount = pasteboard.changeCount
        return succeeded
    }
}
