//
//  WaterfallLayout.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class WaterfallLayout: NSCollectionViewLayout {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var contentHeight: CGFloat = 0

    var items: [DynamicLayoutItem] = []

    public var columns: Int = 5
    public var spacingPercentage: CGFloat = 0.05
    public var sectionInset: NSEdgeInsets = .init(top: 20, left: 20, bottom: 20, right: 20)

    override public func prepare() {
        super.prepare()

        cache.removeAll()
        contentHeight = 0

        guard let collectionView else { return }

        let width = collectionView.bounds.width - sectionInset.left - sectionInset.right
        let initialColumnWidth = width / CGFloat(columns)
        let spacing = initialColumnWidth * spacingPercentage
        let columnWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)

        var xOffset: [CGFloat] = []
        var currentXOffset = sectionInset.left
        for i in 0 ..< columns {
            xOffset.append(currentXOffset)
            if i < columns - 1 {
                currentXOffset += columnWidth + spacing
            } else {
                currentXOffset += columnWidth
            }
        }

        var yOffset: [CGFloat] = Array(repeating: sectionInset.top, count: columns)

        for (index, item) in items.enumerated() {
            // Shortest-column algorithm: always place into the column with least height
            let shortestColumn = yOffset.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0

            let indexPath = IndexPath(item: index, section: 0)
            let aspectRatio = item.aspectRatio
            let height = columnWidth / aspectRatio
            let frame = CGRect(x: xOffset[shortestColumn], y: yOffset[shortestColumn], width: columnWidth, height: height)

            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = frame
            cache.append(attributes)

            yOffset[shortestColumn] += height + spacing
        }

        if let maxOffset = yOffset.max() {
            contentHeight = maxOffset + sectionInset.bottom
        }
    }

    override public var collectionViewContentSize: NSSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override public func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cache.filter { $0.frame.intersects(rect) }
    }

    override public func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        if indexPath.item >= cache.count {
            return NSCollectionViewLayoutAttributes()
        }
        return cache[indexPath.item]
    }

    override public func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let oldBounds = collectionView?.bounds ?? .zero
        return newBounds.width != oldBounds.width
    }
}
