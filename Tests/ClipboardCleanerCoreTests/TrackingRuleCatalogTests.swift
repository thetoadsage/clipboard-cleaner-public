import Foundation
import Testing
@testable import ClipboardCleanerCore

struct TrackingRuleCatalogTests {
    @Test func hostRulesAreSelectedTogetherWithGlobalRules() {
        let data = #"""
        {
            "global": ["utm_source"],
            "domains": {"example.com": ["campaign_id"]},
            "wildcardTLDDomains": {"widgetco": ["widget_click"]}
        }
        """#.data(using: .utf8)!
        let catalog = TrackingRuleCatalog.load(from: data)

        let exampleRules = catalog.rules(for: "WWW.Example.COM")
        #expect(exampleRules.contains("utm_source"))
        #expect(exampleRules.contains("campaign_id"))
        #expect(exampleRules.contains("CAMPAIGN_ID"))
        #expect(!exampleRules.contains("widget_click"))
        #expect(!catalog.rules(for: "notexample.com").contains("campaign_id"))

        let wildcardRules = catalog.rules(for: "shop.widgetco.co.uk")
        #expect(wildcardRules.contains("utm_source"))
        #expect(wildcardRules.contains("widget_click"))
    }

    @Test func bundledResourceLookupDoesNotDependOnGeneratedAbsoluteBuildPath() {
        let resource = TrackingRuleCatalog.resourceURL()
        #expect(resource != nil)
        #expect(resource.map { FileManager.default.isReadableFile(atPath: $0.path) } == true)
    }

    @Test func packagedAppNeverLoadsAnExternalFallbackCatalog() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Cleaner.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.cleaner", "CFBundlePackageType": "APPL"],
            format: .xml, options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let bundle = try #require(Bundle(url: app))
        let external = root.appendingPathComponent("ClipboardCleaner_ClipboardCleanerCore.bundle")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: external.appendingPathComponent("tracking-rules.json"))
        let executable = root.appendingPathComponent("ClipboardCleaner")

        #expect(TrackingRuleCatalog.resourceURL(mainBundle: bundle, executableURL: executable) == nil)

        let ownResource = resources.appendingPathComponent("tracking-rules.json")
        try Data("{}".utf8).write(to: ownResource)
        #expect(TrackingRuleCatalog.resourceURL(mainBundle: bundle, executableURL: executable) == ownResource)
    }

    @Test func relocatedTestBundleFindsItsSiblingResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let host = root.appendingPathComponent("Host.bundle")
        try FileManager.default.createDirectory(at: host, withIntermediateDirectories: true)
        let bundle = try #require(Bundle(url: host))
        let executable = root.appendingPathComponent("CleanerTests.xctest/Contents/MacOS/CleanerTests")
        #expect(TrackingRuleCatalog.resourceURL(mainBundle: bundle, executableURL: executable) == nil)

        let resources = root.appendingPathComponent("ClipboardCleaner_ClipboardCleanerCore.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let resource = resources.appendingPathComponent("tracking-rules.json")
        try Data("{}".utf8).write(to: resource)
        #expect(TrackingRuleCatalog.resourceURL(mainBundle: bundle, executableURL: executable) == resource)
    }
}
