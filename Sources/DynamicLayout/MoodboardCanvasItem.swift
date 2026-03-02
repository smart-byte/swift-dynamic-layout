//
//  MoodboardCanvasItem.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit
import ImageTools

/// Draggable canvas item with rotation, z-index, and context menu.
/// Styled with shadow and border for a physical photo feel.
/// Corner handles allow rotate+scale via mouse drag.
public class MoodboardCanvasItem: NSView {
    let itemID: UUID
    let imageURL: URL
    var rotationAngle: CGFloat
    var zIndex: Int

    weak var canvas: MoodboardCanvas?

    private var imageView: NSImageView!
    private var dragOrigin: NSPoint = .zero
    private var frameOrigin: NSPoint = .zero

    // MARK: - Handle State

    private enum DragMode {
        case move
        case handleResize(corner: CornerHandle)
    }

    private enum CornerHandle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private static let handleSize: CGFloat = 12
    private static let minItemSize: CGFloat = 40

    private var handleViews: [CornerHandle: NSView] = [:]
    private var handlesVisible = false
    private var dragMode: DragMode = .move

    // State captured at drag start for handle resize
    private var initialFrame: NSRect = .zero
    private var initialRotation: CGFloat = 0
    private var initialDistance: CGFloat = 0
    private var initialAngle: CGFloat = 0

    private var trackingArea: NSTrackingArea?

    init(itemID: UUID, imageURL: URL, frame: NSRect, rotation: CGFloat, zIndex: Int) {
        self.itemID = itemID
        self.imageURL = imageURL
        rotationAngle = rotation
        self.zIndex = zIndex
        super.init(frame: frame)
        setupView()
        loadImage()
        setupHandles()
        setupTrackingArea()
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
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.transform = CATransform3DMakeRotation(rotationAngle, 0, 0, 1)
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

    // MARK: - Corner Handles

    private func setupHandles() {
        for corner in CornerHandle.allCases {
            let handle = NSView(frame: .zero)
            handle.wantsLayer = true
            handle.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            handle.layer?.cornerRadius = Self.handleSize / 2
            handle.layer?.borderColor = NSColor.white.cgColor
            handle.layer?.borderWidth = 1.5
            handle.isHidden = true
            addSubview(handle)
            handleViews[corner] = handle
        }
        layoutHandles()
    }

    private func layoutHandles() {
        let s = Self.handleSize
        let half = s / 2
        let w = bounds.width
        let h = bounds.height

        handleViews[.topLeft]?.frame = NSRect(x: -half, y: -half, width: s, height: s)
        handleViews[.topRight]?.frame = NSRect(x: w - half, y: -half, width: s, height: s)
        handleViews[.bottomLeft]?.frame = NSRect(x: -half, y: h - half, width: s, height: s)
        handleViews[.bottomRight]?.frame = NSRect(x: w - half, y: h - half, width: s, height: s)
    }

    override public func layout() {
        super.layout()
        layoutHandles()
    }

    private func setHandlesVisible(_ visible: Bool) {
        guard handlesVisible != visible else { return }
        handlesVisible = visible
        for (_, handle) in handleViews {
            handle.isHidden = !visible
        }
    }

    // MARK: - Tracking Area (Hover)

    private func setupTrackingArea() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with _: NSEvent) {
        setHandlesVisible(true)
    }

    override public func mouseExited(with _: NSEvent) {
        setHandlesVisible(false)
    }

    // MARK: - Hit Testing for Handles

    private func hitHandle(at point: NSPoint) -> CornerHandle? {
        let hitRadius = Self.handleSize + 4 // slightly larger hit area
        for corner in CornerHandle.allCases {
            guard let handleView = handleViews[corner] else { continue }
            let center = NSPoint(
                x: handleView.frame.midX,
                y: handleView.frame.midY
            )
            let dx = point.x - center.x
            let dy = point.y - center.y
            if sqrt(dx * dx + dy * dy) <= hitRadius {
                return corner
            }
        }
        return nil
    }

    private var itemCenter: NSPoint {
        NSPoint(x: bounds.width / 2, y: bounds.height / 2)
    }

    // MARK: - Mouse Events

    override public func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)

        if let corner = hitHandle(at: localPoint) {
            dragMode = .handleResize(corner: corner)
            initialFrame = frame
            initialRotation = rotationAngle

            // Compute initial vector from frame center to mouse (in superview coordinates)
            let superPoint = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let center = NSPoint(x: frame.midX, y: frame.midY)
            let dx = superPoint.x - center.x
            let dy = superPoint.y - center.y
            initialDistance = sqrt(dx * dx + dy * dy)
            initialAngle = atan2(dy, dx)
        } else {
            dragMode = .move
            dragOrigin = event.locationInWindow
            frameOrigin = frame.origin
        }
    }

    override public func mouseDragged(with event: NSEvent) {
        switch dragMode {
        case .move:
            let current = event.locationInWindow
            let dx = current.x - dragOrigin.x
            let dy = current.y - dragOrigin.y
            setFrameOrigin(NSPoint(x: frameOrigin.x + dx, y: frameOrigin.y + dy))

        case .handleResize:
            let superPoint = superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
            let center = NSPoint(x: frame.midX, y: frame.midY)
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
            applyRotation()

            // Resize centered: keep center stable
            let newX = center.x - newWidth / 2
            let newY = center.y - newHeight / 2
            setFrameSize(NSSize(width: newWidth, height: newHeight))
            setFrameOrigin(NSPoint(x: newX, y: newY))
            layoutHandles()
        }
    }

    override public func mouseUp(with _: NSEvent) {
        switch dragMode {
        case .move:
            canvas?.coordinator?.itemMoved(itemID, to: frame.origin)
        case .handleResize:
            canvas?.coordinator?.itemMoved(itemID, to: frame.origin)
            canvas?.coordinator?.itemRotated(itemID, by: rotationAngle)
            canvas?.coordinator?.itemResized(itemID, to: frame.size)
        }
    }

    // MARK: - Rotation via Trackpad

    override public func rotate(with event: NSEvent) {
        rotationAngle += CGFloat(event.rotation) * (.pi / 180)
        applyRotation()
        canvas?.coordinator?.itemRotated(itemID, by: rotationAngle)
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let bringToFront = NSMenuItem(title: "Bring to Front", action: #selector(bringToFrontAction), keyEquivalent: "")
        bringToFront.target = self
        menu.addItem(bringToFront)

        let sendToBack = NSMenuItem(title: "Send to Back", action: #selector(sendToBackAction), keyEquivalent: "")
        sendToBack.target = self
        menu.addItem(sendToBack)

        menu.addItem(NSMenuItem.separator())

        let remove = NSMenuItem(title: "Remove", action: #selector(removeAction), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)

        return menu
    }

    @objc private func bringToFrontAction() {
        canvas?.coordinator?.itemReordered(itemID, action: .bringToFront)
    }

    @objc private func sendToBackAction() {
        canvas?.coordinator?.itemReordered(itemID, action: .sendToBack)
    }

    @objc private func removeAction() {
        canvas?.coordinator?.itemRemoved(itemID)
    }
}
