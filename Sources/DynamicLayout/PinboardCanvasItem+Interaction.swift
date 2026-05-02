//
//  PinboardCanvasItem+Interaction.swift
//
//
//  Created by Mario Heubach on 02.05.26.
//

import AppKit

extension PinboardCanvasItem {
    // MARK: - Mouse Events

    override public func mouseDown(with event: NSEvent) {
        // Selection precedes drag/resize: every mouseDown promotes this
        // item to the active selection (Cmd toggles additively, like
        // NSCollectionView). Doing this *before* the drag-mode branch
        // means a click-and-drag still leaves the item selected on
        // mouseUp without a separate code path.
        let additive = event.modifierFlags.contains(.command)
        canvas?.coordinator?.selectItem(itemID, additive: additive)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let localPoint = localPointFromEvent(event)
        if isNearCorner(localPoint) {
            beginHandleResize(with: event)
        } else {
            beginMove(with: event)
        }
    }

    override public func mouseDragged(with event: NSEvent) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch dragMode {
        case .move:
            updateMove(with: event)
        case .handleResize:
            updateHandleResize(with: event)
        }
    }

    override public func mouseUp(with _: NSEvent) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let cleanOrigin = frame.origin
        let cleanSize = frame.size
        applyRotation()
        CATransaction.commit()

        switch dragMode {
        case .move:
            canvas?.coordinator?.itemMoved(itemID, to: cleanOrigin, phase: .ended)
        case .handleResize:
            canvas?.coordinator?.itemChanged(
                itemID,
                change: PinboardItemChange(
                    position: cleanOrigin,
                    size: cleanSize,
                    rotation: rotationAngle
                ),
                phase: .ended
            )
        }
    }

    // MARK: - Rotation via Trackpad

    override public func rotate(with event: NSEvent) {
        rotationAngle -= CGFloat(event.rotation) * (.pi / 180)
        if event.modifierFlags.contains(.shift) {
            rotationAngle = snapAngle(rotationAngle)
        }
        applyRotation()
        canvas?.coordinator?.itemRotated(itemID, by: rotationAngle, phase: gesturePhase(for: event))
    }

    // MARK: - Interaction Helpers

    func superviewPoint(from event: NSEvent) -> NSPoint {
        superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
    }

    func beginMove(with event: NSEvent) {
        dragMode = .move
        dragOrigin = superviewPoint(from: event)
        frameOrigin = frame.origin
    }

    func beginHandleResize(with event: NSEvent) {
        dragMode = .handleResize
        initialRotation = rotationAngle
        initialFrame = frame

        let superPoint = superviewPoint(from: event)
        let center = itemCenter(for: initialFrame)
        let dx = superPoint.x - center.x
        let dy = superPoint.y - center.y
        initialDistance = sqrt(dx * dx + dy * dy)
        initialAngle = atan2(dy, dx)
    }

    func updateMove(with event: NSEvent) {
        let current = superviewPoint(from: event)
        let deltaX = current.x - dragOrigin.x
        let deltaY = current.y - dragOrigin.y
        let newOrigin = NSPoint(x: frameOrigin.x + deltaX, y: frameOrigin.y + deltaY)
        setFrameOrigin(newOrigin)
        applyRotation()
        canvas?.coordinator?.itemMoved(itemID, to: newOrigin, phase: .changed)
    }

    func updateHandleResize(with event: NSEvent) {
        let superPoint = superviewPoint(from: event)
        let center = itemCenter(for: initialFrame)
        let dx = superPoint.x - center.x
        let dy = superPoint.y - center.y
        let currentDistance = sqrt(dx * dx + dy * dy)
        let currentAngle = atan2(dy, dx)

        guard initialDistance > 0 else { return }

        let minimumScale = Self.minItemSize / initialFrame.width
        let scaleFactor = max(currentDistance / initialDistance, minimumScale)
        let newSize = CGSize(
            width: max(initialFrame.width * scaleFactor, Self.minItemSize),
            height: max(initialFrame.height * scaleFactor, Self.minItemSize)
        )

        // Invert the delta so the handle motion matches the visual
        // "grab the corner and turn it" direction on a flipped canvas.
        let angleDelta = initialAngle - currentAngle
        rotationAngle = initialRotation + angleDelta
        if event.modifierFlags.contains(.shift) {
            rotationAngle = snapAngle(rotationAngle)
        }

        applyResize(to: newSize, centeredAt: center)
        canvas?.coordinator?.itemChanged(
            itemID,
            change: PinboardItemChange(
                position: frame.origin,
                size: frame.size,
                rotation: rotationAngle
            ),
            phase: .changed
        )
    }

    func itemCenter(for frame: NSRect) -> NSPoint {
        NSPoint(x: frame.midX, y: frame.midY)
    }

    func applyResize(to size: CGSize, centeredAt center: NSPoint) {
        let newOrigin = NSPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
        )
        setFrameSize(size)
        setFrameOrigin(newOrigin)
        layoutContentAndImageLayers(transparent: hasTransparency)
        applyRotation()
        if isSelected { updateSelectionRingPath() }
    }

    func gesturePhase(for event: NSEvent) -> PinboardGesturePhase {
        switch event.phase {
        case .ended, .cancelled:
            .ended
        default:
            .changed
        }
    }
}
