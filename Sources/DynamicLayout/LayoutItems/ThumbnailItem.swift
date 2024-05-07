//
//  ThumbnailItem.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit
import ImageTools

public class ThumbnailItem: NSCollectionViewItem {
    public override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    var contentImageView: CustomImageView!
    var titleLabel: NSTextField!

    public override func prepareForReuse() {
        super.prepareForReuse()
        self.view.layer?.contents = nil
        self.isSelected = false
    }

    public override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = .clear
        self.view.layer?.masksToBounds = true
        self.view.autoresizesSubviews = true

        contentImageView = CustomImageView()
        contentImageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel = NSTextField()
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.drawsBackground = false
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center

        self.view.addSubview(contentImageView)
        self.view.addSubview(titleLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            contentImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.8),

            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: contentImageView.bottomAnchor, constant: 5),
            titleLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        self.view.layer?.cornerRadius = self.view.bounds.width * 0.1
    }

    public func configure(with url: URL) {
        ImageCache.shared.image(for: url, maxDimension: 512) { img in
            self.contentImageView.image = img
        }
        self.titleLabel.stringValue = url.lastPathComponent
    }

    private func updateSelectionAppearance() {
        if isSelected {
            self.view.layer?.backgroundColor = CGColor(gray: 0.1, alpha: 0.1)
        } else {
            self.view.layer?.backgroundColor = .clear
        }
    }
}

class CustomImageView: NSView {
    private let imageView = NSImageView()
    private let backgroundView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        addSubview(backgroundView)
        addSubview(imageView)

        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = .clear

        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.white.cgColor
//        backgroundView.layer?.shadowOpacity = 0.5
//        backgroundView.layer?.shadowRadius = 1
//        backgroundView.layer?.shadowOffset = CGSize(width: 0, height: 0)
//        backgroundView.layer?.shadowColor = NSColor.black.cgColor

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: 0.8),
        ])

        updateConstraintsForImage()

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        imageView.imageScaling = .scaleProportionallyUpOrDown
    }

    var image: NSImage? {
        didSet {
            imageView.image = image
            imageView.invalidateIntrinsicContentSize()
            updateConstraintsForImage()
        }
    }

    override func layout() {
        super.layout()
        backgroundView.layer?.borderWidth = max(1.0, bounds.width * 0.02) // Beispiel: Rahmenbreite als 2% der Breite
    }

    private func updateConstraintsForImage() {
        if let image = imageView.image {
            let aspectRatio = image.size.width / image.size.height
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: aspectRatio).isActive = true
        } else {
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        }
    }
}
