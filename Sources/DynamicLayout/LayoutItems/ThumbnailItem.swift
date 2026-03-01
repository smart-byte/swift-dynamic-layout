//
//  ThumbnailItem.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit
import ImageTools

public class ThumbnailItem: NSCollectionViewItem {
    var contentImageView: BorderImageView!
    private var currentURL: URL?

    override init(nibName _: NSNib.Name?, bundle _: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()
        currentURL = nil
        contentImageView.image = nil
        isSelected = false
        view.layer?.transform = CATransform3DIdentity
    }

    override public func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        view.layer?.transform = CATransform3DIdentity
    }

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.masksToBounds = true
        view.autoresizesSubviews = true

        contentImageView = BorderImageView()
        contentImageView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(contentImageView)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            contentImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.8),
        ])
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        view.layer?.cornerRadius = view.bounds.width * 0.1
    }

    public func configure(with url: URL) {
        currentURL = url
        ImageCache.shared.image(for: url, maxDimension: 512) { [weak self] img in
            DispatchQueue.main.async {
                // Only apply if this cell still shows the same URL (not reused)
                guard let self, self.currentURL == url else { return }
                self.contentImageView.image = img
            }
        }
    }

    public func configure(with image: NSImage?) {
        contentImageView.image = image
    }

    private func updateSelectionAppearance() {
        if isSelected {
            view.layer?.backgroundColor = CGColor(gray: 1, alpha: 0.1)
        } else {
            view.layer?.backgroundColor = .clear
        }
    }
}

class BorderImageView: NSView {
    private var borderImageView = NSImageView()

    var image: NSImage? {
        didSet {
            borderImageView.image = image?.withRelativeBorderAndThinBorder(percentage: 0.08, borderColor: overlayColor, borderWidthPercentage: 0.005)
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
}

extension NSImage {
    func withRelativeBorderAndThinBorder(percentage: CGFloat, borderColor: NSColor, borderWidthPercentage: CGFloat, borderAlpha: CGFloat = 0.2) -> NSImage {
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
