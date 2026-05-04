//
//  CaptionPill.swift
//  DynamicLayout
//

import AppKit

/// Centered, capsule-shaped pill used by `ThumbnailItem.borderless` to
/// host the filename label. Sits with a small inset over the lower
/// edge of the image — readable on any underlying photo without
/// covering the whole bottom strip the way a gradient would.
final class CaptionPill: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        // Disable implicit layer animations so the pill doesn't fade or
        // resize-animate during NSCollectionView reuse.
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
            "backgroundColor": NSNull(),
            "cornerRadius": NSNull(),
        ]
    }

    override func layout() {
        super.layout()
        // True capsule — corner radius tracks half the height so the
        // ends always render as half-circles regardless of label size.
        layer?.cornerRadius = bounds.height / 2
    }
}
