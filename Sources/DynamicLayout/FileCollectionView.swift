//
//  FileCollectionView.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import Quartz
import SwiftUI

// MARK: - FileCollectionView (for verticalFlow, horizontalFlow, justified)

public struct FileCollectionView: NSViewRepresentable {
    @Binding var layoutItems: [DynamicLayoutItem]
    @Binding var selection: Set<IndexPath>
    @Binding var layoutMode: LayoutMode
    @Binding var itemStyle: ItemStyle
    @Binding var itemSpacing: CGFloat
    @Binding var columns: Int
    @Binding var targetSize: CGFloat
    let folderURL: URL?
    var actionHandler: ItemActionHandler?

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        layoutMode: Binding<LayoutMode>,
        itemStyle: Binding<ItemStyle> = .constant(.photoFrame),
        itemSpacing: Binding<CGFloat>,
        columns: Binding<Int> = .constant(5),
        targetSize: Binding<CGFloat> = .constant(200),
        folderURL: URL? = nil,
        actionHandler: ItemActionHandler? = nil
    ) {
        _layoutItems = layoutItems
        _selection = selection
        _layoutMode = layoutMode
        _itemStyle = itemStyle
        _itemSpacing = itemSpacing
        _columns = columns
        _targetSize = targetSize
        self.folderURL = folderURL
        self.actionHandler = actionHandler
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let collectionView = NiblessCollectionView()
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask(.every, forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.quickLookCoordinator = context.coordinator
        context.coordinator.actionHandler = actionHandler
        context.coordinator.collectionView = collectionView
        collectionView.actionHandler = actionHandler

        collectionView.registerProgrammatic(
            ThumbnailItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ThumbnailItem")
        )

        let layout = createLayout()
        collectionView.collectionViewLayout = layout

        collectionView.selectionIndexPaths = selection

        let scrollView = AutoScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let collectionView = nsView.documentView as? NSCollectionView else { return }

        let coordinator = context.coordinator

        // Skip collection view updates during active drag or drop processing
        if coordinator.isDragging || coordinator.isProcessingDrop {
            coordinator.parent = self
            return
        }

        let itemsSnapshot = DynamicLayoutItemsSnapshot(items: layoutItems)
        let itemsChanged = coordinator.lastItemsSnapshot != itemsSnapshot
        let layoutChanged = coordinator.lastLayoutMode != layoutMode
        let spacingChanged = coordinator.lastSpacing != itemSpacing
        let columnsChanged = coordinator.lastColumns != columns
        let targetSizeChanged = coordinator.lastTargetSize != targetSize
        let folderChanged = coordinator.currentFolderURL != folderURL

        coordinator.parent = self
        coordinator.actionHandler = actionHandler
        // Keep the collection view's pointer in sync with the latest handler;
        // each body re-render hands us a freshly-allocated handler instance.
        (collectionView as? NiblessCollectionView)?.actionHandler = actionHandler

        let validSelection = sanitizedSelection(selection, itemCount: layoutItems.count)
        if validSelection != selection {
            selection = validSelection
        }
        if collectionView.selectionIndexPaths != validSelection {
            collectionView.selectionIndexPaths = validSelection
        }

        // Save scroll position for the current folder before switching
        if itemsChanged, let url = coordinator.currentFolderURL {
            let firstVisible = collectionView.indexPathsForVisibleItems()
                .sorted { $0.item < $1.item }.first?.item ?? 0
            Coordinator.scrollCache[url] = firstVisible
        }
        coordinator.currentFolderURL = folderURL

        if layoutChanged {
            applyLayoutChange(
                collectionView: collectionView,
                coordinator: coordinator,
                itemsSnapshot: itemsSnapshot
            )
        } else if itemsChanged {
            applyItemsChange(
                collectionView: collectionView,
                coordinator: coordinator,
                itemsSnapshot: itemsSnapshot,
                folderChanged: folderChanged
            )
        } else if spacingChanged || columnsChanged || targetSizeChanged {
            applyPropertyChange(collectionView: collectionView, coordinator: coordinator)
        }

        coordinator.lastSpacing = itemSpacing
        coordinator.lastColumns = columns
        coordinator.lastTargetSize = targetSize

        if coordinator.lastItemStyle != itemStyle {
            coordinator.lastItemStyle = itemStyle
            applyItemStyleChange(collectionView: collectionView)
        }
    }

    // MARK: - Update Helpers

    private func applyLayoutChange(
        collectionView: NSCollectionView,
        coordinator: Coordinator,
        itemsSnapshot: DynamicLayoutItemsSnapshot
    ) {
        // FLIP morph: capture old positions → swap layout → animate old→new
        let oldFrames = coordinator.captureVisibleItemFrames(collectionView)
        let newLayout = createLayout()
        coordinator.lastLayoutMode = layoutMode
        coordinator.lastItemCount = layoutItems.count
        coordinator.lastItemIDs = layoutItems.map(\.id)
        coordinator.lastItemsSnapshot = itemsSnapshot

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.collectionViewLayout = newLayout
        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()
        CATransaction.commit()

        coordinator.animateFromOldFrames(oldFrames, in: collectionView, duration: 0.3)
    }

    private func applyItemsChange(
        collectionView: NSCollectionView,
        coordinator: Coordinator,
        itemsSnapshot: DynamicLayoutItemsSnapshot,
        folderChanged: Bool
    ) {
        let oldIDs = coordinator.lastItemIDs
        let newIDs = layoutItems.map(\.id)
        coordinator.lastItemCount = layoutItems.count
        coordinator.lastItemIDs = newIDs
        coordinator.lastItemsSnapshot = itemsSnapshot
        updateLayoutItems(collectionView.collectionViewLayout, items: layoutItems)

        if folderChanged {
            crossfadeReload(collectionView: collectionView)
        } else if oldIDs.isEmpty {
            // First load into this folder (no previous IDs). Skip the
            // remove+insert animation — there's nothing to fade out
            // and 100 simultaneous fade-ins look noisy.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            collectionView.reloadData()
            collectionView.layoutSubtreeIfNeeded()
            CATransaction.commit()
        } else {
            animateDiff(collectionView: collectionView, coordinator: coordinator, oldIDs: oldIDs, newIDs: newIDs)
        }
    }

    private func crossfadeReload(collectionView: NSCollectionView) {
        let folderURL = folderURL
        let layoutItems = layoutItems
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            collectionView.animator().alphaValue = 0
        } completionHandler: {
            collectionView.reloadData()
            if let url = folderURL,
               let savedIndex = Coordinator.scrollCache[url],
               savedIndex > 0, savedIndex < layoutItems.count
            {
                let ip = IndexPath(item: savedIndex, section: 0)
                collectionView.scrollToItems(at: [ip], scrollPosition: [.top, .left])
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                collectionView.animator().alphaValue = 1
            }
        }
    }

    /// Diff old vs new UUIDs and animate the remove+insert pairs. Pure
    /// reorders (same UUID set, different positions) fall back to the FLIP
    /// morph so existing items slide rather than flashing.
    private func animateDiff(
        collectionView: NSCollectionView,
        coordinator: Coordinator,
        oldIDs: [UUID],
        newIDs: [UUID]
    ) {
        let newIDSet = Set(newIDs)
        let oldIDSet = Set(oldIDs)
        var removedIndexPaths: Set<IndexPath> = []
        var insertedIndexPaths: Set<IndexPath> = []
        for (idx, id) in oldIDs.enumerated() where !newIDSet.contains(id) {
            removedIndexPaths.insert(IndexPath(item: idx, section: 0))
        }
        for (idx, id) in newIDs.enumerated() where !oldIDSet.contains(id) {
            insertedIndexPaths.insert(IndexPath(item: idx, section: 0))
        }

        if removedIndexPaths.isEmpty, insertedIndexPaths.isEmpty {
            let oldFrames = coordinator.captureVisibleItemFrames(collectionView)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            collectionView.reloadData()
            collectionView.layoutSubtreeIfNeeded()
            CATransaction.commit()
            coordinator.animateFromOldFrames(oldFrames, in: collectionView)
        } else {
            collectionView.animator().performBatchUpdates({
                collectionView.deleteItems(at: removedIndexPaths)
                collectionView.insertItems(at: insertedIndexPaths)
            }, completionHandler: nil)
        }
    }

    private func applyPropertyChange(collectionView: NSCollectionView, coordinator: Coordinator) {
        // FLIP animation for smooth property transitions
        let oldFrames = coordinator.captureVisibleItemFrames(collectionView)
        updateLayoutProperties(collectionView.collectionViewLayout)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
        CATransaction.commit()

        coordinator.animateFromOldFrames(oldFrames, in: collectionView, duration: 0.2)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

// MARK: - Coordinator

public class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var parent: FileCollectionView

    var lastLayoutMode: LayoutMode?
    var lastItemStyle: ItemStyle?
    var lastItemCount: Int = -1
    var lastItemIDs: [UUID] = []
    var lastItemsSnapshot: DynamicLayoutItemsSnapshot?
    var lastSpacing: CGFloat = -1
    var lastColumns: Int = -1
    var lastTargetSize: CGFloat?
    var actionHandler: ItemActionHandler?
    weak var collectionView: NSCollectionView?
    var draggedIndexPaths: Set<IndexPath> = []
    var isDragging = false
    var isProcessingDrop = false
    var pendingDropIndex: Int?
    let dragSession = DragSessionState()

    // Scroll-position cache: folder URL → first visible item index
    static var scrollCache: [URL: Int] = [:]
    var currentFolderURL: URL?

    init(_ parent: FileCollectionView) {
        self.parent = parent
    }

    public func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        parent.layoutItems.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let identifier = NSUserInterfaceItemIdentifier(rawValue: "ThumbnailItem")

        guard indexPath.item < parent.layoutItems.count else {
            return collectionView.makeItem(withIdentifier: identifier, for: indexPath)
        }

        let layoutItem = parent.layoutItems[indexPath.item]
        // swiftlint:disable:next force_cast
        let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath) as! ThumbnailItem
        item.itemStyle = parent.itemStyle

        let cellSize = collectionView.layoutAttributesForItem(at: indexPath)?.frame.size
        let maxDim = max(cellSize?.width ?? 256, cellSize?.height ?? 256)
        item.configure(with: layoutItem.url, maxDimension: maxDim)
        return item
    }

    public func collectionView(_: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        parent.selection.formUnion(indexPaths)
        QuickLookHelpers.reloadPanelIfVisible()
    }

    public func collectionView(_: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        parent.selection.subtract(indexPaths)
        QuickLookHelpers.reloadPanelIfVisible()
    }

    // MARK: - Quick Look Helpers

    var selectedURLs: [URL] {
        parent.selection
            .sorted { $0.item < $1.item }
            .compactMap { idx in
                idx.item < parent.layoutItems.count ? parent.layoutItems[idx.item].url : nil
            }
    }
}

// MARK: - Quick Look DataSource & Delegate

extension Coordinator: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        selectedURLs.count
    }

    public func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let urls = selectedURLs
        guard index < urls.count else { return nil }
        return urls[index] as NSURL
    }

    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.specialKey {
        case .leftArrow?, .upArrow?:
            moveSelection(by: -1, panel: panel)
            return true
        case .rightArrow?, .downArrow?:
            moveSelection(by: 1, panel: panel)
            return true
        default:
            return event.characters == " "
        }
    }

    private func moveSelection(by delta: Int, panel: QLPreviewPanel) {
        guard let collectionView, !parent.layoutItems.isEmpty else { return }
        let current = collectionView.selectionIndexPaths.first?.item ?? 0
        let next = max(0, min(parent.layoutItems.count - 1, current + delta))
        guard next != current else { return }
        let path = IndexPath(item: next, section: 0)
        collectionView.selectionIndexPaths = [path]
        parent.selection = [path]
        collectionView.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        panel.reloadData()
    }
}
