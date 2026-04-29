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

    private let gridSpacing: CGFloat = 50
    private let gridColor = NSColor.gray.withAlphaComponent(0.1)
    /// One-shot guard for the initial centre-scroll: the canvas is much
    /// larger than the visible viewport, so we land the user in the middle
    /// of the surface on first appearance instead of the top-left corner.
    private var didCenterInitially = false

    override public var isFlipped: Bool {
        true
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

    func sortSubviewsByZIndex() {
        let sorted = subviews
            .compactMap { $0 as? PinboardCanvasItem }
            .sorted { $0.zIndex < $1.zIndex }
        for item in sorted {
            addSubview(item)
        }
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
