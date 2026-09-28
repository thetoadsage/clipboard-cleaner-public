import Foundation

/// Keeps the most recent cleaned-link before/after pairs in memory only.
///
/// Unlike `StatisticsStore`, this intentionally has no persistence layer at
/// all -- no `UserDefaults`, no file, no other storage. Entries live only in
/// this instance's array and are gone the moment the app quits or this
/// object is deallocated. There is no code path in this type that writes
/// anywhere but its own in-memory `entries` array.
@MainActor
public final class HistoryStore {
    public struct Entry: Identifiable, Equatable {
        public let id = UUID()
        public let original: String
        public let cleaned: String
    }

    /// The most recent entries, newest first. Never exceeds `maxEntries`.
    public private(set) var entries: [Entry] = []

    public static let maxEntries = 5

    /// Whether `record` actually stores anything. Defaults to `false` --
    /// history is off-by-default for privacy, enforced here at the type
    /// level rather than trusted to whichever caller wires this up (see
    /// AppDelegate's `historyEnabled` preference for where the app applies
    /// the user's persisted choice). Flipping this to `false` immediately
    /// discards any existing entries; flipping it back to `true` starts
    /// recording fresh -- it never restores what was cleared.
    public var isEnabled: Bool = false {
        didSet {
            guard oldValue != isEnabled, !isEnabled else { return }
            entries.removeAll()
        }
    }

    public init() {}

    /// Records one cleaned link. Call this only after a URL was actually
    /// changed, mirroring `StatisticsStore.recordCleanedLink`. Does nothing
    /// while `isEnabled` is `false`.
    public func record(original: String, cleaned: String) {
        guard isEnabled else { return }
        entries.insert(Entry(original: original, cleaned: cleaned), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}
