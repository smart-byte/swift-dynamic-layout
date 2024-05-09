//
//  LayoutCollectionViewItem.swift
//
//
//  Created by Mario Heubach on 17.04.24.
//

import SwiftUI
import ImageTools

internal class LayoutCollectionViewItem: NSCollectionViewItem {
    var overlayLayer: CALayer!
    var itemImageView: NSImageView!
    var contentView: NSView!

    var trackingArea: NSTrackingArea?

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        view.layer?.borderWidth = 4.0
        view.layer?.borderColor = .clear

        contentView = NSView()

        itemImageView = NSImageView(frame: view.bounds)
        itemImageView.imageScaling = .scaleAxesIndependently
        itemImageView.autoresizingMask = [.width, .height]
        itemImageView.wantsLayer = true
        view.addSubview(itemImageView)

        overlayLayer = CALayer()
        overlayLayer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        overlayLayer?.frame = view.bounds
        overlayLayer?.opacity = 0
        overlayLayer?.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        overlayLayer.zPosition = 1
        itemImageView.layer?.addSublayer(overlayLayer)

        updateTrackingArea()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateTrackingArea()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.view.layer?.contents = nil
        self.itemImageView.image = nil
        self.isSelected = false
    }

    override func mouseEntered(with event: NSEvent) {
        // overlayLayer?.flashOpacity( toValue: 1, duration: 0.2 )
    }

    func configure(with item: DynamicLayoutItem) {
        //        self.view = NSHostingView(rootView: item.view)
        //        self.view.needsLayout = true

        //        self.view.layer?.contents = NSImage(named: "placeholder")
        //        self.itemImageView.image = item.image

        ImageCache.shared.image(for: item.url, maxDimension: 512) { img in
            self.itemImageView.image = img
        }
    }

    private func updateSelectionAppearance() {
        if isSelected {
            self.view.layer?.borderColor = NSColor.orange.cgColor
            //  self.view.layer?.animateBorderColor( toValue: NSColor.orange.cgColor, duration: 0.2 )
        } else {
            self.view.layer?.borderColor = .clear
            //  self.view.layer?.animateBorderColor( toValue: .clear, duration: 0.2 )
        }
    }

    private func updateTrackingArea() {
        if let existingTrackingArea = trackingArea {
            itemImageView.removeTrackingArea(existingTrackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )

        if let newTrackingArea = trackingArea {
            itemImageView.addTrackingArea(newTrackingArea)
        }
    }
}
