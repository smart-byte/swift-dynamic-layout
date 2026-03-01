//
//  JustifiedLayout.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// Google-Photos-style justified layout where items fill the row width
/// with each row having a dynamic height based on scaling.
public class JustifiedLayout: NSCollectionViewLayout {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var contentHeight: CGFloat = 0

    var items: [DynamicLayoutItem] = []

    public var targetRowHeight: CGFloat = 200
    public var spacing: CGFloat = 4
    public var sectionInset: NSEdgeInsets = .init(top: 20, left: 20, bottom: 20, right: 20)

    override public func prepare() {
        super.prepare()

        cache.removeAll()
        contentHeight = 0

        guard let collectionView, !items.isEmpty else { return }

        let availableWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right

        var yOffset = sectionInset.top
        var currentRowItems: [(index: Int, aspectRatio: CGFloat)] = []
        var currentRowWidth: CGFloat = 0

        for (index, item) in items.enumerated() {
            let itemWidth = targetRowHeight * item.aspectRatio
            let spacingForItem = currentRowItems.isEmpty ? 0 : spacing
            let projectedWidth = currentRowWidth + itemWidth + spacingForItem

            if projectedWidth > availableWidth, !currentRowItems.isEmpty {
                // Lay out the completed row (scaled to fill width)
                yOffset = layoutRow(
                    items: currentRowItems,
                    availableWidth: availableWidth,
                    yOffset: yOffset,
                    stretchToFill: true
                )

                currentRowItems = []
                currentRowWidth = 0
            }

            let spacingBefore = currentRowItems.isEmpty ? 0 : spacing
            currentRowWidth += itemWidth + spacingBefore
            currentRowItems.append((index: index, aspectRatio: item.aspectRatio))
        }

        // Last row — do NOT stretch to fill
        if !currentRowItems.isEmpty {
            yOffset = layoutRow(
                items: currentRowItems,
                availableWidth: availableWidth,
                yOffset: yOffset,
                stretchToFill: false
            )
        }

        contentHeight = yOffset + sectionInset.bottom
    }

    private func layoutRow(
        items: [(index: Int, aspectRatio: CGFloat)],
        availableWidth: CGFloat,
        yOffset: CGFloat,
        stretchToFill: Bool
    ) -> CGFloat {
        let totalSpacing = spacing * CGFloat(items.count - 1)
        let rowHeight: CGFloat

        if stretchToFill {
            // Scale all items so they fill the available width exactly
            let totalAspectRatio = items.reduce(0) { $0 + $1.aspectRatio }
            rowHeight = (availableWidth - totalSpacing) / totalAspectRatio
        } else {
            rowHeight = targetRowHeight
        }

        var xOffset = sectionInset.left

        for item in items {
            let itemWidth = rowHeight * item.aspectRatio
            let indexPath = IndexPath(item: item.index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = CGRect(x: xOffset, y: yOffset, width: itemWidth, height: rowHeight)
            cache.append(attributes)

            xOffset += itemWidth + spacing
        }

        return yOffset + rowHeight + spacing
    }

    override public var collectionViewContentSize: NSSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override public func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cache.filter { $0.frame.intersects(rect) }
    }

    override public func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cache.count else {
            return NSCollectionViewLayoutAttributes()
        }
        // Attributes are stored in insertion order, not index order
        return cache.first { $0.indexPath == indexPath }
    }

    override public func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let oldBounds = collectionView?.bounds ?? .zero
        return newBounds.width != oldBounds.width
    }
}
