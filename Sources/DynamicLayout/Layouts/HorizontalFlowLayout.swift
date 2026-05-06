//
//  HorizontalFlowLayout.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class HorizontalFlowLayout: NSCollectionViewFlowLayout, LayoutItemsProvider {
    public var spacingPercentage: CGFloat = 0.05

    public var items: [LayoutItemFrame] = []

    private var cache = [NSCollectionViewLayoutAttributes]()
    private var oldCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]

    override public func prepare() {
        super.prepare()

        cache.removeAll()

        guard let collectionView else { return }

        let availableHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
        let spacing = availableHeight * spacingPercentage

        minimumInteritemSpacing = spacing
        minimumLineSpacing = spacing
        scrollDirection = .horizontal

        var xOffset: CGFloat = sectionInset.left

        for (index, item) in items.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            let itemWidth = availableHeight * item.aspectRatio

            attributes.frame = CGRect(x: xOffset, y: sectionInset.top, width: itemWidth, height: availableHeight)
            cache.append(attributes)

            xOffset += itemWidth + spacing
        }
    }

    override public var collectionViewContentSize: NSSize {
        guard let collectionView else { return .zero }
        let totalWidth = items.reduce(sectionInset.left) { result, item -> CGFloat in
            let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
            let itemWidth = itemHeight * item.aspectRatio
            return result + itemWidth + minimumInteritemSpacing
        } - minimumInteritemSpacing + sectionInset.right
        return CGSize(width: totalWidth, height: collectionView.bounds.height)
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

    /// Find the correct insertion index by X position (single horizontal row).
    public func dropIndex(at point: CGPoint) -> Int {
        let sorted = cache.sorted { $0.frame.origin.x < $1.frame.origin.x }
        for attr in sorted {
            guard let ip = attr.indexPath else { continue }
            if point.x < attr.frame.midX { return ip.item }
        }
        return items.count
    }

    /// Indicator frame for a given insertion index.
    public func indicatorFrame(forInsertionAt index: Int) -> CGRect {
        guard let collectionView else { return .zero }
        let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
        let gap = minimumInteritemSpacing

        if index < cache.count {
            let x = cache[index].frame.origin.x - gap / 2 - 1.5
            return CGRect(x: x, y: sectionInset.top, width: 3, height: itemHeight)
        } else if let last = cache.last {
            let x = last.frame.maxX + gap / 2 - 1.5
            return CGRect(x: x, y: sectionInset.top, width: 3, height: itemHeight)
        }
        return .zero
    }
}
