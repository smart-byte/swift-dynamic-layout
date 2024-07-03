//
//  MasonryLayout.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class MasonryLayout: NSCollectionViewLayout {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var contentHeight: CGFloat = 0
    private var columnWidths: [CGFloat] = []

    var items: [DynamicLayoutItem] = [] 

    public var columns: Int = 5
    public var spacingPercentage: CGFloat = 0.05
    public var sectionInset: NSEdgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    public override func prepare() {
        super.prepare()

        cache.removeAll()
        contentHeight = 0

        guard let collectionView = collectionView else { return }

        let width = collectionView.bounds.width - sectionInset.left - sectionInset.right
        let initialColumnWidth = width / CGFloat(columns)
        let spacing = initialColumnWidth * spacingPercentage
        let columnWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)

        var xOffset: [CGFloat] = []
        var currentXOffset = sectionInset.left
        for i in 0..<columns {
            xOffset.append(currentXOffset)
            if i < columns - 1 {
                currentXOffset += columnWidth + spacing
            } else {
                currentXOffset += columnWidth
            }
        }

        var column = 0
        var yOffset: [CGFloat] = Array(repeating: sectionInset.top, count: columns)

        for (index, item) in items.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let aspectRatio = item.aspectRatio
            let height = columnWidth / aspectRatio
            let frame = CGRect(x: xOffset[column], y: yOffset[column], width: columnWidth, height: height)

            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = frame
            cache.append(attributes)

            contentHeight = max(contentHeight, frame.maxY + sectionInset.bottom)
            yOffset[column] += height + spacing

            column = (column + 1) % columns
        }

        if let maxOffset = yOffset.max() {
            contentHeight = maxOffset + sectionInset.bottom
        }
    }

    public override var collectionViewContentSize: NSSize {
        return CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    public override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var visibleLayoutAttributes: [NSCollectionViewLayoutAttributes] = []
        for attributes in cache {
            if attributes.frame.intersects(rect) {
                visibleLayoutAttributes.append(attributes)
            }
        }
        return visibleLayoutAttributes
    }

    public override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        if indexPath.item >= cache.count {
            return NSCollectionViewLayoutAttributes()
        }
        return cache[indexPath.item]
    }

    public override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let oldBounds = collectionView?.bounds ?? .zero
        return newBounds.width != oldBounds.width
    }
}
