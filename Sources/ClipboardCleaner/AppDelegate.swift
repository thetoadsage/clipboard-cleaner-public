import AppKit
import ClipboardCleanerCore
import ServiceManagement

@MainActor
final class MenuBarIconFlashController {
    static let normalSymbolName = "doc.on.clipboard"
    static let flashedSymbolName = "doc.on.clipboard.fill"
    static let defaultDuration: TimeInterval = 0.5

    private let duration: TimeInterval
    private let setSymbolName: (String) -> Void
    private var resetWorkItem: DispatchWorkItem?

    private(set) var isFlashing = false

    init(
        duration: TimeInterval = MenuBarIconFlashController.defaultDuration,
        setSymbolName: @escaping (String) -> Void
    ) {
        self.duration = duration
        self.setSymbolName = setSymbolName
    }

    /// Shows the filled clipboard symbol briefly, then restores the normal one.
    func flash() {
        resetWorkItem?.cancel()
        isFlashing = true
        setSymbolName(Self.flashedSymbolName)

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishFlash()
        }
        resetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    /// Internal to make the flash state and reset behavior directly testable.
    func finishFlash() {
        resetWorkItem?.cancel()
        resetWorkItem = nil
        isFlashing = false
        setSymbolName(Self.normalSymbolName)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statisticsStore = StatisticsStore()
    private let historyStore = HistoryStore()
    private lazy var monitor = ClipboardMonitor(statisticsStore: statisticsStore, historyStore: historyStore)
    private lazy var iconFlashController = MenuBarIconFlashController { [weak self] symbolName in
        self?.setStatusItemIcon(symbolName)
    }

    private var toggleMenuItem: NSMenuItem!
    private var linksCleanedItem: NSMenuItem!
    private var parametersRemovedItem: NSMenuItem!
    private var showStatisticsMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem?
    private var historyMenuItem: NSMenuItem!
    private var keepHistoryMenuItem: NSMenuItem!

    private let monitoringEnabledKey = "MonitoringEnabled"

    private var monitoringEnabled: Bool {
        get { UserDefaults.standard.object(forKey: monitoringEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: monitoringEnabledKey) }
    }

    /// Whether History should record new entries. Only this Bool preference
    /// is persisted -- the entries themselves never are (see `HistoryStore`,
    /// which enforces that independently of this setting). Defaults to
    /// `false`: History is off unless the user explicitly turns it on.
    private let historyEnabledKey = "HistoryEnabled"

    private var historyEnabled: Bool {
        get { UserDefaults.standard.object(forKey: historyEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: historyEnabledKey) }
    }

    /// Whether the Statistics section is displayed in the menu. Purely a
    /// display preference -- the counters themselves keep incrementing
    /// either way (see StatisticsStore), so re-enabling this always shows
    /// accurate totals.
    private var showStatistics: Bool {
        get { UserDefaults.standard.object(forKey: "ShowStatistics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ShowStatistics") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setStatusItemIcon(MenuBarIconFlashController.normalSymbolName)

        historyStore.isEnabled = historyEnabled

        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu

        monitor.isEnabled = monitoringEnabled
        toggleMenuItem.state = monitor.isEnabled ? .on : .off
        keepHistoryMenuItem.state = historyStore.isEnabled ? .on : .off
        monitor.onLinkCleaned = { [weak self] in self?.iconFlashController.flash() }
        monitor.start()
    }

    private func setStatusItemIcon(_ symbolName: String) {
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Clipboard Cleaner"
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let cleanNowItem = NSMenuItem(
            title: "Clean Current Clipboard",
            action: #selector(cleanCurrentClipboard),
            keyEquivalent: ""
        )
        cleanNowItem.target = self
        menu.addItem(cleanNowItem)

        menu.addItem(.separator())

        historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyMenuItem.submenu = NSMenu()
        menu.addItem(historyMenuItem)

        menu.addItem(.separator())

        linksCleanedItem = NSMenuItem(title: "Links cleaned: 0", action: nil, keyEquivalent: "")
        linksCleanedItem.isEnabled = false
        menu.addItem(linksCleanedItem)

        parametersRemovedItem = NSMenuItem(title: "Parameters removed: 0", action: nil, keyEquivalent: "")
        parametersRemovedItem.isEnabled = false
        menu.addItem(parametersRemovedItem)

        menu.addItem(.separator())

        let settingsMenu = NSMenu()
        toggleMenuItem = NSMenuItem(
            title: "Enable Monitoring",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        toggleMenuItem.state = monitor.isEnabled ? .on : .off
        settingsMenu.addItem(toggleMenuItem)

        keepHistoryMenuItem = NSMenuItem(
            title: "Keep History",
            action: #selector(toggleKeepHistory),
            keyEquivalent: ""
        )
        keepHistoryMenuItem.target = self
        settingsMenu.addItem(keepHistoryMenuItem)

        showStatisticsMenuItem = NSMenuItem(
            title: "Show Statistics",
            action: #selector(toggleShowStatistics),
            keyEquivalent: ""
        )
        showStatisticsMenuItem.target = self
        settingsMenu.addItem(showStatisticsMenuItem)

        if #available(macOS 13.0, *) {
            let item = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin),
                keyEquivalent: ""
            )
            item.target = self
            launchAtLoginMenuItem = item
            settingsMenu.addItem(item)
        }

        let settingsMenuItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsMenuItem.submenu = settingsMenu
        menu.addItem(settingsMenuItem)

        menu.addItem(.separator())

        let resetStatisticsItem = NSMenuItem(
            title: "Reset Statistics…",
            action: #selector(resetStatistics),
            keyEquivalent: ""
        )
        resetStatisticsItem.target = self
        menu.addItem(resetStatisticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Clipboard Cleaner",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    /// Refreshes the statistics display (current counts, visibility, and
    /// the toggle's checkmark) right before the menu is shown, so it never
    /// shows stale numbers from when the app launched.
    func menuNeedsUpdate(_ menu: NSMenu) {
        linksCleanedItem.title = "Links cleaned: \(statisticsStore.linksCleaned)"
        parametersRemovedItem.title = "Parameters removed: \(statisticsStore.parametersRemoved)"

        linksCleanedItem.isHidden = !showStatistics
        parametersRemovedItem.isHidden = !showStatistics
        showStatisticsMenuItem.state = showStatistics ? .on : .off
        if #available(macOS 13.0, *) {
            launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }

        keepHistoryMenuItem.state = historyStore.isEnabled ? .on : .off
        rebuildHistorySubmenu()
    }

    /// Rebuilds the History submenu from `historyStore.entries` (newest
    /// first) right before display, the same way the statistics text above
    /// is refreshed -- so it never shows stale entries.
    private func rebuildHistorySubmenu() {
        let submenu = NSMenu()

        if !historyStore.isEnabled {
            let disabledItem = NSMenuItem(
                title: "History is off -- enable “Keep History” to start recording",
                action: nil,
                keyEquivalent: ""
            )
            disabledItem.isEnabled = false
            submenu.addItem(disabledItem)
        } else if historyStore.entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No links cleaned yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        } else {
            for entry in historyStore.entries {
                let item = NSMenuItem(
                    title: Self.truncatedForMenu(entry.cleaned),
                    action: #selector(showHistoryEntry(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = entry
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !historyStore.entries.isEmpty
        submenu.addItem(clearItem)

        historyMenuItem.submenu = submenu
    }

    private static func truncatedForMenu(_ string: String, maxLength: Int = 60) -> String {
        guard string.count > maxLength else { return string }
        return String(string.prefix(maxLength - 1)) + "…"
    }

    @objc private func toggleEnabled() {
        monitor.isEnabled.toggle()
        monitoringEnabled = monitor.isEnabled
        toggleMenuItem.state = monitor.isEnabled ? .on : .off
    }

    /// Turning History off immediately discards any in-memory entries (see
    /// `HistoryStore.isEnabled`'s `didSet`); turning it back on starts
    /// recording fresh without restoring what was discarded.
    @objc private func toggleKeepHistory() {
        historyStore.isEnabled.toggle()
        historyEnabled = historyStore.isEnabled
        keepHistoryMenuItem.state = historyStore.isEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLoginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func cleanCurrentClipboard() {
        monitor.cleanCurrentClipboard()
    }

    @objc private func showHistoryEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? HistoryStore.Entry else { return }

        let alert = NSAlert()
        alert.messageText = "Cleaned Link"
        alert.informativeText = "Original:\n\(entry.original)\n\nCleaned:\n\(entry.cleaned)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Copy Cleaned URL")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(entry.cleaned, forType: .string)
        }
    }

    @objc private func clearHistory() {
        guard !historyStore.entries.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Clear History?"
        alert.informativeText = "This removes the recently cleaned links from memory. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            historyStore.clear()
        }
    }

    @objc private func toggleShowStatistics() {
        showStatistics.toggle()
    }

    @objc private func resetStatistics() {
        let alert = NSAlert()
        alert.messageText = "Reset Statistics?"
        alert.informativeText = "This will reset \"Links cleaned\" and \"Parameters removed\" to zero. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            statisticsStore.reset()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
