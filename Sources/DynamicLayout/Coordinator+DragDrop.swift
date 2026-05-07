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
        let frame = parent.layoutItems[indexPath.item]
        guard let url = parent.urlForFrame(frame.id) else { return nil }
        return url as NSURL
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

        // Capture each dragging item's *source* image-components — what
        // NSCollectionView built from `cell.draggingImageComponents` —
        // and pin them as the active provider. This pins the source
        // preview to the cell snapshot, which a target's `validateDrop`
        // is free to override; the cache lets us restore the cell
        // snapshot when the cursor returns to this collection view.
        session.enumerateDraggingItems(
            options: [],
            for: collectionView,
            classes: [NSURL.self],
            searchOptions: [:]
        ) { [weak self] item, _, _ in
            guard let self, let url = item.item as? URL else { return }
            let captured = item.imageComponents ?? []
            sourceComponentsByURL[url] = captured
            item.imageComponentsProvider = { captured }
        }

        dragSession.begin()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        draggingSession _: NSDraggingSession,
        endedAt _: NSPoint, dragOperation _: NSDragOperation
    ) {
        (collectionView as? NiblessCollectionView)?.hideDropIndicator()
        (collectionView as? NiblessCollectionView)?.setDropTargetHighlight(false)
        pendingDropIndex = nil
        unpinSourceItems(in: collectionView)

        // Always reset — cross-pane/cross-app drops run acceptDrop on
        // a different coordinator, so without this the source pane's
        // updateNSView stays guarded and the FolderWatcher's post-move
        // refresh never lands. Same-pane reorder protects its FLIP
        // animation via `isProcessingDrop`, which we leave intact.
        isDragging = false
        draggedIndexPaths = []
        sourceComponentsByURL.removeAll()

        dragSession.end()
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
        let nibless = collectionView as? NiblessCollectionView
        let point = collectionView.convert(info.draggingLocation, from: nil)
        let isInternal = info.draggingSource as? NSCollectionView == collectionView

        // ESC pressed during the drag → refuse any drop, regardless of the
        // synthetic mouse-up's landing point.
        if dragSession.isCancelled {
            nibless?.hideDropIndicator()
            nibless?.setDropTargetHighlight(false)
            return []
        }

        // Finder-style adaptive flying preview: as the cursor enters
        // this collection view, the dragging-image components are
        // either restored to the source's cell snapshot (if we are
        // the source returning to ourselves) or swapped to this
        // collection's drag-image style (if we're a foreign target).
        // The override lasts until another collection / table view
        // takes over, or until `endedAt` clears the cache.
        adaptDraggingPreview(info: info, in: collectionView, isInternal: isInternal)

        // Folder-cell drop target FIRST — applies to both internal
        // and external drags so a same-pane drag onto a sibling
        // subfolder is a real move (matches FileListView). Refusing
        // an internal drag wholesale up here would block that case.
        // NSCollectionView paints `.asDropTarget` on the indicated
        // cell automatically; ThumbnailItem renders the accent border.
        if let hitIndexPath = collectionView.indexPathForItem(at: point),
           hitIndexPath.item < parent.layoutItems.count,
           let folderURL = directoryURL(at: hitIndexPath),
           let op = dropValidator?(info, folderURL), op != []
        {
            proposedDropOperation.pointee = .on
            proposedDropIndexPath.pointee = NSIndexPath(forItem: hitIndexPath.item, inSection: 0)
            nibless?.setDropTargetHighlight(false)
            nibless?.hideDropIndicator()
            return op
        }

        // Internal drag landed on whitespace or a non-folder cell —
        // moving into the same folder we came from is a no-op, so
        // refuse it (or render the reorder line if reorder is on).
        // Either way, pane-border highlight stays off — the cue for
        // "drop here = parent folder" only makes sense for external
        // drags coming from outside this pane.
        if isInternal {
            guard parent.allowsInternalReorder else {
                proposedDropOperation.pointee = .before
                proposedDropIndexPath.pointee = NSIndexPath(forItem: parent.layoutItems.count, inSection: 0)
                nibless?.hideDropIndicator()
                nibless?.setDropTargetHighlight(false)
                return []
            }
            proposedDropOperation.pointee = .before
            updateInternalReorderIndicator(
                collectionView: collectionView,
                point: point,
                proposedDropIndexPath: proposedDropIndexPath
            )
            nibless?.setDropTargetHighlight(false)
            return .move
        }

        // External drag on whitespace / non-folder cell — drop into
        // the pane's own folder. Out-of-range index + `.before` keeps
        // NSCollectionView from painting `.asDropTarget` on a random
        // cell; the pane border is the cue.
        nibless?.hideDropIndicator()
        proposedDropOperation.pointee = .before
        proposedDropIndexPath.pointee = NSIndexPath(
            forItem: parent.layoutItems.count, inSection: 0
        )
        let op = dropValidator?(info, parent.folderURL) ?? []
        nibless?.setDropTargetHighlight(op != [])
        return op
    }

    /// Swaps each dragging item's `imageComponentsProvider` based on
    /// whether the cursor is inside the source collection view or a
    /// foreign target. Internal: restore the cell-snapshot captured at
    /// `willBeginAt`. Foreign: render via `DragImageComposer` with this
    /// collection's `LayoutMode.dragImageStyle` and the target
    /// `ItemStyle`'s `dragShowsLabel` rule. Called from `validateDrop`
    /// on every mouse move while the cursor is inside our collection;
    /// reassigning the provider is cheap (it's only invoked when
    /// AppKit redraws the drag image).
    private func adaptDraggingPreview(
        info: NSDraggingInfo,
        in collectionView: NSCollectionView,
        isInternal: Bool
    ) {
        let style = parent.layoutMode.dragImageStyle
        let showsLabel = parent.itemStyle.dragShowsLabel
        let syncProvider = parent.syncImageProvider
        info.enumerateDraggingItems(
            options: [],
            for: collectionView,
            classes: [NSURL.self],
            searchOptions: [:]
        ) { [weak self] item, _, _ in
            guard let url = item.item as? URL else { return }
            if isInternal,
               let cached = self?.sourceComponentsByURL[url]
            {
                item.imageComponentsProvider = { cached }
                return
            }
            item.imageComponentsProvider = {
                DragImageComposer.compose(
                    for: url,
                    style: style,
                    syncProvider: syncProvider,
                    showsLabel: showsLabel
                )
            }
        }
    }

    /// Computes the layout-specific drop index + indicator frame for
    /// internal reorder and updates the custom drop indicator. Factored
    /// out so the validateDrop branch stays readable.
    private func updateInternalReorderIndicator(
        collectionView: NSCollectionView,
        point: CGPoint,
        proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>
    ) {
        let layout = collectionView.collectionViewLayout
        let nibless = collectionView as? NiblessCollectionView

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
    }

    /// Returns the URL of the layout item at `indexPath` IFF it points to
    /// a directory. Used by the folder-cell drop-target hit test.
    private func directoryURL(at indexPath: IndexPath) -> URL? {
        guard indexPath.item < parent.layoutItems.count else { return nil }
        let frame = parent.layoutItems[indexPath.item]
        guard let url = parent.urlForFrame(frame.id) else { return nil }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true ? url : nil
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
        if dragSession.isCancelled {
            (collectionView as? NiblessCollectionView)?.hideDropIndicator()
            (collectionView as? NiblessCollectionView)?.setDropTargetHighlight(false)
            return false
        }

        (collectionView as? NiblessCollectionView)?.hideDropIndicator()
        (collectionView as? NiblessCollectionView)?.setDropTargetHighlight(false)

        let isInternal = draggingInfo.draggingSource as? NSCollectionView == collectionView

        if isInternal, parent.allowsInternalReorder, let draggedIndex = draggedIndexPaths.first?.item {
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

    // MARK: - External File Drop

    private func handleExternalDrop(
        collectionView _: NSCollectionView,
        draggingInfo: NSDraggingInfo,
        destinationOverride: URL? = nil
    ) -> Bool {
        let destination = destinationOverride ?? parent.folderURL
        guard dropPerformer?(draggingInfo, destination) == true else {
            pendingDropIndex = nil
            isDragging = false
            draggedIndexPaths = []
            return false
        }
        pendingDropIndex = nil

        // No manual layoutItems mutation: the destination pane's file watcher
        // picks up the new entries and animates the diff in. The source pane's
        // watcher does the same on its side for moves.
        DispatchQueue.main.async { [weak self] in
            self?.isDragging = false
            self?.draggedIndexPaths = []
        }
        return true
    }

    // MARK: - Layout Update Helper

    internal func updateLayout(_ collectionView: NSCollectionView, items: [LayoutItemFrame]) {
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
