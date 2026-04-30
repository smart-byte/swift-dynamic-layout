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
        _ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard indexPath.item < parent.layoutItems.count else { return nil }
        // Reset from any previous drag before accumulating new indices
        draggedIndexPaths = []
        draggedIndexPaths.insert(indexPath)
        // Pin visibility EARLY — NSCollectionView fires this before it starts
        // the source-cell fade. Setting the layer's CA actions here blocks
        // the fade entirely on the very first drag (subsequent drags are
        // already smooth because the actions persist on the cached layer).
        pinSourceItemsVisible(in: collectionView, indexPaths: [indexPath])
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

        // Pin the source items' visibility at 1.0 and block Core Animation
        // actions for opacity/hidden so NSCollectionView's default fade-out
        // of the source cells (which causes a brief flicker) never takes
        // effect. Restored in `endedAt`.
        pinSourceItemsVisible(in: collectionView, indexPaths: indexPaths)

        // AppKit's NSDraggingSession does not honour ESC out of the box for
        // NSCollectionView/NSTableView sources. Install a local key monitor
        // that swallows ESC during the drag and triggers a cancel with the
        // standard bounce-back animation.
        dragCancelled = false
        dragKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = ESC
            guard let self else { return event }
            dragCancelled = true
            cancelActiveDrag()
            return nil // swallow ESC
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint, dragOperation operation: NSDragOperation
    ) {
        (collectionView as? NiblessCollectionView)?.hideDropIndicator()
        (collectionView as? NiblessCollectionView)?.setDropTargetHighlight(false)
        pendingDropIndex = nil
        unpinSourceItems(in: collectionView)

        // Only reset here if the drag was cancelled (no operation).
        // For successful drops, acceptDrop handles cleanup after processing.
        if operation == [] {
            isDragging = false
            draggedIndexPaths = []
        }

        if let monitor = dragKeyMonitor {
            NSEvent.removeMonitor(monitor)
            dragKeyMonitor = nil
        }
        dragCancelled = false
    }

    private func pinSourceItemsVisible(in collectionView: NSCollectionView, indexPaths: Set<IndexPath>) {
        for indexPath in indexPaths {
            guard let item = collectionView.item(at: indexPath) else { continue }
            // Disable CA actions so subsequent opacity/hidden writes don't
            // animate. NSNull as an action is the documented opt-out.
            item.view.layer?.actions = ["opacity": NSNull(), "hidden": NSNull()]
            item.view.alphaValue = 1.0
            item.view.isHidden = false
            item.view.layer?.opacity = 1.0
        }
    }

    private func unpinSourceItems(in collectionView: NSCollectionView) {
        for indexPath in draggedIndexPaths {
            guard let item = collectionView.item(at: indexPath) else { continue }
            item.view.layer?.actions = nil
            item.view.alphaValue = 1.0
            item.view.isHidden = false
            item.view.layer?.opacity = 1.0
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop info: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        // ESC pressed during the drag → refuse any drop, regardless of the
        // synthetic mouse-up's landing point.
        if dragCancelled {
            (collectionView as? NiblessCollectionView)?.hideDropIndicator()
            return []
        }

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

        // Internal reorder: leave the existing in-pane move semantics alone.
        if info.draggingSource as? NSCollectionView == collectionView {
            return .move
        }

        // Folder-cell drop target: when the cursor is over a directory
        // item, route the drop INTO that subfolder. NSCollectionView
        // automatically applies `.asDropTarget` to the cell at
        // `proposedDropIndexPath`, which ThumbnailItem renders as a
        // border overlay (see `highlightState` override there).
        if let hitIndexPath = collectionView.indexPathForItem(at: point),
           hitIndexPath.item < parent.layoutItems.count,
           let folderURL = directoryURL(at: hitIndexPath),
           Self.proposedFileOperation(for: info, destinationFolder: folderURL) != []
        {
            let op = Self.proposedFileOperation(for: info, destinationFolder: folderURL)
            proposedDropOperation.pointee = .on
            proposedDropIndexPath.pointee = NSIndexPath(forItem: hitIndexPath.item, inSection: 0)
            nibless?.hideDropIndicator()
            nibless?.setDropTargetHighlight(false)
            return op
        }

        // External (or cross-pane) whitespace drop: highlight the whole
        // pane to signal "drop here = into this folder".
        let op = Self.proposedFileOperation(
            for: info,
            destinationFolder: parent.folderURL
        )
        nibless?.setDropTargetHighlight(op != [])
        return op
    }

    /// Returns the URL of the layout item at `indexPath` IFF it points to
    /// a directory. Used by the folder-cell drop-target hit test.
    private func directoryURL(at indexPath: IndexPath) -> URL? {
        guard indexPath.item < parent.layoutItems.count else { return nil }
        let url = parent.layoutItems[indexPath.item].url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true ? url : nil
    }

    /// Mirrors Finder's drop semantics:
    /// - ⌥ held → forced copy
    /// - same volume → move
    /// - cross volume → copy
    /// - destination unknown → fall back to `.generic`
    /// - no source URL would actually transfer (folder-onto-self,
    ///   folder-into-own-subtree, move-into-own-folder) → `[]` so the
    ///   cursor flips to the not-allowed badge.
    static func proposedFileOperation(
        for info: NSDraggingInfo,
        destinationFolder: URL?
    ) -> NSDragOperation {
        let forceCopy = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        guard let destinationFolder,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let firstSource = urls.first
        else {
            return forceCopy ? .copy : .generic
        }
        guard FileDropPerformer.canTransferAny(
            urls: urls, into: destinationFolder, forceCopy: forceCopy
        ) else {
            return []
        }
        if forceCopy { return .copy }
        return FileDropPerformer.sameVolume(firstSource, destinationFolder) ? .move : .copy
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        // Race-condition guard: validateDrop usually catches the cancel,
        // but if AppKit raced past it, refuse the drop here too. The flag
        // gets reset in the ended hook.
        if dragCancelled {
            (collectionView as? NiblessCollectionView)?.hideDropIndicator()
            (collectionView as? NiblessCollectionView)?.setDropTargetHighlight(false)
            return false
        }

        (collectionView as? NiblessCollectionView)?.hideDropIndicator()
        (collectionView as? NiblessCollectionView)?.setDropTargetHighlight(false)

        let isInternal = draggingInfo.draggingSource as? NSCollectionView == collectionView

        if isInternal, let draggedIndex = draggedIndexPaths.first?.item {
            return handleInternalDrop(collectionView: collectionView, draggedIndex: draggedIndex)
        }

        // Folder-cell drop: validateDrop set `.on` with that cell's
        // indexPath, so the drop target is the directory at that index
        // rather than the pane's own folder.
        let folderTarget: URL? = {
            guard dropOperation == .on else { return nil }
            return directoryURL(at: indexPath)
        }()
        return handleExternalDrop(
            collectionView: collectionView,
            draggingInfo: draggingInfo,
            destinationOverride: folderTarget
        )
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
        collectionView _: NSCollectionView,
        draggingInfo: NSDraggingInfo,
        destinationOverride: URL? = nil
    ) -> Bool {
        let pasteboard = draggingInfo.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty,
              let destinationFolder = destinationOverride ?? parent.folderURL
        else {
            pendingDropIndex = nil
            isDragging = false
            draggedIndexPaths = []
            return false
        }
        pendingDropIndex = nil

        let forceCopy = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
        FileDropPerformer.perform(urls: urls, into: destinationFolder, forceCopy: forceCopy)

        // No manual layoutItems mutation: the destination pane's file watcher
        // (Phase 10) picks up the new entries and animates the diff in. The
        // source pane's watcher does the same on its side for moves.
        DispatchQueue.main.async { [weak self] in
            self?.isDragging = false
            self?.draggedIndexPaths = []
        }
        return true
    }

    // MARK: - Cancel Active Drag

    /// Synthesizes a mouse-up event far off-screen so the active dragging
    /// session ends as cancelled (no valid drop target). NSDraggingSession
    /// picks up the event from the queue and runs its bounce-back animation
    /// thanks to `animatesToStartingPositionsOnCancelOrFail = true`.
    private func cancelActiveDrag() {
        let offScreen = NSPoint(x: -10000, y: -10000)
        if let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: offScreen,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) {
            NSApp.postEvent(up, atStart: true)
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
