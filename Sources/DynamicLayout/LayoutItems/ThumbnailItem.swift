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
    /// Square background view used by `.tile` style. The cell itself stays
    /// full-bleed (so layouts get their natural cell rect), and the visible
    /// "frame" is rendered inside this centered square subview.
    private var tileBackgroundView: NSView?
    private var currentURL: URL?
    private var pendingImage: NSImage?

    /// Overlay for the `.asDropTarget` highlight state. Lazy so cells that
    /// never become drop targets pay no allocation cost. Insets so the
    /// border sits inside the cell rather than slicing the thumbnail's
    /// edge.
    private lazy var dropTargetOverlay: NSView = {
        let overlay = NSView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.borderColor = NSColor.controlAccentColor.cgColor
        overlay.layer?.borderWidth = 3
        overlay.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        overlay.layer?.shadowColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        overlay.layer?.shadowOpacity = 1
        overlay.layer?.shadowRadius = 10
        overlay.layer?.shadowOffset = .zero
        overlay.isHidden = true
        return overlay
    }()

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

    /// NSCollectionView calls this automatically when the item becomes a
    /// drop target (validateDrop returned `.on` with this item's
    /// indexPath). We layer the visual on top of the cell so the
    /// existing selection styling stays untouched.
    override public var highlightState: NSCollectionViewItem.HighlightState {
        didSet {
            dropTargetOverlay.isHidden = highlightState != .asDropTarget
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()
        currentURL = nil
        borderImageView?.image = nil
        plainImageView?.image = nil
        isSelected = false
        highlightState = .none
        view.layer?.transform = CATransform3DIdentity
    }

    override public func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.apply(layoutAttributes)
        view.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    /// For `.tile` cells, the visible "frame" is the surrounding tile, but
    /// only the inner image should fly with the cursor — the dragged
    /// payload is the file itself, not the chrome we put around it. For
    /// the other styles the full cell *is* the visual, so the default
    /// snapshot still applies.
    override public var draggingImageComponents: [NSDraggingImageComponent] {
        guard itemStyle == .tile,
              let imageView = plainImageView,
              let image = imageView.image
        else {
            return super.draggingImageComponents
        }
        let component = NSDraggingImageComponent(key: .icon)
        component.contents = image
        // The imageView is square, but the image inside is drawn at its
        // native aspect via `scaleProportionallyUpOrDown` — so the visible
        // bitmap doesn't fill the square. Use the aspect-fitted sub-rect
        // as the drag component's frame; otherwise the drag preview would
        // stretch the image back to a square.
        let container = imageView.convert(imageView.bounds, to: view)
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            component.frame = container
            return [component]
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        let fitted = if imageAspect > containerAspect {
            CGSize(width: container.width, height: container.width / imageAspect)
        } else {
            CGSize(width: container.height * imageAspect, height: container.height)
        }
        component.frame = CGRect(
            x: container.midX - fitted.width / 2,
            y: container.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
        return [component]
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
        case .tile:
            setupTileStyle()
        case .borderless:
            setupBorderlessStyle()
        }

        view.addSubview(dropTargetOverlay)
        NSLayoutConstraint.activate([
            dropTargetOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            dropTargetOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            dropTargetOverlay.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            dropTargetOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
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

    private func setupTileStyle() {
        view.layer?.backgroundColor = .clear

        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.backgroundColor = CGColor(gray: 0.5, alpha: 0.15)
        tile.layer?.borderWidth = 3.0
        tile.layer?.borderColor = .clear
        tile.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tile)
        tileBackgroundView = tile

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(imageView)
        plainImageView = imageView

        // Tile = the largest centered square that fits inside the cell.
        // Two `lessThanOrEqualTo` caps + a square aspect + one default-high
        // `equalTo` per axis lets Auto Layout pick the smaller axis to drive
        // the tile size while still centering inside the cell.
        let widthFill = tile.widthAnchor.constraint(equalTo: view.widthAnchor)
        widthFill.priority = .defaultHigh
        let heightFill = tile.heightAnchor.constraint(equalTo: view.heightAnchor)
        heightFill.priority = .defaultHigh

        NSLayoutConstraint.activate([
            tile.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tile.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            tile.widthAnchor.constraint(equalTo: tile.heightAnchor),
            tile.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            tile.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor),
            widthFill,
            heightFill,
            imageView.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: tile.widthAnchor, multiplier: 0.9),
            imageView.heightAnchor.constraint(equalTo: tile.heightAnchor, multiplier: 0.9),
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
        case .tile:
            view.layer?.cornerRadius = 0
            if let tile = tileBackgroundView {
                tile.layer?.cornerRadius = tile.bounds.width * 0.06
            }
        case .borderless:
            view.layer?.cornerRadius = 0
        }
        // Keep the drop-target overlay's corner radius in sync; clamp so
        // very small thumbnails don't end up with sharp corners while the
        // surrounding cell is rounded.
        let overlayRadius: CGFloat = switch itemStyle {
        case .photoFrame: max(12, view.bounds.width * 0.1)
        case .tile: max(8, (tileBackgroundView?.bounds.width ?? view.bounds.width) * 0.06)
        case .borderless: 10
        }
        dropTargetOverlay.layer?.cornerRadius = overlayRadius
    }

    // MARK: - Configure

    override public func viewDidLoad() {
        super.viewDidLoad()
        if let pendingImage {
            setImage(pendingImage)
            self.pendingImage = nil
        }
    }

    public func configure(with url: URL, maxDimension: CGFloat = 512) {
        currentURL = url

        // Synchronous cache hit → store for viewDidLoad (view may not exist yet)
        if let cached = ImageCache.shared.cachedImage(for: url, maxDimension: maxDimension) {
            if isViewLoaded {
                setImage(cached)
            } else {
                pendingImage = cached
            }
            return
        }

        ImageCache.shared.image(for: url, maxDimension: maxDimension) { [weak self] img in
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
        case .tile:
            tileBackgroundView?.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : .clear
        case .borderless:
            view.layer?.borderWidth = isSelected ? 4.0 : 0
            view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : .clear
        }
    }
}
