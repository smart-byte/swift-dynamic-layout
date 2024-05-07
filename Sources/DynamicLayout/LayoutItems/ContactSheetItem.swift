//
//  ContactSheetItem.swift
//  
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit
import ImageTools

public class ContactSheetItem: NSCollectionViewItem {
    public override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        self.view.layer?.contents = nil
        self.isSelected = false
    }

    public override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        view.layer?.borderWidth = 4.0
        view.layer?.borderColor = .clear
        view.layer?.contentsGravity = .resizeAspect
    }

    public func configure(with url: URL) {
        ImageCache.shared.image(for: url, maxDimension: 512) { img in
            self.view.layer?.contents = img
        }
    }

    private func updateSelectionAppearance() {
        if isSelected {
            self.view.layer?.borderColor = NSColor.orange.cgColor
        } else {
            self.view.layer?.borderColor = .clear
        }
    }
}

