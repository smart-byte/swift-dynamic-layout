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
    case verticalFlow
    case waterfall
    case horizontalFlow
    case justified
    case horizontalJustified

    public var name: String {
        switch self {
        case .list: "List"
        case .verticalFlow: "Vertical Flow"
        case .waterfall: "Waterfall"
        case .horizontalFlow: "Horizontal Flow"
        case .justified: "Justified"
        case .horizontalJustified: "Horizontal Justified"
        }
    }

    public var icon: String {
        switch self {
        case .list: "list.bullet.rectangle.fill"
        case .verticalFlow: "rectangle.split.1x2.fill"
        case .waterfall: "rectangle.grid.3x2.fill"
        case .horizontalFlow: "rectangle.split.3x1.fill"
        case .justified: "square.grid.2x2.fill"
        case .horizontalJustified: "rectangle.split.2x1.fill"
        }
    }
}

// MARK: - NSCollectionView subclass (bypasses NIB lookup for SPM module classes)

/// NSCollectionView tries to load a NIB when creating new items via class
/// registration, even when the class overrides init(nibName:bundle:).
/// This subclass intercepts `makeItem` to create items programmatically.
class NiblessCollectionView: NSCollectionView {
    private var programmaticClasses: [NSUserInterfaceItemIdentifier: NSCollectionViewItem.Type] = [:]

    func registerProgrammatic(
        _ itemClass: NSCollectionViewItem.Type,
        forItemWithIdentifier identifier: NSUserInterfaceItemIdentifier
    ) {
        programmaticClasses[identifier] = itemClass
    }

    override func makeItem(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        for _: IndexPath
    ) -> NSCollectionViewItem {
        if let itemClass = programmaticClasses[identifier] {
            let item = itemClass.init(nibName: nil, bundle: nil)
            item.identifier = identifier
            return item
        }
        fatalError("Unknown item identifier: \(identifier.rawValue)")
    }

    // MARK: - Custom Drop Indicator

    private lazy var dropIndicatorView: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        v.layer?.cornerRadius = 1.5
        v.isHidden = true
        addSubview(v)
        return v
    }()

    func showDropIndicator(at frame: CGRect) {
        dropIndicatorView.frame = frame
        dropIndicatorView.isHidden = false
    }

    func hideDropIndicator() {
        dropIndicatorView.isHidden = true
    }

    /// Hide the default gap indicator that NSCollectionView adds
    /// for .before drop operations — we draw our own.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        let className = String(describing: type(of: subview))
        if className.contains("Gap") || className.contains("Drop") {
            if subview !== dropIndicatorView {
                subview.isHidden = true
            }
        }
    }
}

// MARK: - FileCollectionView (for verticalFlow, horizontalFlow, justified)

public struct FileCollectionView: NSViewRepresentable {
    @Binding var layoutItems: [DynamicLayoutItem]
    @Binding var selection: Set<IndexPath>
    @Binding var layoutMode: LayoutMode
    @Binding var itemStyle: ItemStyle
    @Binding var itemSpacing: CGFloat
    @Binding var columns: Int
    let folderURL: URL?

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        layoutMode: Binding<LayoutMode>,
        itemStyle: Binding<ItemStyle> = .constant(.photoFrame),
        itemSpacing: Binding<CGFloat>,
        columns: Binding<Int> = .constant(5),
        folderURL: URL? = nil
    ) {
        _layoutItems = layoutItems
        _selection = selection
        _layoutMode = layoutMode
        _itemStyle = itemStyle
        _itemSpacing = itemSpacing
        _columns = columns
        self.folderURL = folderURL
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

        collectionView.registerProgrammatic(
            ThumbnailItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ThumbnailItem")
        )

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
        let folderChanged = coordinator.currentFolderURL != folderURL

        coordinator.parent = self

        // Save scroll position for the current folder before switching
        if itemsChanged, let url = coordinator.currentFolderURL {
            let firstVisible = collectionView.indexPathsForVisibleItems()
                .sorted { $0.item < $1.item }.first?.item ?? 0
            Coordinator.scrollCache[url] = firstVisible
        }
        coordinator.currentFolderURL = folderURL

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
        case .verticalFlow:
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
            layout.targetRowHeight = 200
            return layout

        case .horizontalJustified:
            let layout = HorizontalJustifiedLayout()
            layout.items = items
            layout.sectionInset = insets
            layout.spacing = 4
            layout.targetColumnWidth = 200
            return layout

        case .list:
            let layout = VerticalFlowLayout()
            layout.sectionInset = insets
            layout.items = items
            layout.spacingPercentage = spacing
            return layout
        }
    }

    private func updateLayoutItems(_ layout: NSCollectionViewLayout?, items: [DynamicLayoutItem]) {
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

    private func updateLayoutProperties(_ layout: NSCollectionViewLayout?, spacing: CGFloat, columns: Int) {
        if let layout = layout as? VerticalFlowLayout {
            layout.spacingPercentage = spacing
        } else if let layout = layout as? WaterfallLayout {
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
        item.configure(with: layoutItem.url)
        return item
    }

    public func collectionView(_: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        parent.selection.formUnion(indexPaths)
    }

    public func collectionView(_: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        parent.selection.subtract(indexPaths)
    }
}
