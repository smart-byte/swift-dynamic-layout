//
//  File.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class HorizontalFlowLayout: NSCollectionViewFlowLayout {
    // Cache-Array für Layout-Attribute
    private var cache: [NSCollectionViewLayoutAttributes] = []

    // Gesamtbreite des Inhalts speichern, um collectionViewContentSize festzulegen
    private var contentWidth: CGFloat = 0

    override init() {
        super.init()
        setupLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayout()
    }

    private func setupLayout() {
        scrollDirection = .horizontal
        minimumInteritemSpacing = 10
        minimumLineSpacing = 10
    }

    public override func prepare() {
        super.prepare()
        guard let collectionView = collectionView else { return }

        // Bereiten Sie den Cache und die Größeninitialisierung vor
        cache.removeAll()
        contentWidth = 0

        var xOffset: CGFloat = 0
        let collectionViewHeight = collectionView.bounds.height

        for item in 0..<collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let aspectRatio = CGFloat.random(in: 0.5...2)
            let itemWidth = collectionViewHeight * aspectRatio
            let frame = CGRect(x: xOffset, y: 0, width: itemWidth, height: collectionViewHeight)
            let insetFrame = frame.insetBy(dx: minimumInteritemSpacing / 2, dy: 0)

            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = insetFrame
            cache.append(attributes)

            xOffset += itemWidth + minimumInteritemSpacing
        }

        contentWidth = xOffset
    }

    public override var collectionViewContentSize: NSSize {
        return CGSize(width: contentWidth, height: collectionView?.bounds.height ?? 0)
    }

    public override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        return cache.filter { $0.frame.intersects(rect) }
    }

    public override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes {
        if indexPath.item >= cache.count {
            return NSCollectionViewLayoutAttributes()
        }
        return cache[indexPath.item]
    }
}
