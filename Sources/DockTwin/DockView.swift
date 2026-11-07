import AppKit
import SwiftUI

final class DockView: NSView, NSWindowDelegate {
    let model: DockModel
    var showSettings: (() -> Void)?
    private let glass = DockBackgroundView()
    private var tiles: [DockTile] = []
    private var tracking: NSTrackingArea?
    private var popover: NSPopover?
    private var baseSize: CGFloat = 48
    private var pointer: NSPoint?
    private let padding: CGFloat = 8
    private let spacing: CGFloat = 5
    private var menuActions: [() -> Void] = []
    private var separator = NSView()
    private let settingsButton = NSButton()
    private let settingsExtent: CGFloat = 38
    private var receivingDrag = false
    var isDragging: Bool { receivingDrag || tiles.contains { $0.dragging } }
    private var magnification: CGFloat { model.animationsAllowed ? CGFloat(model.preferences.magnification) : 1 }

    init(model: DockModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(glass)
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.cgColor
        addSubview(separator)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Настройки Dock Twin")
        settingsButton.bezelStyle = .regularSquare
        settingsButton.isBordered = false
        settingsButton.imagePosition = .imageOnly
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.toolTip = "Настройки Dock Twin"
        settingsButton.setAccessibilityLabel("Настройки Dock Twin")
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        addSubview(settingsButton)
        registerForDraggedTypes(DockDragPayload.types)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isInteracting: Bool { popover?.isShown == true || isDragging }

    func rebuild(maxLength: CGFloat) -> NSSize {
        pointer = nil
        tiles.forEach { $0.removeFromSuperview() }
        tiles = model.visibleItems.map { item in
            let tile = DockTile(item: item, model: model)
            tile.dock = self
            addSubview(tile)
            return tile
        }
        let count = CGFloat(max(tiles.count, 1))
        baseSize = min(CGFloat(model.preferences.iconSize), max(16, (maxLength - settingsExtent - 2 * padding - 18) / count - spacing))
        let length = min(maxLength, max(100, count * (baseSize + spacing) + 2 * padding + 18 + settingsExtent))
        let depth = baseSize * magnification + 50
        let size = model.preferences.edge.vertical ? NSSize(width: depth, height: length) : NSSize(width: length, height: depth)
        setFrameSize(size)
        layoutTiles(animated: false)
        return size
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        layoutTiles(animated: true)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        pointer = nil
        layoutTiles(animated: true)
    }

    private func layoutTiles(animated: Bool) {
        let edge = model.preferences.edge
        let vertical = edge.vertical
        let depth = baseSize + 12
        let glassFrame: NSRect
        switch edge {
        case .bottom: glassFrame = NSRect(x: 0, y: 0, width: bounds.width, height: depth)
        case .top: glassFrame = NSRect(x: 0, y: bounds.height - depth, width: bounds.width, height: depth)
        case .left: glassFrame = NSRect(x: 0, y: 0, width: depth, height: bounds.height)
        case .right: glassFrame = NSRect(x: bounds.width - depth, y: 0, width: depth, height: bounds.height)
        }
        glass.frame = glassFrame
        glass.cornerRadius = depth * 0.3
        let section = tiles.firstIndex { !$0.item.isApplication }
        let hasDivider = section.map { $0 > 0 } ?? false
        let baselineLength = CGFloat(tiles.count) * (baseSize + spacing) - spacing + (hasDivider ? 14 : 0)
        let available = (vertical ? bounds.height : bounds.width) - settingsExtent
        let buttonSize: CGFloat = 28
        settingsButton.frame = vertical
            ? NSRect(x: glassFrame.midX - buttonSize / 2, y: 9, width: buttonSize, height: buttonSize)
            : NSRect(x: bounds.width - settingsExtent + 1, y: glassFrame.midY - buttonSize / 2, width: buttonSize, height: buttonSize)
        let start = (available - baselineLength) / 2
        let cursor = pointer.map { vertical ? bounds.height - $0.y : $0.x }
        var sizes: [CGFloat] = []
        for index in tiles.indices {
            let center = start + CGFloat(index) * (baseSize + spacing) + baseSize / 2 + ((hasDivider && index >= section!) ? 14 : 0)
            let distance = cursor.map { abs($0 - center) } ?? .infinity
            let influence = max(0, 1 - distance / (baseSize * 2.5))
            let smooth = (1 - cos(influence * .pi)) / 2
            sizes.append(baseSize * (1 + (magnification - 1) * smooth))
        }
        let expanded = sizes.reduce(0, +) + CGFloat(max(0, tiles.count - 1)) * spacing + (hasDivider ? 14 : 0)
        // Keep the magnified row inside the display even when many apps are running.
        let fit = min(1, max(1, available - padding * 2) / max(1, expanded))
        sizes = sizes.map { $0 * fit }
        let total = sizes.reduce(0, +) + CGFloat(max(0, tiles.count - 1)) * spacing + (hasDivider ? 14 : 0)
        var offset = (available - total) / 2
        separator.isHidden = !hasDivider
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && model.animationsAllowed ? 0.12 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (index, tile) in tiles.enumerated() {
                if hasDivider && index == section {
                    let line = vertical
                        ? NSRect(x: glassFrame.minX + 10, y: bounds.height - offset - 7, width: depth - 20, height: 1)
                        : NSRect(x: offset + 7, y: glassFrame.minY + 10, width: 1, height: depth - 20)
                    separator.frame = line
                    offset += 14
                }
                let size = sizes[index]
                let rect: NSRect
                switch edge {
                case .bottom: rect = NSRect(x: offset, y: 2, width: size, height: size + 5)
                case .top: rect = NSRect(x: offset, y: bounds.height - size - 7, width: size, height: size + 5)
                case .left: rect = NSRect(x: 2, y: bounds.height - offset - size, width: size + 5, height: size)
                case .right: rect = NSRect(x: bounds.width - size - 7, y: bounds.height - offset - size, width: size + 5, height: size)
                }
                tile.animator().frame = rect
                offset += size + spacing
            }
        }
    }

    func activate(_ tile: DockTile, event: NSEvent) {
        if tile.item.isDirectory && event.modifierFlags.intersection([.command, .option]).isEmpty {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = model.animationsAllowed
            popover.contentViewController = NSHostingController(rootView: FolderView(url: tile.item.url) { [weak self] url in
                self?.popover?.close()
                self?.model.open(DockItem(url: url))
            })
            popover.contentSize = NSSize(width: 380, height: 360)
            self.popover?.close()
            self.popover = popover
            let edge: NSRectEdge
            switch model.preferences.edge {
            case .bottom: edge = .maxY
            case .top: edge = .minY
            case .left: edge = .maxX
            case .right: edge = .minX
            }
            popover.show(relativeTo: tile.bounds, of: tile, preferredEdge: edge)
        } else {
            model.open(tile.item, modifiers: event.modifierFlags)
            tile.bounce()
        }
    }

    func itemMenu(_ tile: DockTile) -> NSMenu {
        menuActions = []
        let menu = NSMenu()
        add("Открыть", to: menu) { [weak self] in self?.model.open(tile.item) }
        add("Показать в Finder", to: menu) { NSWorkspace.shared.activateFileViewerSelecting([tile.item.url]) }
        if let app = model.application(for: tile.item) {
            add(app.isHidden ? "Показать" : "Скрыть", to: menu) { _ = app.isHidden ? app.unhide() : app.hide() }
            if app.bundleIdentifier != "com.apple.finder" { add("Завершить", to: menu) { app.terminate() } }
        }
        menu.addItem(.separator())
        if model.items.contains(where: { $0.id == tile.item.id }) {
            add("Убрать из Dock Twin", to: menu) { [weak self] in self?.model.remove(tile.item) }
        } else {
            add("Оставить в Dock Twin", to: menu) { [weak self] in self?.model.add([tile.item.url]) }
        }
        menu.addItem(.separator())
        add("Настройки…", to: menu) { [weak self] in self?.showSettings?() }
        return menu
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuActions = []
        let menu = NSMenu()
        add("Добавить приложения, файлы или папки…", to: menu) { [weak self] in self?.model.chooseItems() }
        add("Настройки…", to: menu) { [weak self] in self?.showSettings?() }
        return menu
    }
    private func add(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.tag = menuActions.count
        menuActions.append(action)
        menu.addItem(item)
    }
    @objc private func openSettings() { showSettings?() }
    @objc private func runMenuAction(_ sender: NSMenuItem) { menuActions[sender.tag]() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = acceptedOperation(sender)
        receivingDrag = !operation.isEmpty
        glass.dropHighlighted = receivingDrag
        return operation
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { finishDrop() }
    override func draggingEnded(_ sender: NSDraggingInfo) { finishDrop() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !acceptedOperation(sender).isEmpty && !DockDragPayload.urls(from: sender.draggingPasteboard).isEmpty
    }
    private func acceptedOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Some system sources supply file data lazily. Negotiate using advertised types,
        // then read and validate the URLs when the user releases the drag.
        guard sender.draggingPasteboard.availableType(from: DockDragPayload.types) != nil else { return [] }
        return DockDragPayload.operation(for: sender.draggingSourceOperationMask)
    }
    private func finishDrop() {
        receivingDrag = false
        glass.dropHighlighted = false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { finishDrop() }
        let urls = DockDragPayload.urls(from: sender.draggingPasteboard)
        guard !urls.isEmpty, !acceptedOperation(sender).isEmpty else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let target = tiles.first { $0.frame.contains(point) }?.item.id
        model.add(urls, before: target)
        return true
    }

}

final class DockTile: NSView, NSDraggingSource {
    let item: DockItem
    let model: DockModel
    weak var dock: DockView?
    var dragging = false
    private let icon = NSImageView()
    private let indicator = NSView()
    private var mouseDownLocation = NSPoint.zero

    init(item: DockItem, model: DockModel) {
        self.item = item
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        icon.image = NSWorkspace.shared.icon(forFile: item.url.resolvingSymlinksInPath().path)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        addSubview(icon)
        indicator.wantsLayer = true
        indicator.layer?.cornerRadius = 1.5
        indicator.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        indicator.isHidden = model.application(for: item) == nil
        addSubview(indicator)
        toolTip = item.title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        setAccessibilityHelp("Открыть. Контекстное меню содержит дополнительные действия.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func layout() {
        super.layout()
        let diameter: CGFloat = 3
        let indicatorSpace: CGFloat = 5
        switch model.preferences.edge {
        case .bottom:
            icon.frame = NSRect(x: 0, y: indicatorSpace, width: bounds.width, height: bounds.height - indicatorSpace)
            indicator.frame = NSRect(x: bounds.midX - diameter / 2, y: 0, width: diameter, height: diameter)
        case .top:
            icon.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - indicatorSpace)
            indicator.frame = NSRect(x: bounds.midX - diameter / 2, y: bounds.height - diameter, width: diameter, height: diameter)
        case .left:
            icon.frame = NSRect(x: indicatorSpace, y: 0, width: bounds.width - indicatorSpace, height: bounds.height)
            indicator.frame = NSRect(x: 0, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        case .right:
            icon.frame = NSRect(x: 0, y: 0, width: bounds.width - indicatorSpace, height: bounds.height)
            indicator.frame = NSRect(x: bounds.width - diameter, y: bounds.midY - diameter / 2, width: diameter, height: diameter)
        }
    }

    override func mouseDown(with event: NSEvent) { mouseDownLocation = event.locationInWindow }
    override func mouseUp(with event: NSEvent) {
        if !dragging { dock?.activate(self, event: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? { dock?.itemMenu(self) }
    override func mouseDragged(with event: NSEvent) {
        guard !dragging, hypot(event.locationInWindow.x - mouseDownLocation.x, event.locationInWindow.y - mouseDownLocation.y) > 5 else { return }
        dragging = true
        let dragItem = NSDraggingItem(pasteboardWriter: DockDragPayload.writer(for: item.url))
        dragItem.setDraggingFrame(icon.frame, contents: icon.image)
        let session = beginDraggingSession(with: [dragItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = model.animationsAllowed
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { [.copy, .link] }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = false }
    override func accessibilityPerformPress() -> Bool { model.open(item); return true }
    func bounce() {
        guard model.animationsAllowed else { return }
        let animation = CAKeyframeAnimation(keyPath: model.preferences.edge.vertical ? "transform.translation.x" : "transform.translation.y")
        let sign: CGFloat = (model.preferences.edge == .right || model.preferences.edge == .top) ? -1 : 1
        animation.values = [0, 12 * sign, 0, 5 * sign, 0]
        animation.duration = 0.5
        icon.layer?.add(animation, forKey: "launch")
    }
}

/// Native glass on Tahoe, with a system vibrancy material on earlier macOS versions.
final class DockBackgroundView: NSView {
    private let effect: NSView
    var cornerRadius: CGFloat = 12 {
        didSet { updateShape() }
    }
    var dropHighlighted = false {
        didSet { layer?.borderWidth = dropHighlighted ? 1.5 : 0 }
    }

    override init(frame: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .clear
            effect = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .sidebar
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.masksToBounds = true
            effect = blur
        }
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        addSubview(effect)
        updateShape()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        effect.frame = bounds
    }
    private func updateShape() {
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            effect.layer?.cornerCurve = .continuous
            effect.layer?.cornerRadius = cornerRadius
        }
    }
}
