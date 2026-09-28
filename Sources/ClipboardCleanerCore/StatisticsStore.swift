import Foundation

/// Tracks exactly two privacy-safe aggregate counters -- links cleaned and
/// parameters removed -- persisted via `UserDefaults`. No other clipboard-
/// derived information is ever recorded: not the URL, its domain, any
/// parameter name or value, or a timestamp. The public API only accepts
/// and returns plain integers, so there is no code path through which
/// clipboard content could be stored here even by mistake.
@MainActor
public final class StatisticsStore {
    // Main-actor isolation makes each compound read-modify-write update
    // atomic with respect to every app caller. UserDefaults itself is
    // thread-safe, but separate reads and writes are not one atomic action.

    private let defaults: UserDefaults
    private let linksCleanedKey: String
    private let parametersRemovedKey: String

    /// - Parameters:
    ///   - defaults: Defaults to `.standard` for real app use. Tests should
    ///     pass an isolated `UserDefaults(suiteName:)` instance instead, so
    ///     test runs never read or write the real app's stored counters.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.linksCleanedKey = "StatisticsLinksCleaned"
        self.parametersRemovedKey = "StatisticsParametersRemoved"
    }

    public var linksCleaned: Int {
        defaults.integer(forKey: linksCleanedKey)
    }

    public var parametersRemoved: Int {
        defaults.integer(forKey: parametersRemovedKey)
    }

    /// Records one cleaned link and how many query parameters were removed
    /// from it (may be zero -- e.g. a redirect-unwrap-only change). Call
    /// this only after a URL was actually changed; see
    /// `URLCleaner.cleanWithDetails(_:)`.
    public func recordCleanedLink(parametersRemoved: Int) {
        defaults.set(linksCleaned + 1, forKey: linksCleanedKey)
        defaults.set(self.parametersRemoved + parametersRemoved, forKey: parametersRemovedKey)
    }

    /// Resets both counters to zero. Callers are responsible for any user
    /// confirmation before calling this (the menu-bar UI requires it).
    public func reset() {
        defaults.set(0, forKey: linksCleanedKey)
        defaults.set(0, forKey: parametersRemovedKey)
    }
}
