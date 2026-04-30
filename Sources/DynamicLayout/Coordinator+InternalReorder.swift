//
//  Coordinator+InternalReorder.swift
//
//
//  Created by Mario Heubach on 30.04.26.
//

import AppKit

// MARK: - Internal Reorder Drop

extension Coordinator {
    /// Same-pane drag: rearrange `layoutItems` and animate the
    /// transition via `animateReorder` (FLIPAnimation extension). No file
    /// system work — internal reorder is a virtual sort, not a real
    /// move. Same-folder cross-pane drops still go through the external
    /// path.
    func handleInternalDrop(
        collectionView: NSCollectionView, draggedIndex: Int
    ) -> Bool {
        let targetIndex = min(pendingDropIndex ?? 0, parent.layoutItems.count)
        let adjustedTarget: Int = if targetIndex > draggedIndex {
            min(targetIndex - 1, parent.layoutItems.count - 1)
        } else {
            targetIndex
        }
        pendingDropIndex = nil

        guard adjustedTarget != draggedIndex else {
            isDragging = false
            draggedIndexPaths = []
            return false
        }

        isProcessingDrop = true

        // Save current layer positions keyed by item ID (before reorder)
        var oldPositionsByID: [UUID: CGPoint] = [:]
        var oldBoundsByID: [UUID: CGRect] = [:]
        for ip in collectionView.indexPathsForVisibleItems() {
            guard ip.item < parent.layoutItems.count,
                  let viewItem = collectionView.item(at: ip),
                  let layer = viewItem.view.layer
            else { continue }
            let itemID = parent.layoutItems[ip.item].id
            oldPositionsByID[itemID] = layer.position
            oldBoundsByID[itemID] = layer.bounds
        }

        let movedItem = parent.layoutItems.remove(at: draggedIndex)
        let safeTarget = min(adjustedTarget, parent.layoutItems.count)
        parent.layoutItems.insert(movedItem, at: safeTarget)

        lastItemCount = parent.layoutItems.count
        lastItemIDs = parent.layoutItems.map(\.id)
        updateLayout(collectionView, items: parent.layoutItems)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.reloadData()
        CATransaction.commit()

        animateReorder(
            collectionView: collectionView,
            oldPositions: oldPositionsByID,
            oldBounds: oldBoundsByID
        )
        return true
    }
}
