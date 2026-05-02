//
//  BorderImageView.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit

class BorderImageView: NSView {
    private var borderImageView = NSImageView()

    var image: NSImage? {
        didSet {
            borderImageView.image = image?.withRelativeBorderAndThinBorder(
                percentage: 0.08,
                borderColor: overlayColor,
                borderWidthPercentage: 0.005
            )
        }
    }

    var overlayColor: NSColor = .white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupImageView()
        configureShadow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupImageView()
        configureShadow()
    }

    private func setupImageView() {
        borderImageView.autoresizingMask = [.width, .height]
        borderImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(borderImageView)
    }

    private func configureShadow() {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = calculateShadowOffset()
        shadow.shadowBlurRadius = calculateShadowBlurRadius()
        borderImageView.shadow = shadow
    }

    private func calculateShadowBlurRadius() -> CGFloat {
        (bounds.width + bounds.height) / 2 * 0.02
    }

    private func calculateShadowOffset() -> NSSize {
        NSSize(width: 0, height: -(bounds.width + bounds.height) / 2 * 0.01)
    }

    override func layout() {
        super.layout()
        configureShadow()
    }
}

extension NSImage {
    func withRelativeBorder(percentage: CGFloat, color: NSColor) -> NSImage {
        let border = (size.width + size.height) / 2.0 * percentage

        let newSize = CGSize(width: size.width + border * 2, height: size.height + border * 2)
        let newImage = NSImage(size: newSize)
        let frame = NSRect(origin: CGPoint(x: border, y: border), size: size)

        newImage.lockFocus()
        color.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()
        draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1.0)
        newImage.unlockFocus()

        return newImage
    }

    func withRelativeBorderAndThinBorder(
        percentage: CGFloat,
        borderColor: NSColor,
        borderWidthPercentage: CGFloat,
        borderAlpha: CGFloat = 0.2
    ) -> NSImage {
        let border = (size.width + size.height) / 2.0 * percentage
        let borderWidth = (size.width + size.height) / 2.0 * borderWidthPercentage

        let newSize = CGSize(width: size.width + border * 2, height: size.height + border * 2)
        let newImage = NSImage(size: newSize)
        let frame = NSRect(origin: CGPoint(x: border, y: border), size: size)

        newImage.lockFocus()

        borderColor.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: newSize)).fill()

        draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1.0)

        NSColor(calibratedWhite: 0.0, alpha: borderAlpha).set()
        let borderPath = NSBezierPath(rect: frame.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2))
        borderPath.lineWidth = borderWidth
        borderPath.stroke()

        newImage.unlockFocus()

        return newImage
    }
}
