import AppKit

@main
final class DockModelTests {
    private var defaults: UserDefaults!
    private var suite: String!
    func setUp() {
        suite = "DockTwinTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }
    func tearDown() { defaults.removePersistentDomain(forName: suite) }
    private func emptyModel() -> DockModel {
        let model = DockModel(defaults: defaults)
        model.items = []
        model.preferences.showRunning = false
        return model
    }
    func testAddingDeduplicatesAndKeepsApplicationsBeforeFiles() {
        let model = emptyModel()
        let file = URL(fileURLWithPath: "/tmp/document.txt")
        let app = URL(fileURLWithPath: "/Applications/Example.app")
        model.add([file, app, file])
        expectEqual(model.items.map(\.url), [app, file])
    }
    func testReorderingAndDroppingOnSelfPreservesItems() {
        let model = emptyModel()
        let urls = ["a", "b", "c"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        model.add(urls)
        model.add([urls[2]], before: urls[0].path)
        expectEqual(model.items.map(\.url), [urls[2], urls[0], urls[1]])
        model.add([urls[0]], before: urls[0].path)
        expectEqual(model.items.map(\.url), [urls[2], urls[0], urls[1]])
    }
    func testPersistenceAndRemoval() {
        let model = emptyModel()
        model.add([URL(fileURLWithPath: "/tmp/keep.txt")])
        model.preferences.edge = .top
        let restored = DockModel(defaults: defaults)
        expectEqual(restored.items.map(\.id), model.items.map(\.id))
        expectEqual(restored.preferences.edge, .top)
        restored.remove(restored.items[0])
        expectTrue(DockModel(defaults: defaults).items.isEmpty)
    }
    func testCorruptPreferencesFallBackToDefaults() {
        defaults.set(Data("broken".utf8), forKey: "preferences")
        expectEqual(DockModel(defaults: defaults).preferences.iconSize, 48)
    }
    func testPreferencesAreClamped() throws {
        var preferences = DockPreferences()
        preferences.iconSize = -1
        preferences.magnification = 100
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences")
        let model = DockModel(defaults: defaults)
        expectEqual(model.preferences.iconSize, 28)
        expectEqual(model.preferences.magnification, 2)
    }
    func testRunningApplicationHintSurvivesPersistence() {
        let model = emptyModel()
        model.items = [DockItem(url: URL(fileURLWithPath: "/tmp/example.exe"), isApplication: true)]
        expectTrue(DockModel(defaults: defaults).items[0].isApplication)
    }
    func testLayoutFitsEveryEdge() {
        _ = NSApplication.shared
        let model = emptyModel()
        model.items = (0..<30).map { DockItem(url: URL(fileURLWithPath: "/Applications/Example\($0).app")) }
        let view = DockView(model: model)
        for edge in DockEdge.allCases {
            model.preferences.edge = edge
            _ = view.rebuild(maxLength: 700)
            let tiles = view.subviews.compactMap { $0 as? DockTile }
            expectEqual(tiles.count, 30)
            for tile in tiles {
                expectTrue(view.bounds.insetBy(dx: -1, dy: -1).contains(tile.frame))
            }
        }
    }
    func testRemoteURLsAreIgnored() {
        let model = emptyModel()
        model.add([URL(string: "https://example.com")!])
        expectTrue(model.items.isEmpty)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    precondition(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
}
func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
extension DockModelTests {
    static func main() throws {
        let tests = DockModelTests()
        let cases: [(String, () throws -> Void)] = [
            ("deduplication and sections", tests.testAddingDeduplicatesAndKeepsApplicationsBeforeFiles),
            ("reordering and self-drop", tests.testReorderingAndDroppingOnSelfPreservesItems),
            ("persistence and removal", tests.testPersistenceAndRemoval),
            ("corrupt settings", tests.testCorruptPreferencesFallBackToDefaults),
            ("settings bounds", tests.testPreferencesAreClamped),
            ("remote URL rejection", tests.testRemoteURLsAreIgnored),
            ("application type persistence", tests.testRunningApplicationHintSurvivesPersistence),
            ("four-edge layout bounds", tests.testLayoutFitsEveryEdge)
        ]
        for (name, test) in cases {
            tests.setUp()
            defer { tests.tearDown() }
            try test()
            print("PASS \(name)")
        }
        print("All \(cases.count) checks passed")
    }
}
