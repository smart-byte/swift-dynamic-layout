//
//  ContactSheetItem.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit
import ImageTools

public class ContactSheetItem: NSCollectionViewItem {
    var contentImageView: NSImageView!

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

        contentImageView = NSImageView()
        contentImageView.imageScaling = .scaleProportionallyUpOrDown
        contentImageView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(contentImageView)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.95),
            contentImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.95)
        ])
    }

    public func configure(with url: URL) {
        ImageCache.shared.image(for: url, maxDimension: 512) { img in
            self.contentImageView.image = img
        }
    }

    public func configure(with image: NSImage? ) {
        self.contentImageView.image = image
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        self.view.layer?.cornerRadius = self.view.bounds.width * 0.02
    }

    private func updateSelectionAppearance() {
        if isSelected {
            self.view.layer?.borderColor = NSColor.orange.cgColor
        } else {
            self.view.layer?.borderColor = .clear
        }
    }
}
