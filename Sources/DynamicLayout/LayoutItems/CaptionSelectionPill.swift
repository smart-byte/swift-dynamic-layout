//
//  CaptionSelectionPill.swift
//  DynamicLayout
//

import AppKit

/// Capsule background that hosts the photoFrame caption label. Stays
/// transparent at rest; the host (`ThumbnailItem`) tints it with the
/// accent (or inactive secondary) colour while the cell is selected,
/// à la Finder's gallery selection style.
///
/// Maintains its own capsule cornerRadius from `layout()` so the pill
/// stays a clean half-circle-ended shape across collection-layout
/// switches and zoom-slider changes — unlike a host-driven cornerRadius
/// which can read a stale height before Auto Layout has propagated to
/// the pill itself.
final class CaptionSelectionPill: NSView {
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
        // Suppress implicit layer animations so the pill never fades or
        // resize-animates during NSCollectionView reuse / layout swaps.
        layer?.actions = [
            "backgroundColor": NSNull(),
            "cornerRadius": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
        ]
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }
}
