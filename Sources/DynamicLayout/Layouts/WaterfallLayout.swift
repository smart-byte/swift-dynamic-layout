//
//  WaterfallLayout.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class WaterfallLayout: NSCollectionViewLayout, LayoutItemsProvider {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var oldCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentHeight: CGFloat = 0
    private var computedSpacing: CGFloat = 0

    public var items: [LayoutItemFrame] = []

    public var columns: Int = 5
    public var spacingPercentage: CGFloat = 0.05
    public var sectionInset: NSEdgeInsets = .init(top: 20, left: 20, bottom: 20, right: 20)

    override public func prepare() {
        super.prepare()

        cache.removeAll()
        contentHeight = 0

        guard let collectionView else { return }

        // Derive spacing from the full bounds first, then mirror it
        // into sectionInset so the gutter at the edge of the scroll
        // area matches the gap between items. Computing spacing
        // independently of sectionInset avoids a feedback loop where
        // each prepare pass would shift the value.
        let totalWidth = collectionView.bounds.width
        let nominalColumnWidth = totalWidth / CGFloat(columns)
        let spacing = nominalColumnWidth * spacingPercentage
        computedSpacing = spacing
        // Auto-derive only when spacing is actually computed; an
        // explicit `spacingPercentage = 0` keeps the host-supplied
        // sectionInset untouched (used by unit tests that pin a
        // specific inset to verify item placement).
        if spacing > 0 {
            sectionInset = NSEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        }

        let width = totalWidth - sectionInset.left - sectionInset.right
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
            let shortestColumn = yOffset.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0

            let indexPath = IndexPath(item: index, section: 0)
            let height = columnWidth / item.aspectRatio
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
        guard indexPath.item < cache.count else { return nil }
        return cache[indexPath.item]
    }

    override public func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        let oldBounds = collectionView?.bounds ?? .zero
        return newBounds.width != oldBounds.width
    }

    override public func invalidationContext(
        forBoundsChange newBounds: NSRect
    ) -> NSCollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)
        guard let cv = collectionView else { return context }

        let oldW = cv.bounds.width - sectionInset.left - sectionInset.right
        let newW = newBounds.width - sectionInset.left - sectionInset.right
        guard oldW > 0, newW > 0 else { return context }

        let oldY = cv.enclosingScrollView?.documentVisibleRect.origin.y ?? 0
        let scale = newW / oldW

        if collectionViewContentSize.height * scale <= newBounds.height {
            context.contentOffsetAdjustment = NSPoint(x: 0, y: -oldY)
        } else {
            context.contentOffsetAdjustment = NSPoint(x: 0, y: oldY * (scale - 1))
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

    /// Find insertion index by nearest item.
    public func dropIndex(at point: CGPoint) -> Int {
        guard !cache.isEmpty else { return 0 }

        let nearest = cache.min {
            hypot(point.x - $0.frame.midX, point.y - $0.frame.midY) <
                hypot(point.x - $1.frame.midX, point.y - $1.frame.midY)
        }
        guard let nearest, let ip = nearest.indexPath else { return items.count }

        return point.y > nearest.frame.midY ? ip.item + 1 : ip.item
    }

    /// Indicator frame for a given insertion index.
    public func indicatorFrame(forInsertionAt index: Int) -> CGRect {
        let gap = computedSpacing
        if index < cache.count {
            let f = cache[index].frame
            return CGRect(x: f.origin.x, y: f.origin.y - gap / 2 - 1.5, width: f.width, height: 3)
        } else if let last = cache.last {
            return CGRect(x: last.frame.origin.x, y: last.frame.maxY + gap / 2 - 1.5, width: last.frame.width, height: 3)
        }
        return .zero
    }
}
