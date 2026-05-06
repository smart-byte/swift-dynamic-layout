//
//  FileCollectionView+LayoutFactory.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import AppKit

/// Layout construction + property mutation. Pulled out of
/// `FileCollectionView.swift` to keep that file under SwiftLint's
/// 400-line ceiling — no behaviour change.
extension FileCollectionView {
    /// Build a fresh layout for the current `layoutMode` / `itemStyle`.
    /// Reads everything off `self` so callers stay one-liners.
    func createLayout() -> NSCollectionViewLayout {
        let insets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let squareCells = itemStyle == .tile

        switch layoutMode {
        case .verticalFlow, .list:
            let layout = VerticalFlowLayout()
            layout.sectionInset = insets
            layout.items = layoutItems
            layout.spacingPercentage = itemSpacing
            return layout

        case .waterfall:
            let layout = WaterfallLayout()
            layout.sectionInset = insets
            layout.items = layoutItems
            layout.columns = columns
            layout.spacingPercentage = itemSpacing
            return layout

        case .horizontalFlow:
            let layout = HorizontalFlowLayout()
            layout.items = layoutItems
            layout.sectionInset = insets
            layout.minimumInteritemSpacing = 10
            layout.minimumLineSpacing = 10
            return layout

        case .justified:
            let layout = JustifiedLayout()
            layout.items = layoutItems
            layout.sectionInset = insets
            layout.spacing = 4
            layout.targetRowHeight = targetSize
            layout.useSquareCells = squareCells
            return layout

        case .horizontalJustified:
            let layout = HorizontalJustifiedLayout()
            layout.items = layoutItems
            layout.sectionInset = insets
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
        } else if let layout = layout as? JustifiedLayout {
            layout.targetRowHeight = targetSize
            layout.useSquareCells = squareCells
        } else if let layout = layout as? HorizontalJustifiedLayout {
            layout.targetColumnWidth = targetSize
            layout.useSquareCells = squareCells
        }
    }
}
