import AppKit
import Testing

@testable import ClipboardCleaner

@MainActor
struct AppDelegateMenuTests {
    @Test func settingsSubmenuContainsAllPreferences() {
        let menu = AppDelegate().buildMenu()

        let topLevelTitles = menu.items.map(\.title)
        #expect(topLevelTitles.contains("Clean Current Clipboard"))
        #expect(topLevelTitles.contains("History"))
        #expect(topLevelTitles.contains("Settings"))
        #expect(topLevelTitles.contains("Reset Statistics…"))
        #expect(!topLevelTitles.contains("Enable Monitoring"))
        #expect(!topLevelTitles.contains("Keep History"))
        #expect(!topLevelTitles.contains("Show Statistics"))

        let settingsItem = try! #require(menu.items.first { $0.title == "Settings" })
        let settingsTitles = settingsItem.submenu!.items.map(\.title)
        #expect(settingsTitles.starts(with: [
            "Enable Monitoring",
            "Keep History",
            "Show Statistics",
        ]))

        if #available(macOS 13.0, *) {
            #expect(settingsTitles.contains("Launch at Login"))
        }
    }
}
