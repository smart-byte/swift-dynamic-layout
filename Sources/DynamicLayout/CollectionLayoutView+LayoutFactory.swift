//
//  CollectionLayoutView+LayoutFactory.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import AppKit

/// Layout construction + property mutation. Pulled out of
/// `CollectionLayoutView.swift` to keep that file under SwiftLint's
/// 400-line ceiling — no behaviour change.
extension CollectionLayoutView {
    /// Build a fresh layout for the current `layoutMode` / `itemStyle`.
    /// Reads everything off `self` so callers stay one-liners.
    ///
    /// Section insets match the inter-item spacing so the gutter at
    /// the scroll-area edge reads as the same visual gap as between
    /// items. Waterfall and verticalFlow re-derive their inset inside
    /// `prepare()` (their spacing depends on bounds + slider); the
    /// other modes have a fixed item spacing and use a matching inset
    /// directly here.
    func createLayout() -> NSCollectionViewLayout {
        let squareCells = itemStyle == .tile

        switch layoutMode {
        case .verticalFlow, .list:
            let layout = VerticalFlowLayout()
            layout.items = layoutItems
            layout.spacingPercentage = itemSpacing
            return layout

        case .waterfall:
            let layout = WaterfallLayout()
            layout.items = layoutItems
            layout.columns = columns
            layout.spacingPercentage = itemSpacing
            return layout

        case .horizontalFlow:
            let layout = HorizontalFlowLayout()
            layout.items = layoutItems
            layout.spacingPercentage = itemSpacing
            layout.useSquareCells = squareCells
            // The toolbar slider doesn't control horizontalFlow's
            // cell size — cells stretch to the available cell height.
            // Push that height down as the layout-level scaleReference
            // so the photoFrame matte stays uniform across cells
            // regardless of where the slider sits, and stays in sync
            // when the window resizes (prepare fires on every bounds
            // change).
            layout.onLayoutPrepared = { [weak layout] availableHeight in
                guard let cv = layout?.collectionView else { return }
                for item in cv.visibleItems() {
                    (item as? ThumbnailItem)?.scaleReference = availableHeight
                }
            }
            return layout

        case .justified:
            let layout = JustifiedLayout()
            layout.items = layoutItems
            layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            layout.spacing = 4
            layout.targetRowHeight = targetSize
            layout.useSquareCells = squareCells
            return layout

        case .horizontalJustified:
            let layout = HorizontalJustifiedLayout()
            layout.items = layoutItems
            layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
            layout.spacing = 4
            layout.targetColumnWidth = targetSize
            layout.useSquareCells = squareCells
            return layout
        }
    }

    func updateLayoutItems(_ layout: NSCollectionViewLayout?, items: [LayoutItemFrame]) {
        (layout as? LayoutItemsProvider)?.setItems(items)
    }

    /// React to an item-style change without swapping the layout mode.
    /// Style-driven flags (e.g. `useSquareCells` for `.tile`) need to take
    /// effect on the live layout, then we invalidate so cells reflow
    /// before the cell views themselves get re-rendered with the new style.
    func applyItemStyleChange(collectionView: NSCollectionView) {
        updateLayoutProperties(collectionView.collectionViewLayout)
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.reloadData()
    }

    func updateLayoutProperties(_ layout: NSCollectionViewLayout?) {
        let squareCells = itemStyle == .tile
        if let layout = layout as? VerticalFlowLayout {
            layout.spacingPercentage = itemSpacing
        } else if let layout = layout as? WaterfallLayout {
            layout.spacingPercentage = itemSpacing
            layout.columns = columns
        } else if let layout = layout as? HorizontalFlowLayout {
            layout.spacingPercentage = itemSpacing
            layout.useSquareCells = squareCells
        } else if let layout = layout as? JustifiedLayout {
            layout.targetRowHeight = targetSize
            layout.useSquareCells = squareCells
        } else if let layout = layout as? HorizontalJustifiedLayout {
            layout.targetColumnWidth = targetSize
            layout.useSquareCells = squareCells
        }
    }
}
