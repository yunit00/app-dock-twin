import AppKit
import SwiftUI

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = DockModel()
    private var panel: DockPanel!
    private var dock: DockView!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var hidden = false
    private var refreshPending = false
    private var visibleFrame = NSRect.zero
    private var lastInside = Date()
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.dockID == model.preferences.screenID } ?? NSScreen.screens.first
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        dock = DockView(model: model)
        dock.showSettings = { [weak self] in self?.openSettings() }
        panel.contentView = dock
        // Register the window as well as its content view for cross-process Dock drags.
        panel.delegate = dock
        panel.registerForDraggedTypes(DockDragPayload.types)
        model.onChange = { [weak self] in self?.refresh() }
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        refresh()
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.updateVisibility() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "Dock Twin")
        let menu = NSMenu()
        let title = NSMenuItem(title: "Dock Twin", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        for (label, selector, key) in [("Добавить…", #selector(addItems), ""), ("Настройки…", #selector(openSettings), ","), ("Завершить Dock Twin", #selector(quit), "q")] {
            let item = NSMenuItem(title: label, action: selector, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    @objc private func refresh() {
        guard !dock.isDragging else {
            refreshPending = true
            return
        }
        refreshPending = false
        guard let screen else { return }
        let edge = model.preferences.edge
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let size = dock.rebuild(maxLength: edge.vertical ? area.height : area.width)
        let origin: NSPoint
        switch edge {
        case .bottom: origin = NSPoint(x: area.midX - size.width / 2, y: area.minY)
        case .top: origin = NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height)
        case .left: origin = NSPoint(x: area.minX, y: area.midY - size.height / 2)
        case .right: origin = NSPoint(x: area.maxX - size.width, y: area.midY - size.height / 2)
        }
        visibleFrame = NSRect(origin: origin, size: size)
        hidden = false
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        panel.setFrame(visibleFrame, display: true)
        lastInside = Date()
    }

    private func updateVisibility() {
        if refreshPending && !dock.isDragging { refresh() }
        guard let screen else { return }
        guard model.preferences.autoHide else {
            if hidden { setHidden(false) }
            return
        }
        let point = NSEvent.mouseLocation
        let frame = screen.frame
        let nearEdge: Bool
        switch model.preferences.edge {
        case .bottom: nearEdge = point.y <= frame.minY + 3
        case .top: nearEdge = point.y >= frame.maxY - 3
        case .left: nearEdge = point.x <= frame.minX + 3
        case .right: nearEdge = point.x >= frame.maxX - 3
        }
        if frame.contains(point) && nearEdge {
            lastInside = Date()
            if hidden { setHidden(false) }
        } else if (!hidden && visibleFrame.contains(point)) || dock.isInteracting {
            lastInside = Date()
        } else if !hidden && Date().timeIntervalSince(lastInside) > 0.7 {
            setHidden(true)
        }
    }

    private func setHidden(_ value: Bool) {
        hidden = value
        panel.ignoresMouseEvents = value
        var target = visibleFrame
        let amount = CGFloat(model.preferences.iconSize + 24)
        switch model.preferences.edge {
        case .bottom: target.origin.y -= amount
        case .top: target.origin.y += amount
        case .left: target.origin.x -= amount
        case .right: target.origin.x += amount
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = model.animationsAllowed ? 0.2 : 0
            panel.animator().alphaValue = value ? 0 : 1
            panel.animator().setFrame(value ? target : visibleFrame, display: true)
        }
    }

    @objc private func addItems() { model.chooseItems() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Dock Twin"
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
