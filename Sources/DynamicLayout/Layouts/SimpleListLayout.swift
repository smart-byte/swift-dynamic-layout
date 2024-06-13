//
//  SimpleListLayout.swift
//  
//
//  Created by Mario Heubach on 13.06.24.
//

import AppKit

public class SimpleListLayout: NSCollectionViewLayout {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var contentHeight: CGFloat = 0

    public var itemHeight: CGFloat = 50
    public var sectionInset: NSEdgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    public var minimumLineSpacing: CGFloat = 10

    public override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else { return }

        // Cache zurücksetzen
        cache.removeAll()
        contentHeight = 0

        let contentWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right
        var yOffset: CGFloat = sectionInset.top

        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        for item in 0..<numberOfItems {
            let indexPath = IndexPath(item: item, section: 0)
            let frame = CGRect(x: sectionInset.left, y: yOffset, width: contentWidth, height: itemHeight)
            let insetFrame = frame.insetBy(dx: 0, dy: minimumLineSpacing / 2)

            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = insetFrame
            cache.append(attributes)

            yOffset += itemHeight + minimumLineSpacing
        }

        contentHeight = yOffset + sectionInset.bottom
    }

    public override var collectionViewContentSize: NSSize {
        return CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    public override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        return cache.filter { $0.frame.intersects(rect) }
    }

    public override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes {
        return cache[indexPath.item]
    }

    override public func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        return true
    }
}
