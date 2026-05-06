//
//  DragImageComposer.swift
//
//
//  Created by Mario Heubach on 29.04.26.
//

import AppKit

/// Visual style for the drag preview. The choice of style is driven by the
/// layout under the cursor (source layout when a drag begins, destination
/// layout once it enters another collection view), so the preview morphs
/// to match the target's "feel" — Finder-style.
public enum DragImageStyle: Sendable {
    /// List-view feel: 16 px icon and label inline (horizontal).
    case compact
    /// Justified / Flow feel: 64 px icon with label below (card).
    case medium
    /// Waterfall / Desktop feel: 128 px icon with soft drop shadow and
    /// label below.
    case large

    /// Pixel size of the file-icon glyph for this style.
    var iconDimension: CGFloat {
        switch self {
        case .compact: 16
        case .medium: 64
        case .large: 128
        }
    }

    /// Font used to render the file name.
    var labelFont: NSFont {
        switch self {
        case .compact: .systemFont(ofSize: NSFont.smallSystemFontSize)
        case .medium: .systemFont(ofSize: NSFont.smallSystemFontSize)
        case .large: .systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    /// Pixels of horizontal/vertical padding between icon and label.
    var spacing: CGFloat {
        switch self {
        case .compact: 6
        case .medium, .large: 4
        }
    }

    /// Width budget for the rendered label image.
    var labelMaxWidth: CGFloat {
        switch self {
        case .compact: 240
        case .medium: 140
        case .large: 200
        }
    }

    /// Whether the icon bitmap should be rendered with a soft drop shadow.
    var drawsShadow: Bool {
        self == .large
    }
}

/// Renders the visual components of a drag preview. Free function — no
/// captured state, no actor isolation, safe to call from inside an
/// `NSDraggingItem.imageComponentsProvider` closure.
public enum DragImageComposer {
    /// Build the dragging-image components for a file URL in the given style.
    /// Returns a fresh array each call. Suitable as the body of
    /// `NSDraggingItem.imageComponentsProvider`.
    ///
    /// - Parameters:
    ///   - url: The file to represent.
    ///   - style: Visual density / size of the drag preview.
    ///   - syncProvider: Synchronous thumbnail lookup — typically backed by
    ///     `ImageCache.shared.cachedImage(for:maxDimension:)` in the host app.
    ///     Passing `nil` (or a provider that returns `nil`) falls back to the
    ///     system workspace icon, which is always available.
    public static func compose(
        for url: URL,
        style: DragImageStyle,
        syncProvider: SyncImageProvider
    ) -> [NSDraggingImageComponent] {
        let iconImage = renderIcon(for: url, style: style, syncProvider: syncProvider)
        let labelImage = renderLabel(text: url.lastPathComponent, style: style)

        let iconComponent = NSDraggingImageComponent(key: .icon)
        iconComponent.contents = iconImage
        let labelComponent = NSDraggingImageComponent(key: .label)
        labelComponent.contents = labelImage

        let iconSize = iconImage.size
        let labelSize = labelImage.size

        switch style {
        case .compact:
            // Side-by-side: icon on the left, label vertically centered to
            // its right. Origin (0, 0) sits at the bottom-left.
            let totalHeight = max(iconSize.height, labelSize.height)
            let iconY = (totalHeight - iconSize.height) / 2
            let labelY = (totalHeight - labelSize.height) / 2
            iconComponent.frame = CGRect(
                x: 0, y: iconY,
                width: iconSize.width, height: iconSize.height
            )
            labelComponent.frame = CGRect(
                x: iconSize.width + style.spacing, y: labelY,
                width: labelSize.width, height: labelSize.height
            )

        case .medium, .large:
            // Stacked: icon centered horizontally on top, label below.
            // The y-axis grows upward, so the icon (top) gets the higher Y.
            let totalWidth = max(iconSize.width, labelSize.width)
            let iconX = (totalWidth - iconSize.width) / 2
            let labelX = (totalWidth - labelSize.width) / 2
            iconComponent.frame = CGRect(
                x: iconX, y: labelSize.height + style.spacing,
                width: iconSize.width, height: iconSize.height
            )
            labelComponent.frame = CGRect(
                x: labelX, y: 0,
                width: labelSize.width, height: labelSize.height
            )
        }

        return [iconComponent, labelComponent]
    }

    // MARK: - Icon rendering

    /// Returns the file's icon resized to the style's icon dimension. Prefers
    /// a real Quick Look thumbnail from the injected `syncProvider` (so
    /// dragged image files look like image files instead of generic file
    /// blanks) and falls back to the system file-type icon when the provider
    /// returns `nil`. For the `.large` style we draw the icon into a fresh
    /// bitmap with a soft drop shadow so the dragging preview gets an extra
    /// elevation cue.
    private static func renderIcon(for url: URL, style: DragImageStyle, syncProvider: SyncImageProvider) -> NSImage {
        let dim = style.iconDimension
        // Match the dimension the list/collection cells request so the
        // provider hits the same cache bucket they already populated.
        let baseIcon = syncProvider(url, 64)
            ?? NSWorkspace.shared.icon(forFile: url.path)

        guard style.drawsShadow else {
            // Fast path: NSWorkspace icons are multi-rep — assigning `size`
            // is enough; AppKit picks the best representation when drawn.
            let copy = baseIcon.copy() as? NSImage ?? baseIcon
            copy.size = NSSize(width: dim, height: dim)
            return copy
        }

        // Drop-shadow path: bake the shadow into the bitmap so the dragging
        // pasteboard renders it without needing CALayer effects.
        let shadowPad: CGFloat = 8
        let canvasSize = NSSize(width: dim + shadowPad * 2, height: dim + shadowPad * 2)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 6
        shadow.set()

        let drawRect = NSRect(x: shadowPad, y: shadowPad, width: dim, height: dim)
        baseIcon.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        return image
    }

    // MARK: - Label rendering

    /// Renders `text` as a rounded-rect label badge into a bitmap so the
    /// drag image stays consistent with how AppKit paints standard drag
    /// labels (semi-transparent dark capsule, white text). For long names
    /// the text truncates in the middle.
    private static func renderLabel(text: String, style: DragImageStyle) -> NSImage {
        let font = style.labelFont

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        paragraph.alignment = .center

        // Finder uses an accent-color tint behind the file name for the
        // List-view (compact) drag preview; the dark capsule is reserved
        // for the card-style Desktop drags.
        let textColor: NSColor = switch style {
        case .compact: .white
        case .medium, .large: .white
        }
        let capsuleFill = switch style {
        case .compact: NSColor.controlAccentColor.withAlphaComponent(0.85)
        case .medium, .large: NSColor.black.withAlphaComponent(0.55)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph,
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)

        // Measure the natural width, capped to the style's budget.
        let naturalSize = attributed.size()
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 3
        let textWidth = min(naturalSize.width, style.labelMaxWidth)
        let imageWidth = ceil(textWidth + horizontalPadding * 2)
        let imageHeight = ceil(font.ascender - font.descender + verticalPadding * 2)

        let imageSize = NSSize(width: max(imageWidth, 1), height: max(imageHeight, 1))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Capsule background.
        let bgRect = NSRect(origin: .zero, size: imageSize)
        let radius = imageSize.height / 2
        let path = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
        capsuleFill.setFill()
        path.fill()

        // Text — vertically centered using font metrics to avoid sub-pixel drift.
        let textRect = NSRect(
            x: horizontalPadding,
            y: verticalPadding,
            width: textWidth,
            height: imageHeight - verticalPadding * 2
        )
        attributed.draw(with: textRect, options: [.usesLineFragmentOrigin], context: nil)
        return image
    }
}

// MARK: - LayoutMode → DragImageStyle

public extension LayoutMode {
    /// The drag-preview style that matches this layout's visual feel.
    var dragImageStyle: DragImageStyle {
        switch self {
        case .list: .compact
        case .justified, .horizontalJustified, .horizontalFlow, .verticalFlow: .medium
        case .waterfall: .large
        }
    }
}
