//
//  VerticalFlowLayout.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// Single-column vertical flow — each item spans the full available width,
/// height is determined by aspect ratio. Like HorizontalFlowLayout but rotated 90°.
public class VerticalFlowLayout: NSCollectionViewLayout, LayoutItemsProvider {
    public var spacingPercentage: CGFloat = 0.02
    public var sectionInset: NSEdgeInsets = .init(top: 20, left: 20, bottom: 20, right: 20)

    public var items: [LayoutItemFrame] = []

    private var cache = [NSCollectionViewLayoutAttributes]()
    private var oldCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentHeight: CGFloat = 0

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
        let spacing = totalWidth * spacingPercentage
        sectionInset = NSEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        let availableWidth = totalWidth - sectionInset.left - sectionInset.right

        var yOffset: CGFloat = sectionInset.top

        for (index, item) in items.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            let itemHeight = availableWidth / item.aspectRatio

            attributes.frame = CGRect(x: sectionInset.left, y: yOffset, width: availableWidth, height: itemHeight)
            cache.append(attributes)

            yOffset += itemHeight + spacing
        }

        contentHeight = yOffset - (items.isEmpty ? 0 : availableWidth * spacingPercentage) + sectionInset.bottom
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

    /// Find the correct insertion index by Y position (single vertical column).
    public func dropIndex(at point: CGPoint) -> Int {
        for attr in cache {
            guard let ip = attr.indexPath else { continue }
            if point.y < attr.frame.midY { return ip.item }
        }
        return items.count
    }

    /// Indicator frame for a given insertion index.
    public func indicatorFrame(forInsertionAt index: Int) -> CGRect {
        guard let collectionView else { return .zero }
        let availableWidth = collectionView.bounds.width - sectionInset.left - sectionInset.right
        let spacing = availableWidth * spacingPercentage

        if index < cache.count {
            let y = cache[index].frame.origin.y - spacing / 2 - 1.5
            return CGRect(x: sectionInset.left, y: y, width: availableWidth, height: 3)
        } else if let last = cache.last {
            let y = last.frame.maxY + spacing / 2 - 1.5
            return CGRect(x: sectionInset.left, y: y, width: availableWidth, height: 3)
        }
        return .zero
    }
}
