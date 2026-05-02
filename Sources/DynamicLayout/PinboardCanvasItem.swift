//
//  PinboardCanvasItem.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit
import Foundation
import ImageIO
import ImageTools
import Logging

/// Draggable canvas item with rotation, z-index, and context menu.
/// Styled with shadow and border for a physical photo feel.
/// Corner regions allow rotate+scale via mouse drag.
public class PinboardCanvasItem: NSView {
    let itemID: UUID
    let imageURL: URL
    var rotationAngle: CGFloat
    var zIndex: Int

    weak var canvas: PinboardCanvas?

    /// All visual content (image, white card backing, border, shadow,
    /// selection ring) lives in this sublayer — *not* on `self.layer`.
    /// NSView automatically resets `layer.transform` to identity on
    /// every frame-sync (see AppKit "automatically updates the layer's
    /// transform at appropriate times"), which made our rotation
    /// silently disappear after each layout pass. By moving the
    /// rotation onto a child layer that NSView doesn't own, the
    /// transform is preserved.
    private let contentLayer = CALayer()
    private let imageLayer = CALayer()
    var hasTransparency = false
    var dragOrigin: NSPoint = .zero
    var frameOrigin: NSPoint = .zero

    /// Highlight the item with a selection ring. Driven from
    /// `PinboardCanvasCoordinator.selectedItemIDs` — the coordinator is
    /// the single source of truth, items just reflect what it tells
    /// them.
    var isSelected: Bool = false {
        didSet {
            guard oldValue != isSelected else { return }
            refreshSelectionVisual()
        }
    }

    /// Sublayer (not subview) so the ring inherits the rotation
    /// transform applied to `layer` and stays aligned with the item's
    /// visible edges, no matter the angle.
    private var selectionRingLayer: CAShapeLayer?
    private static let selectionRingOutset: CGFloat = 3
    private static let selectionRingCornerRadius: CGFloat = 6
    private static let selectionRingLineWidth: CGFloat = 2

    // MARK: - Drag State

    enum DragMode {
        case move
        case handleResize
    }

    static let cornerHitRadius: CGFloat = 16
    static let minItemSize: CGFloat = 40

    var dragMode: DragMode = .move

    // State captured at drag start for handle resize
    var initialFrame: NSRect = .zero
    var initialRotation: CGFloat = 0
    var initialDistance: CGFloat = 0
    var initialAngle: CGFloat = 0

    init(itemID: UUID, imageURL: URL, frame: NSRect, rotation: CGFloat, zIndex: Int) {
        self.itemID = itemID
        self.imageURL = imageURL
        rotationAngle = rotation
        self.zIndex = zIndex
        super.init(frame: frame)
        hasTransparency = Self.imageHasTransparency(at: imageURL)
        setupView(transparent: hasTransparency)
        loadImage()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// `wantsLayer = true` defers backing-layer creation to the next
    /// display pass — `applyRotation()` in `setupView` runs *before*
    /// that and silently no-ops on the still-nil layer. By the time
    /// the view is in a window, the real backing layer exists, so
    /// re-apply rotation here.
    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        applyRotation()
        if isSelected { updateSelectionRingPath() }
    }

    private func setupView(transparent: Bool) {
        wantsLayer = true
        // Keep self.layer pristine — NSView resets its transform on
        // every frame-sync, so anything rotation-related must live on
        // a child layer.
        layer?.backgroundColor = NSColor.clear.cgColor

        // Polaroid card affordance lives on contentLayer (so it
        // rotates together with the image), unless the image carries
        // its own alpha — then we drop the card so transparent regions
        // pass through.
        if transparent {
            contentLayer.backgroundColor = NSColor.clear.cgColor
        } else {
            contentLayer.backgroundColor = NSColor.white.cgColor
            contentLayer.borderColor = NSColor.separatorColor.cgColor
            contentLayer.borderWidth = 1
            contentLayer.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
            contentLayer.shadowOffset = NSSize(width: 0, height: -3)
            contentLayer.shadowRadius = 8
            contentLayer.shadowOpacity = 1.0
        }
        contentLayer.actions = ["transform": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(contentLayer)

        // Image content goes inside contentLayer so it inherits the
        // rotation transform without any intermediate NSView in the
        // way.
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        contentLayer.addSublayer(imageLayer)

        layoutContentAndImageLayers(transparent: transparent)
        applyRotation()

        menu = buildContextMenu()
    }

    /// Sync child-layer geometry to the current bounds. `contentLayer`
    /// may already be rotated, so we update it via `bounds` + `position`
    /// instead of `frame` — mutating `frame` on a transformed CALayer
    /// derives through the transform and can skew the border/image
    /// relationship during interactive resize.
    func layoutContentAndImageLayers(transparent: Bool) {
        contentLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let padding: CGFloat = transparent ? 0 : 8
        imageLayer.frame = contentLayer.bounds.insetBy(dx: padding, dy: padding)
    }

    /// Synchronous alpha-channel probe via `CGImageSource`. Reads only
    /// the metadata header (no decode), so it stays cheap even for
    /// large images. Returns `false` for unreadable sources (PDFs,
    /// movies, missing files) — those keep the polaroid look.
    private static func imageHasTransparency(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }
        return (props[kCGImagePropertyHasAlpha] as? Bool) == true
    }

    // MARK: - Selection Ring

    private func refreshSelectionVisual() {
        if isSelected {
            if selectionRingLayer == nil {
                let shape = CAShapeLayer()
                let accent = NSColor.controlAccentColor
                shape.fillColor = accent.withAlphaComponent(0.12).cgColor
                shape.strokeColor = accent.cgColor
                shape.lineWidth = Self.selectionRingLineWidth
                shape.actions = ["path": NSNull(), "hidden": NSNull(), "opacity": NSNull()]
                // Add to contentLayer so the ring rotates with the
                // image. Index 0 means it renders *behind* imageLayer
                // — the semi-transparent fill is meant to peek out
                // around the photo, not over it.
                contentLayer.insertSublayer(shape, at: 0)
                selectionRingLayer = shape
            }
            updateSelectionRingPath()
        } else {
            selectionRingLayer?.removeFromSuperlayer()
            selectionRingLayer = nil
        }
    }

    func updateSelectionRingPath() {
        guard let ring = selectionRingLayer else { return }
        let outset = Self.selectionRingOutset
        let rect = contentLayer.bounds.insetBy(dx: -outset, dy: -outset)
        let radius = Self.selectionRingCornerRadius
        ring.path = CGPath(
            roundedRect: rect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        // Keep the line crisp at the canvas' current magnification by
        // matching the screen's backing-scale.
        ring.contentsScale = window?.backingScaleFactor ?? 2
    }

    func applyRotation() {
        // contentLayer's anchorPoint is (0.5, 0.5) by default, so the
        // transform's origin already sits at the layer's geometric
        // center. A plain rotate is enough — the translate-rotate-
        // translate pattern would rotate around the bottom-right
        // corner instead. (NSView's self.layer is the special case
        // with anchorPoint (0, 0); we don't put the rotation there
        // anyway because of NSView's auto-sync resetting transforms.)
        contentLayer.transform = CATransform3DMakeRotation(rotationAngle, 0, 0, 1)
    }

    /// Snap angle to the nearest 45° increment.
    func snapAngle(_ angle: CGFloat) -> CGFloat {
        let step = CGFloat.pi / 4
        return (angle / step).rounded() * step
    }

    /// Update frame and rotation. Origin-only changes (e.g. a peer
    /// item moving, mid-drag rerenders for stationary siblings) skip
    /// the transform-clear → re-apply dance entirely — `setFrameOrigin`
    /// on a layer-rotated view preserves the rotation in *most* cases,
    /// but NSView's frame-sync occasionally clobbers `layer.transform`
    /// behind our backs, so we re-apply defensively at the end of every
    /// branch.
    func updateFrame(_ newFrame: NSRect, rotation: CGFloat) {
        let sizeChanged = frame.size != newFrame.size
        let rotationChanged = rotationAngle != rotation
        let originChanged = frame.origin != newFrame.origin

        Logger(label: "voila.pinboard").debug(
            """
            updateFrame item=\(itemID.uuidString.prefix(8)) currentRot=\(rotationAngle) \
            targetRot=\(rotation) sizeChanged=\(sizeChanged) rotChanged=\(rotationChanged) \
            originChanged=\(originChanged)
            """
        )

        if !sizeChanged, !rotationChanged {
            if originChanged {
                setFrameOrigin(newFrame.origin)
            }
            applyRotation()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = newFrame
        rotationAngle = rotation
        layoutContentAndImageLayers(transparent: hasTransparency)
        applyRotation()
        if isSelected { updateSelectionRingPath() }
        CATransaction.commit()
    }

    func updateZIndex(_ newIndex: Int) {
        zIndex = newIndex
    }

    private func loadImage() {
        ImageCache.shared.image(for: imageURL, maxDimension: 512) { [weak self] img in
            DispatchQueue.main.async {
                guard let self, let img else { return }
                // CALayer wants a CGImage, not an NSImage.
                self.imageLayer.contents = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
        }
    }

    // MARK: - Hit Testing (rotation-aware via CALayer)

    /// Convert a window-coordinate event to this item's content-layer
    /// coordinate system, correctly accounting for the rotation
    /// transform (which lives on `contentLayer`, not `self.layer`).
    func localPointFromEvent(_ event: NSEvent) -> NSPoint {
        guard let superLayer = superview?.layer else {
            return convert(event.locationInWindow, from: nil)
        }
        let superPoint = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return contentLayer.convert(superPoint, from: superLayer)
    }

    /// Check if a local point is near any corner of the item bounds.
    func isNearCorner(_ point: NSPoint) -> Bool {
        let r = Self.cornerHitRadius
        let w = bounds.width
        let h = bounds.height
        let corners: [NSPoint] = [
            NSPoint(x: 0, y: 0),
            NSPoint(x: w, y: 0),
            NSPoint(x: 0, y: h),
            NSPoint(x: w, y: h),
        ]
        return corners.contains { corner in
            hypot(point.x - corner.x, point.y - corner.y) <= r
        }
    }

    /// Hit-test accounting for rotation so clicks land on the actual
    /// visual rect. Conversion goes through `contentLayer` because
    /// that's where the rotation transform lives.
    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard let superLayer = superview?.layer else {
            return super.hitTest(point)
        }
        let localPoint = contentLayer.convert(point, from: superLayer)
        let padding = Self.cornerHitRadius
        let hitRect = bounds.insetBy(dx: -padding, dy: -padding)
        return hitRect.contains(localPoint) ? self : nil
    }
}
