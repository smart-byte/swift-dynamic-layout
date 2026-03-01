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
public class MoodboardCanvasItem: NSView {
    let itemID: UUID
    let imageURL: URL
    var rotationAngle: CGFloat
    var zIndex: Int

    weak var canvas: MoodboardCanvas?

    private var imageView: NSImageView!
    private var dragOrigin: NSPoint = .zero
    private var frameOrigin: NSPoint = .zero

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
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)
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

    // MARK: - Drag to Move

    override public func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        frameOrigin = frame.origin
    }

    override public func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let dx = current.x - dragOrigin.x
        let dy = current.y - dragOrigin.y

        setFrameOrigin(NSPoint(x: frameOrigin.x + dx, y: frameOrigin.y + dy))
    }

    override public func mouseUp(with _: NSEvent) {
        canvas?.coordinator?.itemMoved(itemID, to: frame.origin)
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
