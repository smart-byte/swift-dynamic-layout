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
    func createLayout(
        for mode: LayoutMode,
        items: [DynamicLayoutItem],
        spacing: CGFloat,
        columns: Int,
        targetSize: CGFloat = 200
    ) -> NSCollectionViewLayout {
        let insets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        switch mode {
        case .verticalFlow, .list:
            let layout = VerticalFlowLayout()
            layout.sectionInset = insets
            layout.items = items
            layout.spacingPercentage = spacing
            return layout

        case .waterfall:
            let layout = WaterfallLayout()
            layout.sectionInset = insets
            layout.items = items
            layout.columns = columns
            layout.spacingPercentage = spacing
            return layout

        case .horizontalFlow:
            let layout = HorizontalFlowLayout()
            layout.items = items
            layout.sectionInset = insets
            layout.minimumInteritemSpacing = 10
            layout.minimumLineSpacing = 10
            return layout

        case .justified:
            let layout = JustifiedLayout()
            layout.items = items
            layout.sectionInset = insets
            layout.spacing = 4
            layout.targetRowHeight = targetSize
            return layout

        case .horizontalJustified:
            let layout = HorizontalJustifiedLayout()
            layout.items = items
            layout.sectionInset = insets
            layout.spacing = 4
            layout.targetColumnWidth = targetSize
            return layout
        }
    }

    func updateLayoutItems(_ layout: NSCollectionViewLayout?, items: [DynamicLayoutItem]) {
        (layout as? LayoutItemsProvider)?.setItems(items)
    }

    func updateLayoutProperties(_ layout: NSCollectionViewLayout?, spacing: CGFloat, columns: Int, targetSize: CGFloat = 200) {
        if let layout = layout as? VerticalFlowLayout {
            layout.spacingPercentage = spacing
        } else if let layout = layout as? WaterfallLayout {
            layout.spacingPercentage = spacing
            layout.columns = columns
        } else if let layout = layout as? JustifiedLayout {
            layout.targetRowHeight = targetSize
        } else if let layout = layout as? HorizontalJustifiedLayout {
            layout.targetColumnWidth = targetSize
        }
    }
}
