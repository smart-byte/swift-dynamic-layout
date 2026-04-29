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
    /// Called for every drag tick (`.changed`) plus a final `.ended` on
    /// release. Hosts typically maintain a transient overlay on
    /// `.changed` and persist on `.ended`.
    let onItemMoved: ((UUID, CGPoint, PinboardGesturePhase) -> Void)?
    let onItemRotated: ((UUID, CGFloat) -> Void)?
    let onItemResized: ((UUID, CGSize) -> Void)?
    let onItemReordered: ((UUID, PinboardCanvasAction) -> Void)?
    let onItemRemoved: ((UUID) -> Void)?
    let onExternalDrop: (([URL], CGPoint, CGSize?) -> Void)?
    let onZoomChanged: ((CGFloat) -> Void)?
    /// Fires whenever the scroll position or magnification changes.
    /// Both `origin` and `visibleSize` are in canvas coordinates; AppKit
    /// already accounts for magnification on `clipView.bounds`.
    let onScrollChanged: ((_ origin: CGPoint, _ visibleSize: CGSize) -> Void)?
    /// When non-nil, the canvas smoothly scrolls so this point becomes the
    /// new top-left of the visible region. `PinboardView` sets this from the
    /// mini-map's `onScrollTo` callback, then immediately resets it to nil.
    @Binding var scrollTarget: CGPoint?

    public init(
        items: [PinboardCanvasItemData],
        onItemMoved: ((UUID, CGPoint, PinboardGesturePhase) -> Void)? = nil,
        onItemRotated: ((UUID, CGFloat) -> Void)? = nil,
        onItemResized: ((UUID, CGSize) -> Void)? = nil,
        onItemReordered: ((UUID, PinboardCanvasAction) -> Void)? = nil,
        onItemRemoved: ((UUID) -> Void)? = nil,
        onExternalDrop: (([URL], CGPoint, CGSize?) -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil,
        onScrollChanged: ((_ origin: CGPoint, _ visibleSize: CGSize) -> Void)? = nil,
        scrollTarget: Binding<CGPoint?> = .constant(nil)
    ) {
        self.items = items
        self.onItemMoved = onItemMoved
        self.onItemRotated = onItemRotated
        self.onItemResized = onItemResized
        self.onItemReordered = onItemReordered
        self.onItemRemoved = onItemRemoved
        self.onExternalDrop = onExternalDrop
        self.onZoomChanged = onZoomChanged
        self.onScrollChanged = onScrollChanged
        _scrollTarget = scrollTarget
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
        // Subscribe to clip-view bounds changes so the mini-map updates
        // live during scroll and zoom.
        context.coordinator.observeScroll(in: scrollView)

        updateCanvas(canvas, with: items)

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let canvas = nsView.documentView as? PinboardCanvas else { return }
        context.coordinator.parent = self
        updateCanvas(canvas, with: items)

        // Apply scroll command from the mini-map (tap or drag-pan).
        if let target = scrollTarget {
            context.coordinator.scrollTo(target, in: nsView)
            // Reset immediately; the binding write triggers another updateNSView
            // pass but scrollTarget will be nil then, so there is no loop.
            DispatchQueue.main.async {
                scrollTarget = nil
            }
        }
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

/// Lifecycle phase of a continuous interaction (drag, resize, …).
///
/// Hosts use it to skip expensive side-effects (Core Data writes,
/// undo-grouping, …) on every intermediate tick and only commit on
/// `.ended`, while still updating cheap UI surfaces (mini-map dots) on
/// every `.changed`.
public enum PinboardGesturePhase: Sendable {
    case changed
    case ended
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

    /// Subscribe to clip-view bounds changes for live scroll/pan updates.
    /// We listen to both `boundsDidChange` (scroll origin / magnification)
    /// **and** `frameDidChange` (window or pane resize) so the mini-map's
    /// viewport rectangle stays accurate in every interaction path.
    func observeScroll(in scrollView: NSScrollView) {
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        clip.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        for name in [
            NSView.boundsDidChangeNotification,
            NSView.frameDidChangeNotification,
        ] {
            center.addObserver(
                self,
                selector: #selector(clipBoundsChanged(_:)),
                name: name,
                object: clip
            )
        }
    }

    @objc private func magnificationDidEnd(_ notification: Notification) {
        guard let sv = notification.object as? NSScrollView else { return }
        parent.onZoomChanged?(sv.magnification)
        reportScrollState(in: sv)
    }

    @objc private func clipBoundsChanged(_: Notification) {
        guard let sv = scrollView else { return }
        reportScrollState(in: sv)
    }

    /// Computes the current viewport origin and visible size in canvas
    /// coordinates and forwards them via `onScrollChanged`.
    private func reportScrollState(in sv: NSScrollView) {
        let clip = sv.contentView
        // `clipView.bounds` is already in document (canvas) coordinates —
        // NSScrollView accounts for magnification internally so the bounds
        // size shrinks on zoom-in and grows on zoom-out. No further math
        // is needed; dividing by magnification would double-apply the
        // scale factor and produce a visibly mis-sized viewport rect.
        parent.onScrollChanged?(clip.bounds.origin, clip.bounds.size)
    }

    func zoomChanged(_ magnification: CGFloat) {
        parent.onZoomChanged?(magnification)
        if let sv = scrollView { reportScrollState(in: sv) }
    }

    /// Smoothly scrolls the canvas so `origin` becomes the top-left of the
    /// visible region. Uses `NSAnimationContext` for an AppKit-native spring.
    func scrollTo(_ origin: CGPoint, in scrollView: NSScrollView) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func itemMoved(_ id: UUID, to point: CGPoint, phase: PinboardGesturePhase) {
        parent.onItemMoved?(id, point, phase)
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
