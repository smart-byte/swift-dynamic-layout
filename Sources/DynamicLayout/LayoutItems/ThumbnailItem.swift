//
//  ThumbnailItem.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit
import ImageTools

public class ThumbnailItem: NSCollectionViewItem {
    /// Set before accessing `view` — determines the visual style.
    var itemStyle: ItemStyle = .photoFrame

    private var borderImageView: BorderImageView?
    private var plainImageView: NSImageView?
    private var currentURL: URL?
    private var pendingImage: NSImage?

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
        borderImageView?.image = nil
        plainImageView?.image = nil
        isSelected = false
        view.layer?.transform = CATransform3DIdentity
    }

    override public func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.apply(layoutAttributes)
        view.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    // MARK: - View Setup (style-dependent)

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.autoresizesSubviews = true

        // Disable implicit layer animations to prevent fade during drag operations
        view.layer?.actions = [
            "opacity": NSNull(),
            "hidden": NSNull(),
            "onOrderIn": NSNull(),
            "onOrderOut": NSNull(),
            "position": NSNull(),
            "bounds": NSNull(),
            "contents": NSNull(),
            "sublayers": NSNull(),
        ]

        switch itemStyle {
        case .photoFrame:
            setupPhotoFrameStyle()
        case .contactSheet:
            setupContactSheetStyle()
        case .borderless:
            setupBorderlessStyle()
        }
    }

    private func setupPhotoFrameStyle() {
        view.layer?.backgroundColor = .clear

        let imageView = BorderImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        borderImageView = imageView

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.8),
        ])
    }

    private func setupContactSheetStyle() {
        view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        view.layer?.borderWidth = 4.0
        view.layer?.borderColor = .clear

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        plainImageView = imageView

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.95),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.95),
        ])
    }

    private func setupBorderlessStyle() {
        view.layer?.backgroundColor = .clear

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = view.bounds
        view.addSubview(imageView)
        plainImageView = imageView
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        switch itemStyle {
        case .photoFrame:
            view.layer?.cornerRadius = view.bounds.width * 0.1
        case .contactSheet:
            view.layer?.cornerRadius = view.bounds.width * 0.02
        case .borderless:
            view.layer?.cornerRadius = 0
        }
    }

    // MARK: - Configure

    override public func viewDidLoad() {
        super.viewDidLoad()
        if let pendingImage {
            setImage(pendingImage)
            self.pendingImage = nil
        }
    }

    public func configure(with url: URL) {
        currentURL = url

        // Synchronous cache hit → store for viewDidLoad (view may not exist yet)
        if let cached = ImageCache.shared.cachedImage(for: url, maxDimension: 512) {
            if isViewLoaded {
                setImage(cached)
            } else {
                pendingImage = cached
            }
            return
        }

        ImageCache.shared.image(for: url, maxDimension: 512) { [weak self] img in
            DispatchQueue.main.async {
                guard let self, self.currentURL == url else { return }
                self.setImage(img)
            }
        }
    }

    public func configure(with image: NSImage?) {
        setImage(image)
    }

    private func setImage(_ image: NSImage?) {
        if let borderImageView {
            borderImageView.image = image
        } else {
            plainImageView?.image = image
        }
    }

    // MARK: - Selection

    private func updateSelectionAppearance() {
        switch itemStyle {
        case .photoFrame:
            view.layer?.backgroundColor = isSelected ? CGColor(gray: 1, alpha: 0.1) : .clear
        case .contactSheet:
            view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : .clear
        case .borderless:
            view.layer?.borderWidth = isSelected ? 4.0 : 0
            view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : .clear
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
