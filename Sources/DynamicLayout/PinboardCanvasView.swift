//
//  PinboardCanvasView.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import SwiftUI

/// NSViewRepresentable wrapping a PinboardCanvas inside an NSScrollView.
/// Supports magnification (0.25x–4x) and drag & drop from Finder.
public struct PinboardCanvasView: NSViewRepresentable {
    let items: [PinboardCanvasItemData]
    let onItemMoved: ((UUID, CGPoint) -> Void)?
    let onItemRotated: ((UUID, CGFloat) -> Void)?
    let onItemResized: ((UUID, CGSize) -> Void)?
    let onItemReordered: ((UUID, PinboardCanvasAction) -> Void)?
    let onItemRemoved: ((UUID) -> Void)?
    let onExternalDrop: (([URL], CGPoint, CGSize?) -> Void)?
    let onZoomChanged: ((CGFloat) -> Void)?

    public init(
        items: [PinboardCanvasItemData],
        onItemMoved: ((UUID, CGPoint) -> Void)? = nil,
        onItemRotated: ((UUID, CGFloat) -> Void)? = nil,
        onItemResized: ((UUID, CGSize) -> Void)? = nil,
        onItemReordered: ((UUID, PinboardCanvasAction) -> Void)? = nil,
        onItemRemoved: ((UUID) -> Void)? = nil,
        onExternalDrop: (([URL], CGPoint, CGSize?) -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil
    ) {
        self.items = items
        self.onItemMoved = onItemMoved
        self.onItemRotated = onItemRotated
        self.onItemResized = onItemResized
        self.onItemReordered = onItemReordered
        self.onItemRemoved = onItemRemoved
        self.onExternalDrop = onExternalDrop
        self.onZoomChanged = onZoomChanged
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let canvas = PinboardCanvas(frame: NSRect(x: 0, y: 0, width: 4000, height: 4000))
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

        // Register for drag & drop on the canvas itself
        canvas.registerForDraggedTypes([.fileURL])

        // Surface trackpad-pinch magnification changes to the host —
        // the `⌥`+scroll path fires the callback inline in
        // `PinboardCanvas.scrollWheel`, so this notification covers
        // the native pinch gesture and any other scroll-view source.
        context.coordinator.observeMagnification(in: scrollView)

        updateCanvas(canvas, with: items)

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let canvas = nsView.documentView as? PinboardCanvas else { return }
        context.coordinator.parent = self
        updateCanvas(canvas, with: items)
    }

    public func makeCoordinator() -> PinboardCanvasCoordinator {
        PinboardCanvasCoordinator(self)
    }

    private func updateCanvas(_ canvas: PinboardCanvas, with items: [PinboardCanvasItemData]) {
        // Remove stale items
        let currentIDs = Set(items.map(\.id))
        for subview in canvas.subviews {
            if let item = subview as? PinboardCanvasItem, !currentIDs.contains(item.itemID) {
                item.removeFromSuperview()
            }
        }

        // Add or update items
        for data in items {
            if let existing = canvas.subviews.compactMap({ $0 as? PinboardCanvasItem }).first(where: { $0.itemID == data.id }) {
                existing.updateFrame(
                    NSRect(x: data.positionX, y: data.positionY, width: data.width, height: data.height),
                    rotation: data.rotation
                )
                existing.updateZIndex(Int(data.zIndex))
            } else {
                let item = PinboardCanvasItem(
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

public struct PinboardCanvasItemData: Identifiable {
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

public enum PinboardCanvasAction {
    case bringToFront
    case sendToBack
}

// MARK: - Coordinator

public class PinboardCanvasCoordinator: NSObject {
    var parent: PinboardCanvasView
    weak var canvas: PinboardCanvas?
    weak var scrollView: NSScrollView?

    init(_ parent: PinboardCanvasView) {
        self.parent = parent
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func observeMagnification(in scrollView: NSScrollView) {
        self.scrollView = scrollView
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(magnificationDidEnd(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
    }

    @objc private func magnificationDidEnd(_ notification: Notification) {
        guard let sv = notification.object as? NSScrollView else { return }
        parent.onZoomChanged?(sv.magnification)
    }

    func zoomChanged(_ magnification: CGFloat) {
        parent.onZoomChanged?(magnification)
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

    func itemReordered(_ id: UUID, action: PinboardCanvasAction) {
        parent.onItemReordered?(id, action)
    }

    func itemRemoved(_ id: UUID) {
        parent.onItemRemoved?(id)
    }

    func externalDrop(urls: [URL], at point: CGPoint, imageSize: CGSize?) {
        parent.onExternalDrop?(urls, point, imageSize)
    }
}
