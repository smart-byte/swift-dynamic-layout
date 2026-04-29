//
//  PinboardCanvasItem.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit
import ImageTools

/// Draggable canvas item with rotation, z-index, and context menu.
/// Styled with shadow and border for a physical photo feel.
/// Corner regions allow rotate+scale via mouse drag.
public class PinboardCanvasItem: NSView {
    let itemID: UUID
    let imageURL: URL
    var rotationAngle: CGFloat
    var zIndex: Int

    weak var canvas: PinboardCanvas?

    private var imageView: NSImageView!
    private var dragOrigin: NSPoint = .zero
    private var frameOrigin: NSPoint = .zero

    // MARK: - Drag State

    private enum DragMode {
        case move
        case handleResize
    }

    private static let cornerHitRadius: CGFloat = 16
    private static let minItemSize: CGFloat = 40

    private var dragMode: DragMode = .move

    // State captured at drag start for handle resize
    private var initialFrame: NSRect = .zero
    private var initialRotation: CGFloat = 0
    private var initialDistance: CGFloat = 0
    private var initialAngle: CGFloat = 0

    init(itemID: UUID, imageURL: URL, frame: NSRect, rotation: CGFloat, zIndex: Int) {
        self.itemID = itemID
        self.imageURL = imageURL
        rotationAngle = rotation
        self.zIndex = zIndex
        super.init(frame: frame)
        setupView()
        loadImage()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        // Shadow for photo feel
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 8
        self.shadow = shadow

        // Image view with padding (photo border)
        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        let padding: CGFloat = 8
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
        ])

        applyRotation()

        // Context menu
        menu = buildContextMenu()
    }

    private func applyRotation() {
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        var t = CATransform3DIdentity
        t = CATransform3DTranslate(t, cx, cy, 0)
        t = CATransform3DRotate(t, rotationAngle, 0, 0, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        layer?.transform = t
    }

    /// Snap angle to the nearest 45° increment.
    private func snapAngle(_ angle: CGFloat) -> CGFloat {
        let step = CGFloat.pi / 4
        return (angle / step).rounded() * step
    }

    /// Update frame and rotation cleanly (clears transform, sets frame, re-applies).
    func updateFrame(_ newFrame: NSRect, rotation: CGFloat) {
        layer?.transform = CATransform3DIdentity
        frame = newFrame
        rotationAngle = rotation
        applyRotation()
    }

    func updateZIndex(_ newIndex: Int) {
        zIndex = newIndex
    }

    private func loadImage() {
        ImageCache.shared.image(for: imageURL, maxDimension: 512) { [weak self] img in
            DispatchQueue.main.async {
                self?.imageView.image = img
            }
        }
    }

    // MARK: - Hit Testing (rotation-aware via CALayer)

    /// Convert a window-coordinate event to this view's local coordinate system,
    /// correctly accounting for the active layer rotation transform.
    private func localPointFromEvent(_ event: NSEvent) -> NSPoint {
        guard let myLayer = layer, let superLayer = superview?.layer else {
            return convert(event.locationInWindow, from: nil)
        }
        let superPoint = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        return myLayer.convert(superPoint, from: superLayer)
    }

    /// Check if a local point is near any corner of the item bounds.
    private func isNearCorner(_ point: NSPoint) -> Bool {
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

    /// Hit-test accounting for rotation so clicks land on the actual visual rect.
    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard let myLayer = layer, let superLayer = superview?.layer else {
            return super.hitTest(point)
        }
        let localPoint = myLayer.convert(point, from: superLayer)
        let padding = Self.cornerHitRadius
        let hitRect = bounds.insetBy(dx: -padding, dy: -padding)
        return hitRect.contains(localPoint) ? self : nil
    }

    // MARK: - Mouse Events

    override public func mouseDown(with event: NSEvent) {
        let localPt = localPointFromEvent(event)

        if isNearCorner(localPt) {
            dragMode = .handleResize
            initialRotation = rotationAngle

            // Read frame without rotation transform for stable reference
            layer?.transform = CATransform3DIdentity
            initialFrame = frame
            applyRotation()

            // Compute initial vector from frame center to mouse (in superview coordinates)
            let superPoint = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let center = NSPoint(x: initialFrame.midX, y: initialFrame.midY)
            let dx = superPoint.x - center.x
            let dy = superPoint.y - center.y
            initialDistance = sqrt(dx * dx + dy * dy)
            initialAngle = atan2(dy, dx)
        } else {
            dragMode = .move
            dragOrigin = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            layer?.transform = CATransform3DIdentity
            frameOrigin = frame.origin
            applyRotation()
        }
    }

    override public func mouseDragged(with event: NSEvent) {
        switch dragMode {
        case .move:
            let current = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let dx = current.x - dragOrigin.x
            let dy = current.y - dragOrigin.y
            layer?.transform = CATransform3DIdentity
            setFrameOrigin(NSPoint(x: frameOrigin.x + dx, y: frameOrigin.y + dy))
            applyRotation()

        case .handleResize:
            let superPoint = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let center = NSPoint(x: initialFrame.midX, y: initialFrame.midY)
            let dx = superPoint.x - center.x
            let dy = superPoint.y - center.y
            let currentDistance = sqrt(dx * dx + dy * dy)
            let currentAngle = atan2(dy, dx)

            // Scale: ratio of distances
            guard initialDistance > 0 else { return }
            let scaleFactor = currentDistance / initialDistance
            var newWidth = initialFrame.width * scaleFactor
            var newHeight = initialFrame.height * scaleFactor

            // Enforce minimum size
            newWidth = max(newWidth, Self.minItemSize)
            newHeight = max(newHeight, Self.minItemSize)

            // Rotation: angle delta
            let angleDelta = currentAngle - initialAngle
            rotationAngle = initialRotation + angleDelta
            if event.modifierFlags.contains(.shift) {
                rotationAngle = snapAngle(rotationAngle)
            }

            // Clear transform before frame changes
            layer?.transform = CATransform3DIdentity
            let newX = center.x - newWidth / 2
            let newY = center.y - newHeight / 2
            setFrameSize(NSSize(width: newWidth, height: newHeight))
            setFrameOrigin(NSPoint(x: newX, y: newY))
            applyRotation()
        }
    }

    override public func mouseUp(with _: NSEvent) {
        layer?.transform = CATransform3DIdentity
        let cleanOrigin = frame.origin
        let cleanSize = frame.size
        applyRotation()

        switch dragMode {
        case .move:
            canvas?.coordinator?.itemMoved(itemID, to: cleanOrigin)
        case .handleResize:
            canvas?.coordinator?.itemMoved(itemID, to: cleanOrigin)
            canvas?.coordinator?.itemRotated(itemID, by: rotationAngle)
            canvas?.coordinator?.itemResized(itemID, to: cleanSize)
        }
    }

    // MARK: - Rotation via Trackpad

    override public func rotate(with event: NSEvent) {
        rotationAngle -= CGFloat(event.rotation) * (.pi / 180)
        if event.modifierFlags.contains(.shift) {
            rotationAngle = snapAngle(rotationAngle)
        }
        applyRotation()
        canvas?.coordinator?.itemRotated(itemID, by: rotationAngle)
    }
}
