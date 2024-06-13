//
//  ListItem.swift
//
//
//  Created by Mario Heubach on 13.06.24.
//

import AppKit
import ImageTools

public class ListItem: NSCollectionViewItem {
    var contentImageView: NSImageView!
    var nameLabel: NSTextField!
    var dateLabel: NSTextField!

    public override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        self.view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        self.isSelected = false
    }

    public override func loadView() {
        self.view = NSView()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        view.layer?.contentsGravity = .resizeAspect

        contentImageView = NSImageView()
        contentImageView.imageScaling = .scaleProportionallyUpOrDown
        contentImageView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel = NSTextField()
        nameLabel.isEditable = false
        nameLabel.isBordered = false
        nameLabel.backgroundColor = .clear
        nameLabel.font = NSFont.systemFont(ofSize: 14)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel = NSTextField()
        dateLabel.isEditable = false
        dateLabel.isBordered = false
        dateLabel.backgroundColor = .clear
        dateLabel.font = NSFont.systemFont(ofSize: 12)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(contentImageView)
        self.view.addSubview(nameLabel)
        self.view.addSubview(dateLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            contentImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentImageView.widthAnchor.constraint(equalToConstant: 40),
            contentImageView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.leadingAnchor.constraint(equalTo: contentImageView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            nameLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),

            dateLabel.leadingAnchor.constraint(equalTo: contentImageView.trailingAnchor, constant: 10),
            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
    }

    public func configure(with url: URL) {
        ImageCache.shared.image(for: url, maxDimension: 512) { img in
            self.contentImageView.image = img
        }
        self.nameLabel.stringValue = url.lastPathComponent
        // Setze das Datum oder andere Metadaten basierend auf der URL
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let creationDate = attributes[.creationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            self.dateLabel.stringValue = formatter.string(from: creationDate)
        }
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        self.view.layer?.cornerRadius = 8
    }

    private func updateSelectionAppearance() {
        if isSelected {
            self.view.layer?.backgroundColor = NSColor.selectedControlColor.cgColor
        } else {
            self.view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        }
    }
}
