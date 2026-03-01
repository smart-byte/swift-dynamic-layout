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
    private var currentURL: URL?

    override init(nibName _: NSNib.Name?, bundle _: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    override public var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()
        currentURL = nil
        contentImageView.image = nil
        nameLabel.stringValue = ""
        dateLabel.stringValue = ""
        view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        isSelected = false
        view.layer?.transform = CATransform3DIdentity
    }

    override public func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)
        view.layer?.transform = CATransform3DIdentity
    }

    override public func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
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

        view.addSubview(contentImageView)
        view.addSubview(nameLabel)
        view.addSubview(dateLabel)

        setupConstraints()
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            contentImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            contentImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            contentImageView.widthAnchor.constraint(equalToConstant: 40),
            contentImageView.heightAnchor.constraint(equalToConstant: 34),

            nameLabel.leadingAnchor.constraint(equalTo: contentImageView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            nameLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 5),

            dateLabel.leadingAnchor.constraint(equalTo: contentImageView.trailingAnchor, constant: 10),
            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            dateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
        ])
    }

    public func configure(with url: URL) {
        currentURL = url
        nameLabel.stringValue = url.lastPathComponent

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let creationDate = attributes[.creationDate] as? Date
        {
            dateLabel.stringValue = Self.dateFormatter.string(from: creationDate)
        }

        ImageCache.shared.image(for: url, maxDimension: 512) { [weak self] img in
            DispatchQueue.main.async {
                guard let self, self.currentURL == url else { return }
                self.contentImageView.image = img
            }
        }
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        view.layer?.cornerRadius = 8
    }

    private func updateSelectionAppearance() {
        if isSelected {
            view.layer?.backgroundColor = NSColor.selectedControlColor.cgColor
        } else {
            view.layer?.backgroundColor = CGColor(gray: 0.2, alpha: 0.3)
        }
    }
}
