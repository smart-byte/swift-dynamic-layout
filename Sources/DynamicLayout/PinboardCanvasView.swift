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
    let onEvent: ((PinboardCanvasEvent) -> Void)?
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
        onEvent: ((PinboardCanvasEvent) -> Void)? = nil,
        onZoomChanged: ((CGFloat) -> Void)? = nil,
        onScrollChanged: ((_ origin: CGPoint, _ visibleSize: CGSize) -> Void)? = nil,
        scrollTarget: Binding<CGPoint?> = .constant(nil)
    ) {
        self.items = items
        self.onEvent = onEvent
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
        let currentIDs = Set(items.map(\.id))

        // Remove stale items.
        canvas.forEachItem { item in
            guard !currentIDs.contains(item.itemID) else { return }
            canvas.removeItem(withID: item.itemID)
        }

        // Add or update items. `updateFrame` itself decides whether
        // anything actually needs touching — origin-only changes go
        // through a fast path that doesn't reset the layer transform,
        // so peer items don't flicker to 0° while one item is being
        // dragged.
        for data in items {
            if let existing = canvas.item(for: data.id) {
                let targetFrame = data.frame
                existing.updateFrame(targetFrame, rotation: data.rotation)
                existing.updateZIndex(Int(data.zIndex))
            } else {
                let item = PinboardCanvasItem(
                    itemID: data.id,
                    imageURL: data.fileURL,
                    frame: data.frame,
                    rotation: data.rotation,
                    zIndex: Int(data.zIndex)
                )
                item.canvas = canvas
                item.isSelected = contextSelectionState(for: data.id, canvas: canvas)
                canvas.registerItem(item)
                canvas.addSubview(item)
            }
        }

        canvas.syncZOrder(using: items)
    }

    private func contextSelectionState(for id: UUID, canvas: PinboardCanvas) -> Bool {
        canvas.coordinator?.isItemSelected(id) ?? false
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

    var frame: CGRect {
        CGRect(
            x: positionX,
            y: positionY,
            width: width,
            height: height
        )
    }
}

public enum PinboardCanvasAction {
    case bringToFront
    case sendToBack
}

public enum PinboardCanvasEvent {
    case itemChanged(UUID, PinboardItemChange, PinboardGesturePhase)
    case itemReordered(UUID, PinboardCanvasAction)
    case itemRemoved(UUID)
    case externalDrop(urls: [URL], at: CGPoint, imageSize: CGSize?)
}

public struct PinboardItemChange {
    public var position: CGPoint?
    public var size: CGSize?
    public var rotation: CGFloat?

    public init(
        position: CGPoint? = nil,
        size: CGSize? = nil,
        rotation: CGFloat? = nil
    ) {
        self.position = position
        self.size = size
        self.rotation = rotation
    }
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
    /// Process-local selection state. Lives on the coordinator so a
    /// reflow of the SwiftUI parent doesn't reset what the user picked
    /// (selection isn't persisted across launches).
    private var selectedItemIDs: Set<UUID> = []
    /// Last reported scroll origin/size — used by `reportScrollState`
    /// to swallow no-op notifications. Without dedup, every layout
    /// pass during a drag can re-fire bounds notifications that
    /// mutate the host's `@State` viewportOrigin/Size, retriggering
    /// SwiftUI rerenders → updateCanvas → updateFrame for every item
    /// → layout pass. That's the "items snap to 0° as soon as I drag
    /// one" cycle.
    private var lastReportedOrigin: CGPoint?
    private var lastReportedSize: CGSize?

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
    /// Deduplicates: the host stores the values in `@State`, so firing
    /// with unchanged values would still trigger SwiftUI rerenders and
    /// can establish a feedback loop with the layout system during
    /// drag interactions.
    private func reportScrollState(in sv: NSScrollView) {
        let clip = sv.contentView
        // `clipView.bounds` is already in document (canvas) coordinates —
        // NSScrollView accounts for magnification internally so the bounds
        // size shrinks on zoom-in and grows on zoom-out. No further math
        // is needed; dividing by magnification would double-apply the
        // scale factor and produce a visibly mis-sized viewport rect.
        let origin = clip.bounds.origin
        let size = clip.bounds.size
        if let lastOrigin = lastReportedOrigin, let lastSize = lastReportedSize,
           lastOrigin == origin, lastSize == size
        {
            return
        }
        lastReportedOrigin = origin
        lastReportedSize = size
        parent.onScrollChanged?(origin, size)
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

    func itemChanged(_ id: UUID, change: PinboardItemChange, phase: PinboardGesturePhase) {
        parent.onEvent?(.itemChanged(id, change, phase))
    }

    func itemMoved(_ id: UUID, to point: CGPoint, phase: PinboardGesturePhase) {
        itemChanged(id, change: PinboardItemChange(position: point), phase: phase)
    }

    func itemRotated(_ id: UUID, by angle: CGFloat, phase: PinboardGesturePhase) {
        itemChanged(id, change: PinboardItemChange(rotation: angle), phase: phase)
    }

    func itemResized(_ id: UUID, to size: CGSize, phase: PinboardGesturePhase) {
        itemChanged(id, change: PinboardItemChange(size: size), phase: phase)
    }

    func itemReordered(_ id: UUID, action: PinboardCanvasAction) {
        parent.onEvent?(.itemReordered(id, action))
    }

    func itemRemoved(_ id: UUID) {
        parent.onEvent?(.itemRemoved(id))
    }

    func externalDrop(urls: [URL], at point: CGPoint, imageSize: CGSize?) {
        parent.onEvent?(.externalDrop(urls: urls, at: point, imageSize: imageSize))
    }

    // MARK: - Selection

    /// Promote `id` to the active selection. `additive == true` toggles
    /// it in place (Cmd+Click), otherwise the selection collapses to
    /// just this item.
    func selectItem(_ id: UUID, additive: Bool) {
        if additive {
            if selectedItemIDs.contains(id) {
                selectedItemIDs.remove(id)
            } else {
                selectedItemIDs.insert(id)
            }
        } else {
            selectedItemIDs = [id]
        }
        applySelectionToItems()
    }

    func deselectAll() {
        guard !selectedItemIDs.isEmpty else { return }
        selectedItemIDs.removeAll()
        applySelectionToItems()
    }

    func isItemSelected(_ id: UUID) -> Bool {
        selectedItemIDs.contains(id)
    }

    /// Walks the canvas' item subviews and pushes each one's selected
    /// state. Cheap because `PinboardCanvasItem.isSelected` short-
    /// circuits when the value doesn't change.
    private func applySelectionToItems() {
        guard let canvas else { return }
        canvas.forEachItem { item in
            item.isSelected = selectedItemIDs.contains(item.itemID)
        }
    }
}
