// swiftlint:disable file_length

import Quartz
import SwiftUI

// MARK: - CollectionLayoutView (for verticalFlow, horizontalFlow, justified)

public struct CollectionLayoutView: NSViewRepresentable {
    @Binding var layoutItems: [LayoutItemFrame]
    @Binding var selection: Set<IndexPath>
    @Binding var layoutMode: LayoutMode
    @Binding var itemStyle: ItemStyle
    @Binding var itemSpacing: CGFloat
    @Binding var columns: Int
    @Binding var targetSize: CGFloat
    /// Voila-specific hint passed through to the Coordinator for two purposes:
    /// (1) scroll-position cache keyed by folder URL, so the view restores the
    ///     scroll offset when navigating back to a previously visited folder;
    /// (2) background-context-menu target (New Folder, Reveal in Finder) when
    ///     the user right-clicks on empty canvas.
    ///
    /// Long-term this could be replaced by a `backgroundMenuProvider: ((URL) -> NSMenu)?`
    /// callback so the package stays fully file-domain-agnostic. For now it
    /// remains as an optional hint — passing `nil` disables both features gracefully.
    let folderURL: URL?
    var actionHandler: (any ItemActionHandler)?
    /// Called during drag validation to determine the allowed drop operation.
    /// The host app binds `FileDropPerformer.proposedOperation` here so the
    /// package stays free of FileManager knowledge.
    var dropValidator: DropValidator?
    /// Called when a drop is accepted. The host app binds
    /// `FileDropPerformer.perform` here.
    var dropPerformer: DropPerformer?
    /// Resolves a frame ID to a file URL for cell rendering and drag operations.
    /// O(N) lookup in the host's FileLayoutItem array — acceptable because
    /// cell reuse limits call frequency to visible cells only. Profile before
    /// adding a cache here.
    var urlForFrame: (UUID) -> URL?
    /// Synchronous cache lookup — returns `nil` on miss. See `ImageProvider.swift`.
    var syncImageProvider: SyncImageProvider
    /// Async image loader — delivers on the main queue. See `ImageProvider.swift`.
    var asyncImageProvider: ImageProvider
    /// Allows the user to drag a cell within the same collection view
    /// to reorder it. Off by default — most apps (Voila included)
    /// drive item ordering from a sort descriptor or external model
    /// state, where a manual in-pane reorder would conflict with the
    /// authoritative order on the next reload. Cross-pane drags
    /// between two collection views remain unaffected; they go
    /// through the external drop-validator path.
    var allowsInternalReorder: Bool = false

    public init(
        layoutItems: Binding<[LayoutItemFrame]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        layoutMode: Binding<LayoutMode>,
        itemStyle: Binding<ItemStyle> = .constant(.photoFrame),
        itemSpacing: Binding<CGFloat>,
        columns: Binding<Int> = .constant(5),
        targetSize: Binding<CGFloat> = .constant(200),
        folderURL: URL? = nil,
        actionHandler: (any ItemActionHandler)? = nil,
        dropValidator: DropValidator? = nil,
        dropPerformer: DropPerformer? = nil,
        urlForFrame: @escaping (UUID) -> URL?,
        syncImageProvider: @escaping SyncImageProvider,
        asyncImageProvider: @escaping ImageProvider,
        allowsInternalReorder: Bool = false
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
        self.dropValidator = dropValidator
        self.dropPerformer = dropPerformer
        self.urlForFrame = urlForFrame
        self.syncImageProvider = syncImageProvider
        self.asyncImageProvider = asyncImageProvider
        self.allowsInternalReorder = allowsInternalReorder
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
        context.coordinator.dropValidator = dropValidator
        context.coordinator.dropPerformer = dropPerformer
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
        coordinator.dropValidator = dropValidator
        coordinator.dropPerformer = dropPerformer
        coordinator.syncImageProvider = syncImageProvider
        coordinator.asyncImageProvider = asyncImageProvider
        // Keep the collection view's pointer in sync with the latest handler;
        // each body re-render hands us a freshly-allocated handler instance.
        (collectionView as? NiblessCollectionView)?.actionHandler = actionHandler

        // Sanitize the host's selection up-front so out-of-range
        // index paths don't survive a folder change. Pushing it onto
        // the collection view is deferred until AFTER any reloadData
        // — NSCollectionView's `reloadData()` clears
        // `selectionIndexPaths`, so a pre-reload sync would be wiped
        // (regression observed via the pinboard's "Open Source Folder"
        // landing on a hidden / freshly-mounted tab).
        let validSelection = sanitizedSelection(selection, itemCount: layoutItems.count)
        if validSelection != selection {
            selection = validSelection
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

        // Push the validated selection now — after any `reloadData`
        // inside the apply* branches has had a chance to wipe the
        // collection view's own selection state.
        if collectionView.selectionIndexPaths != validSelection {
            collectionView.selectionIndexPaths = validSelection
        }

        // Slider drives photo-frame matte thickness via
        // `scaleReference` on each cell. Push the new value to
        // already-visible cells when the slider moves; new / reused
        // cells pick it up via `itemForRepresentedObjectAt`.
        if targetSizeChanged {
            for item in collectionView.visibleItems() {
                (item as? ThumbnailItem)?.scaleReference = targetSize
            }
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
        scheduleDeferredInvalidate(collectionView)
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
        scheduleDeferredInvalidate(collectionView)
    }

    /// Belt-and-suspenders re-invalidate on the next runloop. Covers
    /// the timing window where `prepare()` runs against transient cv
    /// bounds (zero / mid-tab-swap / right after restart) before the
    /// scroll view has propagated its final size — without this the
    /// layout sometimes lands a 2x2-pixel cache and never recovers
    /// because `shouldInvalidateLayout` won't fire on the bounds
    /// change AppKit silently applies right after layoutSubtree.
    private func scheduleDeferredInvalidate(_ collectionView: NSCollectionView) {
        DispatchQueue.main.async { [weak collectionView] in
            collectionView?.collectionViewLayout?.invalidateLayout()
        }
    }

    private func crossfadeReload(collectionView: NSCollectionView) {
        let folderURL = folderURL
        let layoutItems = layoutItems
        // Capture the host's current selection so we can re-apply it
        // after the deferred `reloadData()` lands. Without this, a
        // host-set selection (e.g. pinboard's reveal landing on a
        // freshly-mounted tab) gets wiped by the reload.
        let pendingSelection = sanitizedSelection(selection, itemCount: layoutItems.count)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            collectionView.animator().alphaValue = 0
        } completionHandler: {
            collectionView.reloadData()
            if collectionView.selectionIndexPaths != pendingSelection {
                collectionView.selectionIndexPaths = pendingSelection
            }
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

    private func applyPropertyChange(collectionView: NSCollectionView, coordinator _: Coordinator) {
        // No FLIP animation here on purpose: spacing / columns /
        // targetSize are slider-driven, and a continuous slider fires
        // dozens of changes per second. Stacking 200ms FLIP animations
        // on each tick reads as stutter — direct invalidation tracks
        // the slider 1:1 instead.
        updateLayoutProperties(collectionView.collectionViewLayout)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.collectionViewLayout?.invalidateLayout()
        CATransaction.commit()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

// MARK: - Coordinator

public class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var parent: CollectionLayoutView

    var lastLayoutMode: LayoutMode?
    var lastItemStyle: ItemStyle?
    var lastItemCount: Int = -1
    var lastItemIDs: [UUID] = []
    var lastItemsSnapshot: DynamicLayoutItemsSnapshot?
    var lastSpacing: CGFloat = -1
    var lastColumns: Int = -1
    var lastTargetSize: CGFloat?
    var actionHandler: (any ItemActionHandler)?
    var dropValidator: DropValidator?
    var dropPerformer: DropPerformer?
    var syncImageProvider: SyncImageProvider
    var asyncImageProvider: ImageProvider
    weak var collectionView: NSCollectionView?
    var draggedIndexPaths: Set<IndexPath> = []
    var isDragging = false
    var isProcessingDrop = false
    var pendingDropIndex: Int?
    let dragSession = DragSessionState()
    /// Source-side cell snapshots captured at `willBeginAt`. Used to
    /// restore the preview when the cursor returns to this collection
    /// view after hovering over a different drop target. Cleared in
    /// `endedAt`.
    var sourceComponentsByURL: [URL: [NSDraggingImageComponent]] = [:]

    // Scroll-position cache: folder URL → first visible item index
    static var scrollCache: [URL: Int] = [:]
    var currentFolderURL: URL?

    init(_ parent: CollectionLayoutView) {
        self.parent = parent
        syncImageProvider = parent.syncImageProvider
        asyncImageProvider = parent.asyncImageProvider
    }

    public func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        parent.layoutItems.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let identifier = NSUserInterfaceItemIdentifier(rawValue: "ThumbnailItem")

        guard indexPath.item < parent.layoutItems.count else {
            return collectionView.makeItem(withIdentifier: identifier, for: indexPath)
        }

        let frame = parent.layoutItems[indexPath.item]
        // swiftlint:disable:next force_cast
        let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath) as! ThumbnailItem
        item.itemStyle = parent.itemStyle

        let cellSize = collectionView.layoutAttributesForItem(at: indexPath)?.frame.size
        let maxDim = max(cellSize?.width ?? 256, cellSize?.height ?? 256)

        // Layout-level scale drives the photo-frame matte thickness
        // so it stays uniform across cells in the same layout. For
        // horizontalFlow the cell height is what's uniform (the
        // toolbar slider is decoupled there), for everything else the
        // toolbar slider's targetSize is the right reference.
        item.scaleReference = parent.layoutMode == .horizontalFlow
            ? cellSize?.height ?? parent.targetSize
            : parent.targetSize

        // Resolve frame ID → URL via the host-injected closure.
        // This is an O(N) lookup in the host's FileLayoutItem array.
        // Acceptable because cell reuse limits call frequency to visible cells.
        if let url = parent.urlForFrame(frame.id) {
            item.configure(
                with: url,
                maxDimension: maxDim,
                syncProvider: syncImageProvider,
                asyncProvider: asyncImageProvider
            )
        }
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
                guard idx.item < parent.layoutItems.count else { return nil }
                let frame = parent.layoutItems[idx.item]
                return parent.urlForFrame(frame.id)
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
