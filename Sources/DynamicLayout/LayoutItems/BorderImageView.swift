//
//  BorderImageView.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit

/// Photo-frame chrome around an image: a constant-thickness white
/// matte hugging the image's aspect-fit rect, a thin dark inner
/// edge, and a soft drop shadow. When selected, the matte itself
/// gains an accent-coloured border drawn directly on its outer
/// edge — keeps the selection visually integrated with the frame,
/// no extra padding layer outside the cell that could clash with
/// the cell's clipping / cornerRadius mask.
///
/// Matte thickness derives from the host's `scaleReference`
/// (toolbar zoom slider); the selection border width is fixed pt UI
/// chrome and doesn't scale with zoom.
class BorderImageView: NSView {
    private static let matteFraction: CGFloat = 0.04
    private static let matteMinimum: CGFloat = 4
    private static let innerEdgeWidth: CGFloat = 0.5
    private static let selectionBorderWidth: CGFloat = 4

    /// Layout-level scale reference, set by the host. Drives the
    /// matte thickness so it tracks the zoom slider rather than the
    /// per-cell bounds.
    var scaleReference: CGFloat = 250 {
        didSet {
            guard oldValue != scaleReference else { return }
            needsLayout = true
        }
    }

    var image: NSImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            needsLayout = true
        }
    }

    var overlayColor: NSColor = .white {
        didSet { matteLayer.backgroundColor = overlayColor.cgColor }
    }

    /// Whether the cell is selected. Renders as an accent border
    /// drawn on the matte's outer edge.
    var isSelected: Bool = false {
        didSet {
            guard oldValue != isSelected else { return }
            applySelectionAppearance()
        }
    }

    /// Whether the host's window/pane currently has key-window /
    /// first-responder focus. Active selections pick up an accent
    /// flavour, inactive ones use NSTableView's secondary tint.
    var isActiveSelection: Bool = true {
        didSet {
            guard oldValue != isActiveSelection else { return }
            applySelectionAppearance()
        }
    }

    private let imageView = NSImageView()
    private let matteLayer = CALayer()
    /// Cached matte size from the last layout pass — drives a
    /// shouldRecreateShadowPath check so we don't allocate a fresh
    /// CGPath on every layout call (resize / scaleReference push
    /// would otherwise burn one CGPath per visible cell per pass).
    private var lastMatteSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        matteLayer.backgroundColor = overlayColor.cgColor
        // Shadow lives on the matte sublayer (not on our root) so
        // the cell.view's `masksToBounds = true` doesn't clip it
        // away — the matte is well inside the cell, leaving room
        // for the shadow halo on all sides.
        matteLayer.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        matteLayer.shadowOpacity = 1
        matteLayer.shadowRadius = 3
        matteLayer.shadowOffset = NSSize(width: 0, height: -1.5)
        matteLayer.actions = Self.noImplicitActions
        layer?.addSublayer(matteLayer)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = true
        imageView.wantsLayer = true
        imageView.layer?.borderWidth = Self.innerEdgeWidth
        imageView.layer?.borderColor = NSColor.black.withAlphaComponent(0.2).cgColor
        addSubview(imageView)
    }

    private var matteThickness: CGFloat {
        max(Self.matteMinimum, scaleReference * Self.matteFraction)
    }

    /// Aspect-fit rect for the image inside `bounds`, with the matte
    /// inset removed on all sides. Adding `matteThickness` back on
    /// all four sides yields the matte rect, which fits within
    /// `bounds` by construction.
    private func imageRect() -> NSRect {
        let m = matteThickness
        let inner = bounds.insetBy(dx: m, dy: m)
        guard let img = imageView.image,
              img.size.width > 0, img.size.height > 0,
              inner.width > 0, inner.height > 0
        else { return inner }
        let imgAspect = img.size.width / img.size.height
        let innerAspect = inner.width / inner.height
        if imgAspect > innerAspect {
            let h = inner.width / imgAspect
            return NSRect(x: inner.minX, y: inner.midY - h / 2, width: inner.width, height: h)
        } else {
            let w = inner.height * imgAspect
            return NSRect(x: inner.midX - w / 2, y: inner.minY, width: w, height: inner.height)
        }
    }

    override func layout() {
        super.layout()
        let img = imageRect()
        imageView.frame = img
        let matte = img.insetBy(dx: -matteThickness, dy: -matteThickness)
        matteLayer.frame = matte
        // shadowPath is keyed off layer bounds (origin-zero), not the
        // outer frame — keeps the halo crisp and avoids the per-frame
        // alpha-mask sampling CALayer falls back to without a path.
        // Only recreate when the matte's size actually changes; cell
        // reuse + scroll trigger layout() with identical sizes most
        // of the time and CGPath allocation isn't free.
        if matte.size != lastMatteSize {
            lastMatteSize = matte.size
            matteLayer.shadowPath = CGPath(
                rect: CGRect(origin: .zero, size: matte.size),
                transform: nil
            )
        }
    }

    private static let noImplicitActions: [String: any CAAction] = [
        "position": NSNull(),
        "bounds": NSNull(),
        "frame": NSNull(),
        "backgroundColor": NSNull(),
        "hidden": NSNull(),
    ]

    private func applySelectionAppearance() {
        // Selection draws as an accent border directly on the matte's
        // outer edge. Same affordance thickness as tile / borderless,
        // so the three styles read consistently.
        if isSelected {
            let tint: NSColor = isActiveSelection ? .controlAccentColor : .systemGray
            matteLayer.borderWidth = Self.selectionBorderWidth
            matteLayer.borderColor = tint.withAlphaComponent(isActiveSelection ? 0.95 : 0.7).cgColor
        } else {
            matteLayer.borderWidth = 0
            matteLayer.borderColor = nil
        }
    }
}
