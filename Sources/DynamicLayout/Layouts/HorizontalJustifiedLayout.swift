//
//  HorizontalJustifiedLayout.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// Justified layout rotated 90° — items flow top-to-bottom into columns,
/// each column is scaled to fill the available height exactly.
/// Horizontal scrolling. Like JustifiedLayout but for columns instead of rows.
public class HorizontalJustifiedLayout: NSCollectionViewFlowLayout, LayoutItemsProvider {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var oldCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentWidth: CGFloat = 0

    public var items: [DynamicLayoutItem] = []

    public var targetColumnWidth: CGFloat = 200
    public var spacing: CGFloat = 4

    override public func prepare() {
        super.prepare()

        cache.removeAll()
        contentWidth = 0

        guard let collectionView, !items.isEmpty else { return }

        scrollDirection = .horizontal

        let availableHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom

        var xOffset = sectionInset.left
        var currentColItems: [(index: Int, aspectRatio: CGFloat)] = []
        var currentColHeight: CGFloat = 0

        for (index, item) in items.enumerated() {
            // At targetColumnWidth, item height = targetColumnWidth / aspectRatio
            let itemHeight = targetColumnWidth / item.aspectRatio
            let spacingForItem = currentColItems.isEmpty ? 0 : spacing
            let projectedHeight = currentColHeight + itemHeight + spacingForItem

            if projectedHeight > availableHeight, !currentColItems.isEmpty {
                xOffset = layoutColumn(
                    items: currentColItems,
                    availableHeight: availableHeight,
                    xOffset: xOffset,
                    stretchToFill: true
                )

                currentColItems = []
                currentColHeight = 0
            }

            let spacingBefore = currentColItems.isEmpty ? 0 : spacing
            currentColHeight += itemHeight + spacingBefore
            currentColItems.append((index: index, aspectRatio: item.aspectRatio))
        }

        // Last column — do NOT stretch to fill
        if !currentColItems.isEmpty {
            xOffset = layoutColumn(
                items: currentColItems,
                availableHeight: availableHeight,
                xOffset: xOffset,
                stretchToFill: false
            )
        }

        contentWidth = xOffset + sectionInset.right
    }

    private func layoutColumn(
        items: [(index: Int, aspectRatio: CGFloat)],
        availableHeight: CGFloat,
        xOffset: CGFloat,
        stretchToFill: Bool
    ) -> CGFloat {
        let totalSpacing = spacing * CGFloat(items.count - 1)
        let colWidth: CGFloat

        if stretchToFill {
            // Scale so items fill the available height exactly.
            // Each item's height = colWidth / aspectRatio.
            // Sum of heights = colWidth * sum(1/aspectRatio) = availableHeight - totalSpacing
            let totalInvAspect = items.reduce(0) { $0 + 1.0 / $1.aspectRatio }
            colWidth = (availableHeight - totalSpacing) / totalInvAspect
        } else {
            colWidth = targetColumnWidth
        }

        var yOffset = sectionInset.top

        for item in items {
            let itemHeight = colWidth / item.aspectRatio
            let indexPath = IndexPath(item: item.index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            attributes.frame = CGRect(x: xOffset, y: yOffset, width: colWidth, height: itemHeight)
            cache.append(attributes)

            yOffset += itemHeight + spacing
        }

        return xOffset + colWidth + spacing
    }

    override public var collectionViewContentSize: NSSize {
        guard let collectionView else { return .zero }
        return CGSize(width: contentWidth, height: collectionView.bounds.height)
    }

    override public func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        cache.filter { $0.frame.intersects(rect) }
    }

    override public func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.item < cache.count else { return nil }
        return cache.first { $0.indexPath == indexPath }
    }

    override public func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let oldBounds = collectionView?.bounds ?? .zero
        return newBounds.height != oldBounds.height
    }

    override public func invalidationContext(
        forBoundsChange newBounds: NSRect
    ) -> NSCollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let cv = collectionView else { return context }

        let oldH = cv.bounds.height - sectionInset.top - sectionInset.bottom
        let newH = newBounds.height - sectionInset.top - sectionInset.bottom
        guard oldH > 0, newH > 0 else { return context }

        let oldX = cv.enclosingScrollView?.documentVisibleRect.origin.x ?? 0
        let scale = newH / oldH

        if collectionViewContentSize.width * scale <= newBounds.width {
            context.contentOffsetAdjustment = NSPoint(x: -oldX, y: 0)
        } else {
            context.contentOffsetAdjustment = NSPoint(x: oldX * (scale - 1), y: 0)
        }
        return context
    }

    // MARK: - Batch Update Animation Support

    override public func prepare(forCollectionViewUpdates updateItems: [NSCollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        oldCache = Dictionary(
            uniqueKeysWithValues: cache.compactMap { attr -> (IndexPath, NSCollectionViewLayoutAttributes)? in
                guard let ip = attr.indexPath else { return nil }
                // swiftlint:disable:next force_cast
                return (ip, attr.copy() as! NSCollectionViewLayoutAttributes)
            }
        )
    }

    override public func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        oldCache = [:]
    }

    override public func initialLayoutAttributesForAppearingItem(
        at itemIndexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        layoutAttributesForItem(at: itemIndexPath)
    }

    override public func finalLayoutAttributesForDisappearingItem(
        at itemIndexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        oldCache[itemIndexPath] ?? layoutAttributesForItem(at: itemIndexPath)
    }

    // MARK: - Drop Target Support

    /// Column-aware drop: find the column, then Y position within it.
    public func dropIndex(at point: CGPoint) -> Int {
        guard !cache.isEmpty else { return 0 }

        let colItems = itemsInColumn(nearX: point.x)
        guard !colItems.isEmpty else { return items.count }

        let sorted = colItems.sorted { $0.frame.origin.y < $1.frame.origin.y }
        for attr in sorted {
            guard let ip = attr.indexPath else { continue }
            if point.y < attr.frame.midY { return ip.item }
        }
        return (sorted.last?.indexPath?.item ?? items.count - 1) + 1
    }

    /// Horizontal indicator spanning the column width.
    public func indicatorFrame(forInsertionAt index: Int) -> CGRect {
        if index < cache.count {
            let itemAttrs = cache.first { $0.indexPath?.item == index }
            guard let f = itemAttrs?.frame else { return .zero }
            return CGRect(x: f.origin.x, y: f.origin.y - spacing / 2 - 1.5, width: f.width, height: 3)
        } else if let last = cache.last {
            return CGRect(x: last.frame.origin.x, y: last.frame.maxY + spacing / 2 - 1.5, width: last.frame.width, height: 3)
        }
        return .zero
    }

    private func itemsInColumn(nearX x: CGFloat) -> [NSCollectionViewLayoutAttributes] {
        let groups = Dictionary(grouping: cache) { Int($0.frame.origin.x.rounded()) }

        var best: [NSCollectionViewLayoutAttributes] = []
        var bestDist = CGFloat.infinity

        for (_, attrs) in groups {
            guard let first = attrs.first else { continue }
            if x >= first.frame.minX, x <= first.frame.maxX { return attrs }
            let dist = min(abs(x - first.frame.minX), abs(x - first.frame.maxX))
            if dist < bestDist {
                bestDist = dist
                best = attrs
            }
        }
        return best
    }
}
