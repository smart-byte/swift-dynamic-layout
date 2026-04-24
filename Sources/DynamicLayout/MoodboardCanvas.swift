//
//  MoodboardCanvas.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// Custom NSView that serves as the canvas for moodboard items.
/// Provides a large drawing surface with a subtle grid background.
public class MoodboardCanvas: NSView {
    weak var coordinator: MoodboardCanvasCoordinator?

    private let gridSpacing: CGFloat = 50
    private let gridColor = NSColor.gray.withAlphaComponent(0.1)

    override public var isFlipped: Bool {
        true
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
            .compactMap { $0 as? MoodboardCanvasItem }
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
