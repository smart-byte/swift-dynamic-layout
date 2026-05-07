//
//  ThumbnailItem.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

// swiftlint:disable file_length

import AppKit

public class ThumbnailItem: NSCollectionViewItem {
    /// Set before accessing `view` — determines the visual style.
    var itemStyle: ItemStyle = .photoFrame

    private var borderImageView: BorderImageView?
    private var plainImageView: NSImageView?
    /// Square background view used by `.tile` style. The cell itself stays
    /// full-bleed (so layouts get their natural cell rect), and the visible
    /// "frame" is rendered inside this centered square subview.
    private var tileBackgroundView: NSView?
    /// Filename label shown below (photoFrame, tile) or overlaid on
    /// (borderless) the image. Style-specific look configured by the
    /// per-style setup methods.
    private var captionLabel: NSTextField?
    /// Pill-shaped wrapper used by the borderless caption — sits
    /// centered over the lower edge of the image. Other styles use
    /// the cell view directly.
    private var captionPill: CaptionPill?
    /// Below this cell-height threshold the caption is hidden — at
    /// thumbnail-grid sizes the label would either get clipped or
    /// dominate the cell.
    private static let captionMinCellHeight: CGFloat = 80
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

    /// Tracks whether the cursor is currently inside the cell. Drives
    /// the borderless caption pill's visibility — it stays hidden
    /// until the user hovers, so the borderless look stays truly
    /// chrome-free at rest. Other styles ignore hover (their captions
    /// are always visible up to the small-cell cutoff).
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            applyCaptionVisibility()
        }
    }

    private var hoverTrackingArea: NSTrackingArea?

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
        captionLabel?.stringValue = ""
        isSelected = false
        // Snap-reset the borderless pill alpha BEFORE clearing
        // `isHovered`, so the recycle-driven applyCaptionVisibility
        // call animates from 0 → 0 (no visible change) instead of
        // 1 → 0 (visible fade-out for cells that scroll back into
        // view from a hovered state).
        if itemStyle == .borderless {
            captionPill?.alphaValue = 0
        }
        isHovered = false
        highlightState = .none
        view.layer?.transform = CATransform3DIdentity
    }

    override public func mouseEntered(with _: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with _: NSEvent) {
        isHovered = false
    }

    override public func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.apply(layoutAttributes)
        view.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    /// `.tile` and `.borderless` both render an image-only drag
    /// preview — chrome (tile backdrop, borderless caption pill)
    /// shouldn't ride along with the dragged file. `.photoFrame`
    /// keeps the default super snapshot, which already shows the
    /// framed image + filename below the way a card-style drag
    /// should look.
    override public var draggingImageComponents: [NSDraggingImageComponent] {
        let usesPlainImage = itemStyle == .tile || itemStyle == .borderless
        guard usesPlainImage,
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

        // Hover tracking — `inVisibleRect` keeps the area aligned with
        // whatever rect the cell is currently showing (cell reuse,
        // scrolling, layout-attribute changes), no manual updates.
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        hoverTrackingArea = area
    }

    /// Folds the size-based and hover-based visibility rules for the
    /// caption pill into a single decision. Called from
    /// `viewDidLayout` (size changes) and the `isHovered` setter
    /// (hover changes); the small-cell cutoff still wins over the
    /// hover gate so tiny grid thumbnails don't pop a caption no
    /// matter what.
    private func applyCaptionVisibility() {
        let cellTooSmall = view.bounds.height < Self.captionMinCellHeight
        switch itemStyle {
        case .photoFrame, .tile:
            // Caption always visible, subject only to the small-cell
            // cutoff (binary toggle, no animation).
            captionLabel?.isHidden = cellTooSmall
            captionPill?.isHidden = cellTooSmall
        case .borderless:
            // Hover-only with a short fade. Size cutoff still wins —
            // tiny cells hide the pill outright instead of briefly
            // animating a caption that wouldn't be readable anyway.
            if cellTooSmall {
                captionPill?.isHidden = true
                captionPill?.alphaValue = 0
            } else {
                captionPill?.isHidden = false
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.allowsImplicitAnimation = true
                    captionPill?.animator().alphaValue = isHovered ? 1.0 : 0.0
                }
            }
        }
    }

    private func setupPhotoFrameStyle() {
        view.layer?.backgroundColor = .clear

        let imageView = BorderImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        borderImageView = imageView

        // Filename below the framed image — centered, single line,
        // truncated in the middle so file extensions stay visible.
        let label = makeCaptionLabel(
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .secondaryLabelColor
        )
        captionLabel = label

        // Apple-idiomatic vertical stack: caption gets `required`
        // compression and hugging priorities so it always renders at
        // its intrinsic height; the image gets `defaultLow` and shrinks
        // first when the cell can't fit both. When the caption is
        // hidden later, the stack drops it from layout automatically
        // and the image takes the freed space.
        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            // Framed image keeps its 80% cell width — caption fills the
            // stack width so middle-truncation kicks in for long names.
            imageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            label.widthAnchor.constraint(equalTo: stack.widthAnchor),
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
        plainImageView = imageView

        // Caption sits on the tile's tinted background — no extra
        // panel needed, the existing tile fill provides the contrast.
        let label = makeCaptionLabel(
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .labelColor
        )
        captionLabel = label

        // NSStackView arranges image-over-caption inside the tile.
        // Caption is non-shrinkable so the image yields space first
        // when the tile gets small — same Apple-idiomatic priority
        // dance as the photo-frame style above.
        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.distribution = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(stack)

        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .vertical)

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
            // Stack fills the tile with insets — image takes the upper
            // portion, caption sits on the tinted tile background.
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -8),
            imageView.widthAnchor.constraint(equalTo: tile.widthAnchor, multiplier: 0.82),
            label.widthAnchor.constraint(equalTo: stack.widthAnchor),
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

        // Floating pill: dark capsule centered above the bottom edge,
        // white filename inside. The pill hugs the label width so the
        // underlying image stays mostly visible. Starts at alpha 0 so
        // the first hover-fade animates from 0 → 1, not 1 → 0 → 1.
        let pill = CaptionPill()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.alphaValue = 0
        view.addSubview(pill)
        captionPill = pill

        let label = makeCaptionLabel(
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .white
        )
        pill.addSubview(label)
        captionLabel = label

        NSLayoutConstraint.activate([
            pill.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
        ])
    }

    /// Shared factory for the filename label so all three styles agree
    /// on truncation, alignment, and single-line behaviour. Color and
    /// font come from the caller because each style sits on a different
    /// background.
    private func makeCaptionLabel(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false
        // Keep the label transparent — borderless and tile already
        // provide the readable surface; photoFrame puts it on the
        // window background.
        label.drawsBackground = false
        label.isBezeled = false
        label.isBordered = false
        return label
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
        // Caption visibility folds size-based hiding (tiny grid
        // thumbnails) and hover-based hiding (borderless) into one
        // decision in `applyCaptionVisibility`.
        applyCaptionVisibility()
    }

    // MARK: - Configure

    override public func viewDidLoad() {
        super.viewDidLoad()
        if let pendingImage {
            setImage(pendingImage)
            self.pendingImage = nil
        }
        // The caption label only exists after the per-style setup that
        // runs in `loadView`. If `configure(with:)` ran first, its
        // assignment to `captionLabel?.stringValue` was a no-op — repaint
        // from the canonical source now that the label is alive.
        if let url = currentURL {
            captionLabel?.stringValue = url.lastPathComponent
        }
    }

    public func configure(
        with url: URL,
        maxDimension: CGFloat = 512,
        syncProvider: SyncImageProvider,
        asyncProvider: ImageProvider
    ) {
        currentURL = url
        captionLabel?.stringValue = url.lastPathComponent

        // Synchronous cache hit → store for viewDidLoad (view may not exist yet)
        if let cached = syncProvider(url, maxDimension) {
            if isViewLoaded {
                setImage(cached)
            } else {
                pendingImage = cached
            }
            return
        }

        asyncProvider(url, maxDimension) { [weak self] img in
            // The provider may deliver on a background thread; hop to main
            // so UIKit/AppKit mutations are safe.
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
