//
//  HorizontalFlowLayout.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class HorizontalFlowLayout: NSCollectionViewFlowLayout, LayoutItemsProvider {
    public var spacingPercentage: CGFloat = 0.02

    public var items: [LayoutItemFrame] = []

    /// Forces every cell to be a perfect square at the available
    /// height — used by the tile item style so the framed tile fills
    /// the row instead of adopting the image's aspect ratio.
    public var useSquareCells: Bool = false

    /// Fires from `prepare()` with the current `availableHeight` so
    /// the host can push a layout-aware scale reference (cell height)
    /// down to its cells without having to observe the collection
    /// view's frame separately.
    public var onLayoutPrepared: ((CGFloat) -> Void)?

    private var cache = [NSCollectionViewLayoutAttributes]()
    private var oldCache: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    /// Total content width, mirrored from the last `prepare()` so
    /// `collectionViewContentSize` is O(1) — NSCollectionView reads
    /// that property repeatedly per scroll frame.
    private var contentWidth: CGFloat = 0
    /// Last `availableHeight` we pushed to the host via
    /// `onLayoutPrepared`. Lets us skip the visible-cell iteration
    /// when nothing about the layout's effective scale changed.
    private var lastAvailableHeight: CGFloat = -1

    override public func prepare() {
        super.prepare()

        cache.removeAll()
        contentWidth = 0

        guard let collectionView else { return }

        // Same gutter-matches-gap policy as Waterfall / VerticalFlow:
        // derive spacing from the full bounds first, mirror it into
        // sectionInset, then compute available height — avoids the
        // feedback loop that would otherwise shift the value each
        // prepare pass.
        let totalHeight = collectionView.bounds.height
        let spacing = totalHeight * spacingPercentage
        // Auto-derive only when spacing is actually computed; an
        // explicit `spacingPercentage = 0` keeps the host-supplied
        // sectionInset untouched (used by unit tests that pin a
        // specific inset to verify item placement).
        if spacing > 0 {
            sectionInset = NSEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        }
        let availableHeight = totalHeight - sectionInset.top - sectionInset.bottom

        minimumInteritemSpacing = spacing
        minimumLineSpacing = spacing
        scrollDirection = .horizontal

        // Only push when the effective scale actually changed; the
        // didSet on each cell's `scaleReference` triggers a layout
        // pass per cell and we don't want that on every prepare()
        // (e.g. plain scrolling) when nothing relevant moved.
        if availableHeight != lastAvailableHeight {
            lastAvailableHeight = availableHeight
            onLayoutPrepared?(availableHeight)
        }

        var xOffset: CGFloat = sectionInset.left

        for (index, item) in items.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            let itemWidth = useSquareCells ? availableHeight : availableHeight * item.aspectRatio

            attributes.frame = CGRect(x: xOffset, y: sectionInset.top, width: itemWidth, height: availableHeight)
            cache.append(attributes)

            xOffset += itemWidth + spacing
        }

        // Cache content width for O(1) `collectionViewContentSize`.
        // Last item's maxX + right inset; spacing already baked into
        // xOffset advances above.
        if let last = cache.last {
            contentWidth = last.frame.maxX + sectionInset.right
        } else {
            contentWidth = sectionInset.left + sectionInset.right
        }
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
