//
//  PinboardCanvas.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// Custom NSView that serves as the canvas for pinboard items.
/// Provides a large drawing surface with a subtle grid background.
public class PinboardCanvas: NSView {
    weak var coordinator: PinboardCanvasCoordinator?
    private var itemsByID: [UUID: PinboardCanvasItem] = [:]
    private var orderedItemIDs: [UUID] = []

    private let gridSpacing: CGFloat = 50
    private let gridColor = NSColor.gray.withAlphaComponent(0.1)
    /// One-shot guard for the initial centre-scroll: the canvas is much
    /// larger than the visible viewport, so we land the user in the middle
    /// of the surface on first appearance instead of the top-left corner.
    private var didCenterInitially = false

    override public var isFlipped: Bool {
        true
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-back the canvas so child items' layer transforms are
        // composited reliably. Without this, rotated children often
        // render at 0° because the non-layer-backed parent doesn't
        // propagate the layer.transform of layer-backed subviews
        // through its drawRect-based rendering path.
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !didCenterInitially else { return }
        // Defer to the next runloop tick so the enclosing scroll view has
        // finished its first layout pass (otherwise its contentView bounds
        // are still zero and the centre offset comes out wrong).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scrollToCenter()
            didCenterInitially = true
        }
    }

    private func scrollToCenter() {
        guard let scrollView = enclosingScrollView else { return }
        let visible = scrollView.contentView.bounds.size
        guard visible.width > 0, visible.height > 0 else { return }
        let origin = NSPoint(
            x: (bounds.width - visible.width) / 2,
            y: (bounds.height - visible.height) / 2
        )
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// `⌥` + scroll wheel zooms the canvas centred on the mouse cursor —
    /// matches Sketch / Affinity / Photoshop. We deliberately avoid `⌃`
    /// because macOS reserves it for the system-wide Accessibility zoom.
    /// Without the modifier the event falls through to NSScrollView for
    /// normal panning.
    override public func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.option),
              let scrollView = enclosingScrollView
        else {
            super.scrollWheel(with: event)
            return
        }
        let factor = 1.0 + event.scrollingDeltaY * 0.02
        let target = scrollView.magnification * factor
        let clamped = max(scrollView.minMagnification, min(scrollView.maxMagnification, target))
        let mouseInCanvas = convert(event.locationInWindow, from: nil)
        scrollView.setMagnification(clamped, centeredAt: mouseInCanvas)
        coordinator?.zoomChanged(clamped)
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Background
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        // Subtle grid
        gridColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 0.5

        // Vertical lines
        let startX = floor(dirtyRect.minX / gridSpacing) * gridSpacing
        var x = startX
        while x <= dirtyRect.maxX {
            path.move(to: NSPoint(x: x, y: dirtyRect.minY))
            path.line(to: NSPoint(x: x, y: dirtyRect.maxY))
            x += gridSpacing
        }

        // Horizontal lines
        let startY = floor(dirtyRect.minY / gridSpacing) * gridSpacing
        var y = startY
        while y <= dirtyRect.maxY {
            path.move(to: NSPoint(x: dirtyRect.minX, y: y))
            path.line(to: NSPoint(x: dirtyRect.maxX, y: y))
            y += gridSpacing
        }

        path.stroke()
    }

    func item(for id: UUID) -> PinboardCanvasItem? {
        itemsByID[id]
    }

    func registerItem(_ item: PinboardCanvasItem) {
        itemsByID[item.itemID] = item
    }

    func removeItem(withID id: UUID) {
        itemsByID[id]?.removeFromSuperview()
        itemsByID[id] = nil
        orderedItemIDs.removeAll { $0 == id }
    }

    func forEachItem(_ body: (PinboardCanvasItem) -> Void) {
        for id in orderedItemIDs {
            if let item = itemsByID[id] {
                body(item)
            }
        }
    }

    func syncZOrder(using orderedItems: [PinboardCanvasItemData]) {
        let desiredOrder = orderedItems
            .sorted {
                if $0.zIndex == $1.zIndex {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.zIndex < $1.zIndex
            }
            .map(\.id)

        guard desiredOrder != orderedItemIDs else { return }

        orderedItemIDs = desiredOrder

        var previous: PinboardCanvasItem?
        for id in desiredOrder {
            guard let item = itemsByID[id] else { continue }
            if let previous {
                addSubview(item, positioned: .above, relativeTo: previous)
            } else {
                addSubview(item, positioned: .below, relativeTo: nil)
            }
            previous = item
        }
    }

    // MARK: - Selection

    /// Click on empty canvas (no item caught the event) clears the
    /// selection — same affordance as Finder, NSCollectionView, and any
    /// canvas app. Marquee select would extend this; for now a plain
    /// click on background is the only path that lands here.
    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        coordinator?.deselectAll()
    }

    // MARK: - Drag & Drop from Finder

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else {
            return false
        }

        let dropPoint = convert(sender.draggingLocation, from: nil)

        // Pick up the preview size of the first dragging item as a hint for
        // initial card dimensions. Replaces the deprecated draggedImage API.
        var imageSize: CGSize?
        sender.enumerateDraggingItems(
            options: [],
            for: self,
            classes: [NSURL.self],
            searchOptions: [.urlReadingFileURLsOnly: true]
        ) { draggingItem, _, stop in
            imageSize = draggingItem.draggingFrame.size
            stop.pointee = true
        }

        coordinator?.externalDrop(urls: urls, at: dropPoint, imageSize: imageSize)
        return true
    }
}
