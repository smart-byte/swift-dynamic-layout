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
        collectionView.actionHandler = actionHandler

        collectionView.registerProgrammatic(
            ThumbnailItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ThumbnailItem")
        )

        let layout = createLayout(for: layoutMode, items: layoutItems, spacing: itemSpacing, columns: columns, targetSize: targetSize)
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

        let itemsChanged = coordinator.lastItemCount != layoutItems.count ||
            coordinator.lastItemIDs != layoutItems.map(\.id)
        let layoutChanged = coordinator.lastLayoutMode != layoutMode
        let spacingChanged = coordinator.lastSpacing != itemSpacing
        let columnsChanged = coordinator.lastColumns != columns
        let targetSizeChanged = coordinator.lastTargetSize != targetSize
        let folderChanged = coordinator.currentFolderURL != folderURL

        coordinator.parent = self
        coordinator.actionHandler = actionHandler

        // Save scroll position for the current folder before switching
        if itemsChanged, let url = coordinator.currentFolderURL {
            let firstVisible = collectionView.indexPathsForVisibleItems()
                .sorted { $0.item < $1.item }.first?.item ?? 0
            Coordinator.scrollCache[url] = firstVisible
        }
        coordinator.currentFolderURL = folderURL

        if layoutChanged {
            let newLayout = createLayout(for: layoutMode, items: layoutItems, spacing: itemSpacing, columns: columns, targetSize: targetSize)
            coordinator.lastLayoutMode = layoutMode
            coordinator.lastItemCount = layoutItems.count
            coordinator.lastItemIDs = layoutItems.map(\.id)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                collectionView.animator().alphaValue = 0
            } completionHandler: {
                collectionView.collectionViewLayout = newLayout
                collectionView.reloadData()
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    collectionView.animator().alphaValue = 1
                }
            }
        } else if itemsChanged {
            coordinator.lastItemCount = layoutItems.count
            coordinator.lastItemIDs = layoutItems.map(\.id)
            updateLayoutItems(collectionView.collectionViewLayout, items: layoutItems)
            collectionView.reloadData()

            // Restore scroll position when returning to a folder
            if folderChanged, let url = folderURL,
               let savedIndex = Coordinator.scrollCache[url],
               savedIndex > 0, savedIndex < layoutItems.count
            {
                DispatchQueue.main.async {
                    let ip = IndexPath(item: savedIndex, section: 0)
                    collectionView.scrollToItems(at: [ip], scrollPosition: [.top, .left])
                }
            }
        } else if spacingChanged || columnsChanged || targetSizeChanged {
            updateLayoutProperties(collectionView.collectionViewLayout, spacing: itemSpacing, columns: columns, targetSize: targetSize)
            collectionView.collectionViewLayout?.invalidateLayout()
        }

        coordinator.lastSpacing = itemSpacing
        coordinator.lastColumns = columns
        coordinator.lastTargetSize = targetSize

        if coordinator.lastItemStyle != itemStyle {
            coordinator.lastItemStyle = itemStyle
            collectionView.reloadData()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Layout Factory

    private func createLayout(
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

    private func updateLayoutItems(_ layout: NSCollectionViewLayout?, items: [DynamicLayoutItem]) {
        (layout as? LayoutItemsProvider)?.setItems(items)
    }

    private func updateLayoutProperties(_ layout: NSCollectionViewLayout?, spacing: CGFloat, columns: Int, targetSize: CGFloat = 200) {
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

// MARK: - Coordinator

public class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var parent: FileCollectionView

    var lastLayoutMode: LayoutMode?
    var lastItemStyle: ItemStyle?
    var lastItemCount: Int = -1
    var lastItemIDs: [UUID] = []
    var lastSpacing: CGFloat = -1
    var lastColumns: Int = -1
    var lastTargetSize: CGFloat?
    var actionHandler: ItemActionHandler?
    var draggedIndexPaths: Set<IndexPath> = []
    var isDragging = false
    var isProcessingDrop = false
    var pendingDropIndex: Int?

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

    public func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.characters == " " {
            return true
        }
        return false
    }
}
