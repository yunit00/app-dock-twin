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
    var id: String { url.standardizedFileURL.path }
    let url: URL
    var bookmark: Data?
    var application: Bool?
    var isApplication: Bool { application ?? (url.pathExtension.lowercased() == "app") }
    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !isApplication
    }
    var title: String { FileManager.default.displayName(atPath: url.path) }
    init(url: URL, isApplication: Bool? = nil) {
        application = isApplication
        self.url = url.standardizedFileURL
        bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func resolved() -> DockItem {
        guard let bookmark else { return self }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return self }
        return DockItem(url: resolved, isApplication: application)
    }
}

struct DockPreferences: Codable {
    var edge: DockEdge = .right
    var iconSize: Double = 48
    var magnification: Double = 1.6
    var autoHide = false
    var showRunning = true
    var screenID: String = "main"
}

final class DockModel: ObservableObject {
    @Published var items: [DockItem]
    @Published var preferences: DockPreferences
    @Published var running: [NSRunningApplication] = []
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var subscriptions = Set<AnyCancellable>()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "items"), let stored = try? JSONDecoder().decode([DockItem].self, from: data) {
            var seen = Set<String>()
            items = stored.map { $0.resolved() }.filter { seen.insert($0.id).inserted }
        } else {
            let paths = ["/System/Library/CoreServices/Finder.app", "/Applications/Safari.app", "/System/Applications/System Settings.app", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path]
            items = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { DockItem(url: URL(fileURLWithPath: $0)) }
        }
        preferences = defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(DockPreferences.self, from: $0) } ?? DockPreferences()
        preferences.iconSize = min(80, max(28, preferences.iconSize))
        preferences.magnification = min(2, max(1, preferences.magnification))
        refreshRunning()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshRunning() })
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
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    var visibleItems: [DockItem] {
        guard preferences.showRunning else { return items }
        var seen = Set(items.map(\.id))
        let extra = running.compactMap(\.bundleURL)
            .map { DockItem(url: $0, isApplication: true) }
            .filter { seen.insert($0.id).inserted }
        let apps = items.filter(\.isApplication)
        let files = items.filter { !$0.isApplication }
        return apps + extra + files
    }

    func application(for item: DockItem) -> NSRunningApplication? {
        running.first { $0.bundleURL?.standardizedFileURL == item.url.standardizedFileURL }
    }

    func add(_ urls: [URL], before target: String? = nil) {
        var updated = items
        for url in urls where url.isFileURL {
            let isRunning = running.contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
            let item = DockItem(url: url, isApplication: isRunning ? true : nil)
            guard item.id != target else { continue }
            updated.removeAll { $0.id == item.id }
            let index = target.flatMap { target in updated.firstIndex { $0.id == target } } ?? updated.endIndex
            updated.insert(item, at: index)
        }
        items = updated.filter(\.isApplication) + updated.filter { !$0.isApplication }
    }

    func remove(_ item: DockItem) { items.removeAll { $0.id == item.id } }

    func open(_ item: DockItem, modifiers: NSEvent.ModifierFlags = []) {
        if modifiers.contains(.command) {
            if modifiers.contains(.option), let app = application(for: item) {
                running.filter { $0 != app }.forEach { $0.hide() }
                app.activate(options: [.activateAllWindows])
            } else { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            return
        }
        if let app = application(for: item) {
            if modifiers.contains(.option) { app.hide() }
            else { app.activate(options: [.activateAllWindows]) }
        } else {
            NSWorkspace.shared.open(item.url, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { NSAlert(error: error).runModal() } }
            }
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
        running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        onChange?()
    }
}
