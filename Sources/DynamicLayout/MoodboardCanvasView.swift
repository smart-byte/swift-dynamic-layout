//
//  MoodboardCanvasView.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import SwiftUI

/// NSViewRepresentable wrapping a MoodboardCanvas inside an NSScrollView.
/// Supports magnification (0.25x–4x) and drag & drop from Finder.
public struct MoodboardCanvasView: NSViewRepresentable {
    let items: [MoodboardCanvasItemData]
    let onItemMoved: ((UUID, CGPoint) -> Void)?
    let onItemRotated: ((UUID, CGFloat) -> Void)?
    let onItemResized: ((UUID, CGSize) -> Void)?
    let onItemReordered: ((UUID, MoodboardCanvasAction) -> Void)?
    let onItemRemoved: ((UUID) -> Void)?
    let onExternalDrop: (([URL], CGPoint) -> Void)?

    public init(
        items: [MoodboardCanvasItemData],
        onItemMoved: ((UUID, CGPoint) -> Void)? = nil,
        onItemRotated: ((UUID, CGFloat) -> Void)? = nil,
        onItemResized: ((UUID, CGSize) -> Void)? = nil,
        onItemReordered: ((UUID, MoodboardCanvasAction) -> Void)? = nil,
        onItemRemoved: ((UUID) -> Void)? = nil,
        onExternalDrop: (([URL], CGPoint) -> Void)? = nil
    ) {
        self.items = items
        self.onItemMoved = onItemMoved
        self.onItemRotated = onItemRotated
        self.onItemResized = onItemResized
        self.onItemReordered = onItemReordered
        self.onItemRemoved = onItemRemoved
        self.onExternalDrop = onExternalDrop
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let canvas = MoodboardCanvas(frame: NSRect(x: 0, y: 0, width: 4000, height: 4000))
        canvas.coordinator = context.coordinator
        context.coordinator.canvas = canvas

        let scrollView = NSScrollView()
        scrollView.documentView = canvas
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 4.0
        scrollView.magnification = 1.0

        // Register for drag & drop
        scrollView.registerForDraggedTypes([.fileURL])

        updateCanvas(canvas, with: items)

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let canvas = nsView.documentView as? MoodboardCanvas else { return }
        context.coordinator.parent = self
        updateCanvas(canvas, with: items)
    }

    public func makeCoordinator() -> MoodboardCanvasCoordinator {
        MoodboardCanvasCoordinator(self)
    }

    private func updateCanvas(_ canvas: MoodboardCanvas, with items: [MoodboardCanvasItemData]) {
        // Remove stale items
        let currentIDs = Set(items.map(\.id))
        for subview in canvas.subviews {
            if let item = subview as? MoodboardCanvasItem, !currentIDs.contains(item.itemID) {
                item.removeFromSuperview()
            }
        }

        // Add or update items
        for data in items {
            if let existing = canvas.subviews.compactMap({ $0 as? MoodboardCanvasItem }).first(where: { $0.itemID == data.id }) {
                existing.frame = NSRect(x: data.positionX, y: data.positionY, width: data.width, height: data.height)
                existing.rotationAngle = data.rotation
                existing.updateZIndex(Int(data.zIndex))
            } else {
                let item = MoodboardCanvasItem(
                    itemID: data.id,
                    imageURL: data.fileURL,
                    frame: NSRect(x: data.positionX, y: data.positionY, width: data.width, height: data.height),
                    rotation: data.rotation,
                    zIndex: Int(data.zIndex)
                )
                item.canvas = canvas
                canvas.addSubview(item)
            }
        }

        // Sort subviews by z-index
        canvas.sortSubviewsByZIndex()
    }
}

// MARK: - Data Model

public struct MoodboardCanvasItemData: Identifiable {
    public let id: UUID
    public let fileURL: URL
    public var positionX: Double
    public var positionY: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var zIndex: Int32

    public init(
        id: UUID,
        fileURL: URL,
        positionX: Double,
        positionY: Double,
        width: Double,
        height: Double,
        rotation: Double,
        zIndex: Int32
    ) {
        self.id = id
        self.fileURL = fileURL
        self.positionX = positionX
        self.positionY = positionY
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zIndex = zIndex
    }
}

public enum MoodboardCanvasAction {
    case bringToFront
    case sendToBack
}

// MARK: - Coordinator

public class MoodboardCanvasCoordinator: NSObject {
    var parent: MoodboardCanvasView
    weak var canvas: MoodboardCanvas?

    init(_ parent: MoodboardCanvasView) {
        self.parent = parent
    }

    func itemMoved(_ id: UUID, to point: CGPoint) {
        parent.onItemMoved?(id, point)
    }

    func itemRotated(_ id: UUID, by angle: CGFloat) {
        parent.onItemRotated?(id, angle)
    }

    func itemResized(_ id: UUID, to size: CGSize) {
        parent.onItemResized?(id, size)
    }

    func itemReordered(_ id: UUID, action: MoodboardCanvasAction) {
        parent.onItemReordered?(id, action)
    }

    func itemRemoved(_ id: UUID) {
        parent.onItemRemoved?(id)
    }

    func externalDrop(urls: [URL], at point: CGPoint) {
        parent.onExternalDrop?(urls, point)
    }
}
