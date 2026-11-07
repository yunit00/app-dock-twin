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
    func testDropOntoUnpinnedRunningItemPinsIt() {
        let model = emptyModel()
        let url = URL(fileURLWithPath: "/Applications/Example.app")
        model.add([url], before: url.path)
        expectEqual(model.items.map(\.url), [url])
    }
    func testOldPreferencesSurviveNewAnimationSetting() throws {
        let data = Data(#"{"edge":"left","iconSize":64,"magnification":1.8,"autoHide":true,"showRunning":false,"screenID":"123"}"#.utf8)
        defaults.set(data, forKey: "preferences")
        let model = DockModel(defaults: defaults)
        expectEqual(model.preferences.edge, .left)
        expectEqual(model.preferences.iconSize, 64)
        expectEqual(model.preferences.screenID, "123")
        expectTrue(model.preferences.autoHide)
        expectTrue(model.preferences.animationsEnabled)
        model.preferences.animationsEnabled = false
        let restored = DockModel(defaults: defaults)
        expectTrue(!restored.preferences.animationsEnabled)
        expectTrue(!restored.animationsAllowed)
    }
    func testDockPasteboardCompatibility() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let url = URL(fileURLWithPath: "/Applications/An App.app")
        pasteboard.writeObjects([DockDragPayload.writer(for: url)])
        expectEqual(DockDragPayload.urls(from: pasteboard), [url])
        expectEqual(pasteboard.propertyList(forType: DockDragPayload.filenames) as? [String], [url.path])
        pasteboard.clearContents()
        pasteboard.setPropertyList([url.path, "/tmp/Папка с файлами", "relative/path"], forType: DockDragPayload.filenames)
        expectEqual(DockDragPayload.urls(from: pasteboard), [url, URL(fileURLWithPath: "/tmp/Папка с файлами")])
        pasteboard.clearContents()
        pasteboard.setString("https://example.com", forType: .URL)
        expectTrue(DockDragPayload.urls(from: pasteboard).isEmpty)
        expectEqual(DockDragPayload.operation(for: [.link, .move]), .link)
        expectEqual(DockDragPayload.operation(for: [.move]), .move)
        expectEqual(DockDragPayload.operation(for: [.delete]), [])
    }
    func testSettingsButtonOnEveryEdge() {
        _ = NSApplication.shared
        let model = emptyModel()
        let view = DockView(model: model)
        var opened = false
        view.showSettings = { opened = true }
        for edge in DockEdge.allCases {
            model.preferences.edge = edge
            _ = view.rebuild(maxLength: 700)
            let button = view.subviews.compactMap { $0 as? NSButton }.first!
            expectTrue(view.bounds.contains(button.frame))
            button.performClick(nil)
            expectTrue(opened)
            opened = false
        }
    }
    func testLegacyDockURLAndIndicatorSpacing() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let url = URL(fileURLWithPath: "/Applications/App With Spaces.app")
        pasteboard.setPropertyList([url.absoluteString, "App With Spaces"], forType: DockDragPayload.legacyURL)
        expectEqual(DockDragPayload.urls(from: pasteboard), [url])
        _ = NSApplication.shared
        let model = emptyModel()
        let tile = DockTile(item: DockItem(url: url), model: model)
        for edge in DockEdge.allCases {
            model.preferences.edge = edge
            tile.frame = edge.vertical ? NSRect(x: 0, y: 0, width: 33, height: 28) : NSRect(x: 0, y: 0, width: 28, height: 33)
            tile.layout()
            let icon = tile.subviews[0].frame
            let dot = tile.subviews[1].frame
            let gap: CGFloat
            switch edge {
            case .left: gap = icon.minX - dot.maxX
            case .right: gap = dot.minX - icon.maxX
            case .bottom: gap = icon.minY - dot.maxY
            case .top: gap = dot.minY - icon.maxY
            }
            expectEqual(gap, 2)
            expectTrue(tile.bounds.contains(dot))
            expectEqual(icon.width, icon.height)
        }
    }
    func testAnimatedReorderingCommitsAndCancelsOnEveryEdge() {
        _ = NSApplication.shared
        for edge in DockEdge.allCases {
            defaults.removeObject(forKey: "displayOrder")
            let model = emptyModel()
            model.preferences.edge = edge
            model.preferences.animationsEnabled = false
            let apps = ["A", "B", "C"].map { DockItem(url: URL(fileURLWithPath: "/Applications/\($0).app")) }
            model.items = apps + [DockItem(url: URL(fileURLWithPath: "/tmp/folder"))]
            let view = DockView(model: model)
            _ = view.rebuild(maxLength: 700)
            let tiles = view.subviews.compactMap { $0 as? DockTile }
            let first = tiles[0]
            let last = tiles[2]
            let point = NSPoint(x: last.frame.midX, y: last.frame.midY)
            view.beginReordering(first)
            view.previewReordering(at: point)
            expectEqual(first.alphaValue, 0)
            expectEqual(model.items.map(\.id), (apps + [tiles[3].item]).map(\.id))
            view.commitReordering()
            view.endReordering()
            expectEqual(Array(model.items.prefix(3)).map(\.id), [apps[1].id, apps[2].id, apps[0].id])
            expectEqual(first.alphaValue, 1)
            expectEqual(DockModel(defaults: defaults).items.map(\.id), model.items.map(\.id))
            let beforeCancel = model.items.map(\.id)
            let settled = first.frame
            view.beginReordering(first)
            let beginning = edge.vertical ? NSPoint(x: 10, y: view.bounds.maxY) : NSPoint(x: 0, y: 10)
            view.previewReordering(at: beginning)
            view.endReordering()
            expectEqual(model.items.map(\.id), beforeCancel)
            expectEqual(first.frame, settled)
            // Dragging an app past the files stops at the end of the applications section.
            view.beginReordering(tiles[1])
            let end = edge.vertical ? NSPoint(x: 10, y: 0) : NSPoint(x: view.bounds.maxX, y: 10)
            view.previewReordering(at: end)
            view.commitReordering()
            view.endReordering()
            expectTrue(!model.items.last!.isApplication)
        }
    }

    func testReorderingAcrossEntirePanel() {
        _ = NSApplication.shared
        for edge in DockEdge.allCases {
            for fraction: CGFloat in [0.05, 0.5, 0.95] {
                defaults.removeObject(forKey: "displayOrder")
                let model = emptyModel()
                model.preferences.edge = edge
                model.preferences.animationsEnabled = false
                let apps = ["A", "B", "C"].map { DockItem(url: URL(fileURLWithPath: "/Applications/\($0).app")) }
                model.items = apps
                let view = DockView(model: model)
                _ = view.rebuild(maxLength: 700)
                let tiles = view.subviews.compactMap { $0 as? DockTile }
                let source = tiles[0]
                let target = tiles[2].frame
                view.beginReordering(source)
                let point = edge.vertical
                    ? NSPoint(x: view.bounds.width * fraction, y: target.midY)
                    : NSPoint(x: target.midX, y: view.bounds.height * fraction)
                expectTrue(view.hitTest(point) === view)
                view.trackLocalDrag(at: point)
                expectTrue(edge.vertical ? source.frame.midY < tiles[1].frame.midY : source.frame.midX > tiles[1].frame.midX)
                view.trackLocalDrag(at: NSPoint(x: -20, y: -20))
                expectTrue(edge.vertical ? source.frame.midY > tiles[1].frame.midY : source.frame.midX < tiles[1].frame.midX)
                view.trackLocalDrag(at: point)
                view.commitReordering()
                view.endReordering()
                expectEqual(model.items.map(\.id), [apps[1].id, apps[2].id, apps[0].id])
                expectTrue(view.hitTest(NSPoint(x: source.frame.midX, y: source.frame.midY)) === source)
            }
        }
    }

    func testApplicationIdentityMigrationAndRunningDeduplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("One.app")
        let second = root.appendingPathComponent("Two.app")
        let bundleID = "com.example.docktwin.identity-test"
        for url in [first, second] {
            try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            try plist.write(to: url.appendingPathComponent("Contents/Info.plist"))
        }
        let oldItems: [[String: Any]] = [["url": first.absoluteString], ["url": second.absoluteString]]
        defaults.set(try JSONSerialization.data(withJSONObject: oldItems), forKey: "items")
        defaults.set([second.path, first.path], forKey: "displayOrder")
        let model = DockModel(defaults: defaults)
        expectEqual(model.items.count, 1)
        expectEqual(model.items[0].id, "app:" + bundleID)
        let finder = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }!
        let finderItem = DockItem(url: finder.bundleURL!)
        model.items = [finderItem]
        model.running = [finder]
        model.preferences.showRunning = true
        expectEqual(model.visibleItems.count, 1)
        expectEqual(model.application(for: finderItem)?.processIdentifier, finder.processIdentifier)
        let other = DockItem(url: first)
        model.items = [other]
        model.move(other, in: [finderItem, other])
        expectEqual(model.visibleItems.map(\.id), [finderItem.id, other.id])
        expectEqual(model.items.map(\.id), [other.id])
        let restored = DockModel(defaults: defaults)
        restored.running = [finder]
        expectEqual(restored.visibleItems.map(\.id), [finderItem.id, other.id])
    }

    func testFinderClickUsesApplicationReopen() {
        let workspace = RecordingWorkspace()
        let model = DockModel(defaults: defaults, workspace: workspace)
        let finder = DockItem(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        model.open(finder)
        expectEqual(workspace.openedURL, finder.url)
        expectTrue(workspace.configuration!.activates)
        expectTrue(!workspace.configuration!.createsNewApplicationInstance)
        expectTrue(workspace.configuration!.allowsRunningApplicationSubstitution)
    }

    func testMouseReleaseAfterDragDoesNotLaunchApplication() {
        _ = NSApplication.shared
        let workspace = RecordingWorkspace()
        let model = DockModel(defaults: defaults, workspace: workspace)
        model.preferences.showRunning = false
        model.items = [DockItem(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))]
        let view = DockView(model: model)
        _ = view.rebuild(maxLength: 700)
        let tile = view.subviews.compactMap { $0 as? DockTile }.first!
        let location = NSPoint(x: tile.frame.midX, y: tile.frame.midY)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        tile.mouseUp(with: up)
        expectEqual(workspace.openCount, 0)
        tile.mouseDown(with: down)
        tile.dragging = true
        tile.mouseUp(with: up)
        tile.dragging = false
        tile.mouseUp(with: up)
        expectEqual(workspace.openCount, 0)
        tile.mouseDown(with: down)
        tile.mouseUp(with: up)
        expectEqual(workspace.openCount, 1)
    }
    func testDesktopModeMigrationAndLayer() throws {
        defaults.set(Data(#"{"edge":"left","autoHide":true,"iconSize":36}"#.utf8), forKey: "preferences")
        let model = DockModel(defaults: defaults)
        expectTrue(model.preferences.desktopOnly)
        expectEqual(model.preferences.iconSize, 36)
        expectTrue(model.preferences.autoHide)
        expectTrue(model.preferences.panelLevel.rawValue < NSWindow.Level.normal.rawValue)
        expectTrue(model.preferences.panelLevel.rawValue > Int(CGWindowLevelForKey(.desktopIconWindow)))
        model.preferences.desktopOnly = false
        let restored = DockModel(defaults: defaults)
        expectTrue(!restored.preferences.desktopOnly)
        expectEqual(restored.preferences.panelLevel, .floating)
    }
    func testSystemDockEmptyOperationMask() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([DockDragPayload.writer(for: URL(fileURLWithPath: "/Applications/Example.app"))])
        expectEqual(DockDragPayload.operation(for: [], pasteboard: pasteboard), .copy)
        expectEqual(DockDragPayload.operation(for: [.delete], pasteboard: pasteboard), [])
        pasteboard.clearContents()
        pasteboard.setString("https://example.com", forType: .URL)
        expectEqual(DockDragPayload.operation(for: [], pasteboard: pasteboard), [])
        pasteboard.clearContents()
        expectEqual(DockDragPayload.operation(for: [], pasteboard: pasteboard), [])
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
            ("four-edge layout bounds", tests.testLayoutFitsEveryEdge),
            ("old settings migration and animation persistence", tests.testOldPreferencesSurviveNewAnimationSetting),
            ("Dock pasteboard compatibility", tests.testDockPasteboardCompatibility),
            ("settings button on every edge", tests.testSettingsButtonOnEveryEdge),
            ("pin when dropped on unpinned item", tests.testDropOntoUnpinnedRunningItemPinsIt),
            ("legacy Dock URL and indicator gap", tests.testLegacyDockURLAndIndicatorSpacing),
            ("reorder preview, commit, cancel, section boundaries", tests.testAnimatedReorderingCommitsAndCancelsOnEveryEdge),
            ("application identity migration and running deduplication", tests.testApplicationIdentityMigrationAndRunningDeduplication),
            ("Finder click reopens the application", tests.testFinderClickUsesApplicationReopen),
            ("mouse release after drag never launches an app", tests.testMouseReleaseAfterDragDoesNotLaunchApplication),
            ("desktop mode migration, layer and persistence", tests.testDesktopModeMigrationAndLayer),
            ("system Dock file drop with empty source mask", tests.testSystemDockEmptyOperationMask),
            ("reordering across the entire panel on every edge", tests.testReorderingAcrossEntirePanel)
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

final class RecordingWorkspace: NSWorkspace {
    var openCount = 0
    var openedURL: URL?
    var configuration: NSWorkspace.OpenConfiguration?
    override func openApplication(at applicationURL: URL, configuration: NSWorkspace.OpenConfiguration, completionHandler: (@Sendable (NSRunningApplication?, Error?) -> Void)? = nil) {
        openCount += 1
        openedURL = applicationURL
        self.configuration = configuration
    }
}
