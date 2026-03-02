//
//  Coordinator+DragDrop.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

// MARK: - Drag & Drop

public extension Coordinator {
    func collectionView(
        _: NSCollectionView, canDragItemsAt _: Set<IndexPath>, with _: NSEvent
    ) -> Bool {
        true
    }

    func collectionView(
        _: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard indexPath.item < parent.layoutItems.count else { return nil }
        // Reset from any previous drag before accumulating new indices
        draggedIndexPaths = []
        draggedIndexPaths.insert(indexPath)
        return parent.layoutItems[indexPath.item].url as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession session: NSDraggingSession,
        willBeginAt _: NSPoint, forItemsAt indexPaths: Set<IndexPath>
    ) {
        isDragging = true
        session.draggingFormation = .default
        session.animatesToStartingPositionsOnCancelOrFail = true

        // Restore original item visibility after NSCollectionView dims them.
        // Async ensures we run after NSCollectionView's internal handling.
        DispatchQueue.main.async {
            for indexPath in indexPaths {
                guard let item = collectionView.item(at: indexPath) else { continue }
                item.view.alphaValue = 1.0
                item.view.isHidden = false
                item.view.layer?.opacity = 1.0
            }
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint, dragOperation operation: NSDragOperation
    ) {
        (collectionView as? NiblessCollectionView)?.hideDropIndicator()
        pendingDropIndex = nil

        // Only reset here if the drag was cancelled (no operation).
        // For successful drops, acceptDrop handles cleanup after processing.
        if operation == [] {
            isDragging = false
            draggedIndexPaths = []
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop info: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        // .before gives NSCollectionView proper zone-based drop detection
        // (user doesn't need precise cursor placement on the indicator line).
        proposedDropOperation.pointee = .before

        let point = collectionView.convert(info.draggingLocation, from: nil)
        let layout = collectionView.collectionViewLayout
        let nibless = collectionView as? NiblessCollectionView

        // Each layout calculates its own drop index + indicator frame
        let index: Int
        let indicatorFrame: CGRect

        if let vf = layout as? VerticalFlowLayout {
            index = vf.dropIndex(at: point)
            indicatorFrame = vf.indicatorFrame(forInsertionAt: index)
        } else if let wf = layout as? WaterfallLayout {
            index = wf.dropIndex(at: point)
            indicatorFrame = wf.indicatorFrame(forInsertionAt: index)
        } else if let hf = layout as? HorizontalFlowLayout {
            index = hf.dropIndex(at: point)
            indicatorFrame = hf.indicatorFrame(forInsertionAt: index)
        } else if let jf = layout as? JustifiedLayout {
            index = jf.dropIndex(at: point)
            indicatorFrame = jf.indicatorFrame(forInsertionAt: index)
        } else if let hj = layout as? HorizontalJustifiedLayout {
            index = hj.dropIndex(at: point)
            indicatorFrame = hj.indicatorFrame(forInsertionAt: index)
        } else {
            index = proposedDropIndexPath.pointee.item
            indicatorFrame = .zero
        }

        pendingDropIndex = index
        proposedDropIndexPath.pointee = NSIndexPath(forItem: index, inSection: 0)

        if indicatorFrame != .zero {
            nibless?.showDropIndicator(at: indicatorFrame)
        } else {
            nibless?.hideDropIndicator()
        }

        if info.draggingSource as? NSCollectionView == collectionView {
            return .move
        } else if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
            return .copy
        } else {
            return .generic
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath _: IndexPath,
        dropOperation _: NSCollectionView.DropOperation
    ) -> Bool {
        (collectionView as? NiblessCollectionView)?.hideDropIndicator()

        let isInternal = draggingInfo.draggingSource as? NSCollectionView == collectionView

        if isInternal, let draggedIndex = draggedIndexPaths.first?.item {
            return handleInternalDrop(collectionView: collectionView, draggedIndex: draggedIndex)
        }

        return handleExternalDrop(collectionView: collectionView, draggingInfo: draggingInfo)
    }

    // MARK: - Internal Reorder Drop

    private func handleInternalDrop(
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

    // MARK: - External File Drop

    private func handleExternalDrop(
        collectionView: NSCollectionView, draggingInfo: NSDraggingInfo
    ) -> Bool {
        isProcessingDrop = true
        let pasteboard = draggingInfo.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first
        else {
            isProcessingDrop = false
            isDragging = false
            draggedIndexPaths = []
            return false
        }

        let targetIndex = min(pendingDropIndex ?? 0, parent.layoutItems.count)
        pendingDropIndex = nil
        parent.layoutItems.insert(
            DynamicLayoutItem(url: url, size: CGSize(width: 100, height: 100)),
            at: targetIndex
        )
        lastItemCount = parent.layoutItems.count
        lastItemIDs = parent.layoutItems.map(\.id)
        updateLayout(collectionView, items: parent.layoutItems)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.reloadData()
        CATransaction.commit()

        DispatchQueue.main.async { [weak self] in
            self?.isProcessingDrop = false
            self?.isDragging = false
            self?.draggedIndexPaths = []
        }
        return true
    }

    // MARK: - Reorder Animation

    private func animateReorder(
        collectionView: NSCollectionView,
        oldPositions: [UUID: CGPoint],
        oldBounds: [UUID: CGRect]
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let duration = 0.25
            let timing = CAMediaTimingFunction(name: .easeInEaseOut)

            for ip in collectionView.indexPathsForVisibleItems() {
                guard ip.item < parent.layoutItems.count,
                      let viewItem = collectionView.item(at: ip),
                      let layer = viewItem.view.layer
                else { continue }

                let itemID = parent.layoutItems[ip.item].id
                guard let oldPos = oldPositions[itemID] else { continue }

                if oldPos != layer.position {
                    let anim = CABasicAnimation(keyPath: "position")
                    anim.fromValue = oldPos
                    anim.duration = duration
                    anim.timingFunction = timing
                    layer.add(anim, forKey: "reorderPos")
                }

                if let oldFrame = oldBounds[itemID],
                   oldFrame.size != layer.bounds.size
                {
                    let anim = CABasicAnimation(keyPath: "bounds")
                    anim.fromValue = oldFrame
                    anim.duration = duration
                    anim.timingFunction = timing
                    layer.add(anim, forKey: "reorderBounds")
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                self.isProcessingDrop = false
                self.isDragging = false
                self.draggedIndexPaths = []
            }
        }
    }

    // MARK: - Layout Update Helper

    internal func updateLayout(_ collectionView: NSCollectionView, items: [DynamicLayoutItem]) {
        let layout = collectionView.collectionViewLayout
        if let layout = layout as? VerticalFlowLayout {
            layout.items = items
        } else if let layout = layout as? WaterfallLayout {
            layout.items = items
        } else if let layout = layout as? HorizontalFlowLayout {
            layout.items = items
        } else if let layout = layout as? JustifiedLayout {
            layout.items = items
        } else if let layout = layout as? HorizontalJustifiedLayout {
            layout.items = items
        }
    }
}
