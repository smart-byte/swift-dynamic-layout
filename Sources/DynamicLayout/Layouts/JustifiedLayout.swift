//
//  JustifiedLayout.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// Google-Photos-style justified layout where items fill the row width
/// with each row having a dynamic height based on scaling.
public class JustifiedLayout: NSCollectionViewLayout, LayoutItemsProvider {
    private var cache = [NSCollectionViewLayoutAttributes]()
    private var oldCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentHeight: CGFloat = 0

    public var items: [DynamicLayoutItem] = []

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
        guard indexPath.item < cache.count else { return nil }
        // Attributes are stored in insertion order, not index order
        return cache.first { $0.indexPath == indexPath }
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

    /// Find the correct insertion index. Row-aware: finds the row, then X position within it.
    public func dropIndex(at point: CGPoint) -> Int {
        guard !cache.isEmpty else { return 0 }

        let rowItems = itemsInRow(nearY: point.y)
        guard !rowItems.isEmpty else { return items.count }

        let sorted = rowItems.sorted { $0.frame.origin.x < $1.frame.origin.x }
        for attr in sorted {
            guard let ip = attr.indexPath else { continue }
            if point.x < attr.frame.midX { return ip.item }
        }
        return (sorted.last?.indexPath?.item ?? items.count - 1) + 1
    }

    /// Indicator frame for a given insertion index.
    public func indicatorFrame(forInsertionAt index: Int) -> CGRect {
        if index < cache.count {
            let itemAttrs = cache.first { $0.indexPath?.item == index }
            guard let f = itemAttrs?.frame else { return .zero }
            return CGRect(x: f.origin.x - spacing / 2 - 1.5, y: f.origin.y, width: 3, height: f.height)
        } else if let last = cache.last {
            return CGRect(x: last.frame.maxX + spacing / 2 - 1.5, y: last.frame.origin.y, width: 3, height: last.frame.height)
        }
        return .zero
    }

    private func itemsInRow(nearY y: CGFloat) -> [NSCollectionViewLayoutAttributes] {
        let groups = Dictionary(grouping: cache) { Int($0.frame.origin.y.rounded()) }

        var best: [NSCollectionViewLayoutAttributes] = []
        var bestDist = CGFloat.infinity

        for (_, attrs) in groups {
            guard let first = attrs.first else { continue }
            if y >= first.frame.minY, y <= first.frame.maxY { return attrs }
            let dist = min(abs(y - first.frame.minY), abs(y - first.frame.maxY))
            if dist < bestDist {
                bestDist = dist
                best = attrs
            }
        }
        return best
    }
}
