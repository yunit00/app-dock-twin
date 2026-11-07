import AppKit
import Combine

enum DockEdge: String, Codable, CaseIterable {
    case left, bottom, right, top
    var title: String {
        switch self {
        case .left: return "Слева"
        case .bottom: return "Снизу"
        case .right: return "Справа"
        case .top: return "Сверху"
        }
    }
    var vertical: Bool { self == .left || self == .right }
}

struct DockItem: Codable, Identifiable {
    var id: String { applicationIdentifier.map { "app:\($0)" } ?? url.standardizedFileURL.path }
    let url: URL
    var bookmark: Data?
    var application: Bool?
    private(set) var applicationIdentifier: String?
    var isApplication: Bool { application ?? (url.pathExtension.lowercased() == "app") }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !isApplication
    }
    var title: String { FileManager.default.displayName(atPath: url.path) }
    init(url: URL, isApplication: Bool? = nil) {
        application = isApplication
        let resolved = (try? URL(resolvingAliasFileAt: url, options: [.withoutUI])) ?? url
        self.url = resolved.resolvingSymlinksInPath().standardizedFileURL
        if isApplication == true || self.url.pathExtension.lowercased() == "app" {
            applicationIdentifier = Bundle(url: self.url)?.bundleIdentifier
        }
        bookmark = try? self.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func resolved() -> DockItem {
        guard let bookmark else { return DockItem(url: url, isApplication: application) }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return DockItem(url: url, isApplication: application) }
        return DockItem(url: resolved, isApplication: application)
    }
}

struct DockPreferences: Codable {
    var edge: DockEdge = .right
    var iconSize: Double = 48
    var magnification: Double = 1.6
    var autoHide = false
    var desktopOnly = true
    var showRunning = true
    var screenID: String = "main"
    var animationsEnabled = true

    var panelLevel: NSWindow.Level {
        desktopOnly ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1) : .floating
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case edge, iconSize, magnification, autoHide, desktopOnly, showRunning, screenID, animationsEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        edge = try values.decodeIfPresent(DockEdge.self, forKey: .edge) ?? .right
        iconSize = try values.decodeIfPresent(Double.self, forKey: .iconSize) ?? 48
        magnification = try values.decodeIfPresent(Double.self, forKey: .magnification) ?? 1.6
        autoHide = try values.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        desktopOnly = try values.decodeIfPresent(Bool.self, forKey: .desktopOnly) ?? true
        showRunning = try values.decodeIfPresent(Bool.self, forKey: .showRunning) ?? true
        screenID = try values.decodeIfPresent(String.self, forKey: .screenID) ?? "main"
        animationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? true
    }
}

final class DockModel: ObservableObject {
    @Published var items: [DockItem]
    @Published var preferences: DockPreferences
    @Published var running: [NSRunningApplication] = []
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private var displayOrder: [String]

    init(defaults: UserDefaults = .standard, workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.defaults = defaults
        displayOrder = defaults.stringArray(forKey: "displayOrder") ?? []
        if let data = defaults.data(forKey: "items"), let stored = try? JSONDecoder().decode([DockItem].self, from: data) {
            var seen = Set<String>()
            items = stored.map { $0.resolved() }.filter { seen.insert($0.id).inserted }
        } else {
            let paths = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/System Settings.app", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path]
            items = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { DockItem(url: URL(fileURLWithPath: $0)) }
        }
        // Earlier versions stored paths as identities; migrate ordering without resetting it.
        displayOrder = displayOrder.map { $0.hasPrefix("/") ? DockItem(url: URL(fileURLWithPath: $0)).id : $0 }
        preferences = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(DockPreferences.self, from: $0) } ?? DockPreferences()
        preferences.iconSize = min(80, max(28, preferences.iconSize))
        preferences.magnification = min(2, max(1, preferences.magnification))
        refreshRunning()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshRunning() })
        }
        $items.dropFirst().sink { [weak self] value in
            self?.defaults.set(try? JSONEncoder().encode(value), forKey: "items")
            DispatchQueue.main.async { self?.onChange?() }
        }.store(in: &subscriptions)
        $preferences.dropFirst().sink { [weak self] value in
            self?.defaults.set(try? JSONEncoder().encode(value), forKey: "preferences")
            DispatchQueue.main.async { self?.onChange?() }
        }.store(in: &subscriptions)
    }

    deinit {
        observers.forEach { workspace.notificationCenter.removeObserver($0) }
    }

    var animationsAllowed: Bool {
        preferences.animationsEnabled && !workspace.accessibilityDisplayShouldReduceMotion
    }

    var visibleItems: [DockItem] {
        var candidates = items
        if preferences.showRunning {
            var seen = Set(items.map(\.id))
            candidates += running.compactMap(\.bundleURL)
                .map { DockItem(url: $0, isApplication: true) }
                .filter { seen.insert($0.id).inserted }
        }
        var ranks: [String: Int] = [:]
        for (index, id) in displayOrder.enumerated() where ranks[id] == nil { ranks[id] = index }
        let ordered = candidates.enumerated().sorted {
            (ranks[$0.element.id] ?? (displayOrder.count + $0.offset)) <
                (ranks[$1.element.id] ?? (displayOrder.count + $1.offset))
        }.map(\.element)
        return ordered.filter(\.isApplication) + ordered.filter { !$0.isApplication }
    }

    private func saveDisplayOrder(_ ordered: [DockItem]) {
        displayOrder = ordered.map(\.id)
        defaults.set(displayOrder, forKey: "displayOrder")
    }

    func move(_ item: DockItem, in ordered: [DockItem]) {
        // Moving a running-only app pins that app, while its neighbours retain their status.
        let pinned = Set(items.map(\.id)).union([item.id])
        let visible = Set(ordered.map(\.id))
        let remaining = items.filter { !visible.contains($0.id) }
        saveDisplayOrder(ordered + remaining)
        items = ordered.filter { pinned.contains($0.id) } + remaining
    }

    func application(for item: DockItem) -> NSRunningApplication? {
        running.first {
            if let identifier = item.applicationIdentifier, $0.bundleIdentifier == identifier { return true }
            return $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == item.url
        }
    }

    func add(_ urls: [URL], before target: String? = nil) {
        var updated = items
        var ordered = visibleItems
        for url in urls where url.isFileURL {
            let isRunning = running.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
            let item = DockItem(url: url, isApplication: isRunning ? true : nil)
            if item.id == target && updated.contains(where: { $0.id == item.id }) { continue }
            updated.removeAll { $0.id == item.id }
            let index = target.flatMap { target in updated.firstIndex { $0.id == target } } ?? updated.endIndex
            updated.insert(item, at: index)
            ordered.removeAll { $0.id == item.id }
            let visibleIndex = target.flatMap { target in ordered.firstIndex { $0.id == target } } ?? ordered.endIndex
            ordered.insert(item, at: visibleIndex)
        }
        saveDisplayOrder(ordered)
        items = updated.filter(\.isApplication) + updated.filter { !$0.isApplication }
    }

    func remove(_ item: DockItem) { items.removeAll { $0.id == item.id } }

    func open(_ item: DockItem, modifiers: NSEvent.ModifierFlags = []) {
        if modifiers.contains(.command) {
            if modifiers.contains(.option), let app = application(for: item) {
                running.filter { $0 != app }.forEach { $0.hide() }
                app.activate(options: [.activateAllWindows])
            } else { workspace.activateFileViewerSelecting([item.url]) }
            return
        }
        if modifiers.contains(.option), let app = application(for: item) {
            app.hide()
            return
        }
        let completion: (NSRunningApplication?, Error?) -> Void = { _, error in
            if let error { DispatchQueue.main.async { NSAlert(error: error).runModal() } }
        }
        if item.isApplication {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = true
            // Opening also delivers the normal reopen event to an already-running app.
            // Activation alone leaves Finder (and other apps) with no visible window.
            workspace.openApplication(at: item.url, configuration: configuration, completionHandler: completion)
        } else {
            workspace.open(item.url, configuration: .init(), completionHandler: completion)
        }
    }

    func chooseItems() {
        let panel = NSOpenPanel()
        panel.title = "Добавить в Dock Twin"
        panel.prompt = "Добавить"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func refreshRunning() {
        running = workspace.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        onChange?()
    }
}

// Dock and older AppKit sources can publish filename lists instead of file URLs.
enum DockDragPayload {
    static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let legacyURL = NSPasteboard.PasteboardType("Apple URL pasteboard type")
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .URL, filenames, legacyURL]

    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        var urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if let paths = pasteboard.propertyList(forType: filenames) as? [String] {
            urls += paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0) }
        }
        if let values = pasteboard.propertyList(forType: legacyURL) as? [String],
           let value = values.first, let url = URL(string: value), url.isFileURL {
            urls.append(url)
        }
        for item in pasteboard.pasteboardItems ?? [] {
            for type in [NSPasteboard.PasteboardType.fileURL, .URL] {
                if let value = item.string(forType: type), let url = URL(string: value), url.isFileURL {
                    urls.append(url)
                }
            }
        }
        var seen = Set<String>()
        return urls.filter { $0.isFileURL && $0.path.hasPrefix("/") }
            .map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    static func writer(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.absoluteString, forType: .URL)
        return item
    }

    static func operation(for mask: NSDragOperation) -> NSDragOperation {
        for operation: NSDragOperation in [.copy, .link, .move, .generic] where mask.contains(operation) {
            return operation
        }
        return []
    }
}
