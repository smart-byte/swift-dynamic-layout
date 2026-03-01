//
//  FileCollectionView.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import SwiftUI

// MARK: - Item Style

/// Visual presentation style for collection view items.
public enum ItemStyle: String, CaseIterable, Hashable {
    case photoFrame
    case contactSheet
    case borderless

    public var name: String {
        switch self {
        case .photoFrame: "Photo Frame"
        case .contactSheet: "Contact Sheet"
        case .borderless: "Borderless"
        }
    }

    public var icon: String {
        switch self {
        case .photoFrame: "photo.on.rectangle"
        case .contactSheet: "rectangle.grid.2x2"
        case .borderless: "rectangle"
        }
    }
}

// MARK: - Layout Mode

/// Single enum for all layout modes. Moodboard is NOT a layout mode —
/// it's a separate system (Phase 4).
public enum LayoutMode: String, CaseIterable, Hashable {
    case list
    case waterfall
    case horizontalFlow
    case justified

    public var name: String {
        switch self {
        case .list: "List"
        case .waterfall: "Waterfall"
        case .horizontalFlow: "Horizontal Flow"
        case .justified: "Justified"
        }
    }

    public var icon: String {
        switch self {
        case .list: "list.bullet.rectangle.fill"
        case .waterfall: "rectangle.grid.3x2.fill"
        case .horizontalFlow: "rectangle.split.3x1.fill"
        case .justified: "square.grid.2x2.fill"
        }
    }
}

// MARK: - FileCollectionView (for waterfall, horizontalFlow, justified)

public struct FileCollectionView: NSViewRepresentable {
    @Binding var layoutItems: [DynamicLayoutItem]
    @Binding var selection: Set<IndexPath>
    @Binding var layoutMode: LayoutMode
    @Binding var itemStyle: ItemStyle
    @Binding var itemSpacing: CGFloat
    @Binding var columns: Int

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        layoutMode: Binding<LayoutMode>,
        itemStyle: Binding<ItemStyle> = .constant(.photoFrame),
        itemSpacing: Binding<CGFloat>,
        columns: Binding<Int> = .constant(5)
    ) {
        _layoutItems = layoutItems
        _selection = selection
        _layoutMode = layoutMode
        _itemStyle = itemStyle
        _itemSpacing = itemSpacing
        _columns = columns
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let collectionView = NSCollectionView()
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator

        // NOTE: Do NOT register classes with NSCollectionView.register(_:forItemWithIdentifier:)
        // When items are in a separate SPM module, NSCollectionView tries to load a NIB from the
        // main bundle and crashes. Items are created directly in the data source instead.

        let layout = createLayout(for: layoutMode, items: layoutItems, spacing: itemSpacing, columns: columns)
        collectionView.collectionViewLayout = layout

        collectionView.selectionIndexPaths = selection

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let collectionView = nsView.documentView as? NSCollectionView else { return }

        let coordinator = context.coordinator
        let itemsChanged = coordinator.lastItemCount != layoutItems.count ||
            coordinator.lastItemIDs != layoutItems.map(\.id)
        let layoutChanged = coordinator.lastLayoutMode != layoutMode
        let spacingChanged = coordinator.lastSpacing != itemSpacing
        let columnsChanged = coordinator.lastColumns != columns

        coordinator.parent = self

        if layoutChanged {
            let newLayout = createLayout(for: layoutMode, items: layoutItems, spacing: itemSpacing, columns: columns)
            coordinator.lastLayoutMode = layoutMode

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                collectionView.animator().collectionViewLayout = newLayout
            }

            if itemsChanged || layoutChanged {
                coordinator.lastItemCount = layoutItems.count
                coordinator.lastItemIDs = layoutItems.map(\.id)
                collectionView.reloadData()
            }
        } else if itemsChanged {
            coordinator.lastItemCount = layoutItems.count
            coordinator.lastItemIDs = layoutItems.map(\.id)
            updateLayoutItems(collectionView.collectionViewLayout, items: layoutItems)
            collectionView.reloadData()
        } else if spacingChanged || columnsChanged {
            updateLayoutProperties(collectionView.collectionViewLayout, spacing: itemSpacing, columns: columns)
            collectionView.collectionViewLayout?.invalidateLayout()
        }

        coordinator.lastSpacing = itemSpacing
        coordinator.lastColumns = columns

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
        columns: Int
    ) -> NSCollectionViewLayout {
        let insets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        switch mode {
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
            layout.targetRowHeight = 200
            return layout

        case .list:
            // List mode is handled by FileListView, not FileCollectionView.
            // Return a simple fallback layout in case this is reached.
            let layout = WaterfallLayout()
            layout.sectionInset = insets
            layout.items = items
            layout.columns = columns
            layout.spacingPercentage = spacing
            return layout
        }
    }

    private func updateLayoutItems(_ layout: NSCollectionViewLayout?, items: [DynamicLayoutItem]) {
        if let layout = layout as? WaterfallLayout {
            layout.items = items
        } else if let layout = layout as? HorizontalFlowLayout {
            layout.items = items
        } else if let layout = layout as? JustifiedLayout {
            layout.items = items
        }
    }

    private func updateLayoutProperties(_ layout: NSCollectionViewLayout?, spacing: CGFloat, columns: Int) {
        if let layout = layout as? WaterfallLayout {
            layout.spacingPercentage = spacing
            layout.columns = columns
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

    init(_ parent: FileCollectionView) {
        self.parent = parent
    }

    public func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        parent.layoutItems.count
    }

    public func collectionView(_: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        guard indexPath.item < parent.layoutItems.count else {
            return ThumbnailItem(nibName: nil, bundle: nil)
        }

        let layoutItem = parent.layoutItems[indexPath.item]
        let item = ThumbnailItem(nibName: nil, bundle: nil)
        item.itemStyle = parent.itemStyle
        item.configure(with: layoutItem.url)
        return item
    }

    public func collectionView(_: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        parent.selection.formUnion(indexPaths)
    }

    public func collectionView(_: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        parent.selection.subtract(indexPaths)
    }

    // MARK: - Drag & Drop

    public func collectionView(_: NSCollectionView, canDragItemsAt _: Set<IndexPath>, with _: NSEvent) -> Bool {
        true
    }

    public func collectionView(_: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        guard indexPath.item < parent.layoutItems.count else { return nil }
        let url = parent.layoutItems[indexPath.item].url

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        pasteboardItem.setString(url.lastPathComponent, forType: .string)
        return pasteboardItem
    }

    public func collectionView(_: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt _: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        let urls = indexPaths.compactMap { indexPath -> URL? in
            guard indexPath.item < parent.layoutItems.count else { return nil }
            return parent.layoutItems[indexPath.item].url
        }
        session.draggingPasteboard.writeObjects(urls as [NSPasteboardWriting])
        session.draggingFormation = .default
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // swiftlint:disable:next line_length
    public func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath _: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        proposedDropOperation.pointee = .on

        if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
            return .copy
        } else if info.draggingSource as? NSCollectionView == collectionView {
            return .move
        } else {
            return .generic
        }
    }

    // swiftlint:disable:next line_length
    public func collectionView(_: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, index: Int, dropOperation _: NSCollectionView.DropOperation) -> Bool {
        let pasteboard = draggingInfo.draggingPasteboard

        guard let itemIndexUrl = pasteboard.data(forType: .fileURL),
              let itemUrl = URL(dataRepresentation: itemIndexUrl, relativeTo: nil)
        else {
            return false
        }

        guard let itemIndex = parent.layoutItems.firstIndex(where: { $0.url == itemUrl }) else {
            let targetIndex = min(index, parent.layoutItems.count)
            parent.layoutItems.insert(
                DynamicLayoutItem(url: itemUrl, size: CGSize(width: 100, height: 100)),
                at: targetIndex
            )
            return true
        }

        let item = parent.layoutItems.remove(at: itemIndex)
        let targetIndex = min(index, parent.layoutItems.count)
        parent.layoutItems.insert(item, at: targetIndex)

        return true
    }
}

extension Coordinator: NSPasteboardItemDataProvider {
    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .fileURL, let url = item.string(forType: .fileURL) {
            pasteboard?.setString(url, forType: .fileURL)
        }
    }
}
