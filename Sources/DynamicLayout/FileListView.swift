//
//  FileListView.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import Quartz
import SwiftUI

/// Finder-style table view wrapping NSTableView.
/// Columns: Name, Date, Size, Kind — sortable by header click.
public struct FileListView: NSViewRepresentable {
    @Binding var layoutItems: [DynamicLayoutItem]
    @Binding var selection: Set<IndexPath>
    let folderURL: URL?
    var actionHandler: ItemActionHandler?
    /// Active column sort, used purely for the column-header arrow
    /// indicator. Items arrive in `layoutItems` already sorted by the
    /// host (FolderContentLoader owns the order). `nil` clears the
    /// header arrow.
    var currentSort: ListSortDescriptor?
    /// Fires when the user clicks a column header. The host is
    /// expected to push this into the data source (so the next
    /// `layoutItems` publish arrives in the new order) and persist it.
    var onSortChange: ((ListSortDescriptor) -> Void)?

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        folderURL: URL? = nil,
        actionHandler: ItemActionHandler? = nil,
        currentSort: ListSortDescriptor? = nil,
        onSortChange: ((ListSortDescriptor) -> Void)? = nil
    ) {
        _layoutItems = layoutItems
        _selection = selection
        self.folderURL = folderURL
        self.actionHandler = actionHandler
        self.currentSort = currentSort
        self.onSortChange = onSortChange
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let tableView = NiblessTableView()
        tableView.quickLookCoordinator = context.coordinator
        context.coordinator.actionHandler = actionHandler
        tableView.actionHandler = actionHandler
        if #available(macOS 11.0, *) {
            tableView.style = .inset
        }
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 8, height: 4)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.width = 300
        nameColumn.minWidth = 150
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        tableView.addTableColumn(nameColumn)

        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "Date Modified"
        dateColumn.width = 150
        dateColumn.minWidth = 100
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "date", ascending: false)
        tableView.addTableColumn(dateColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 80
        sizeColumn.minWidth = 60
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        tableView.addTableColumn(sizeColumn)

        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kindColumn.title = "Kind"
        kindColumn.width = 120
        kindColumn.minWidth = 80
        kindColumn.sortDescriptorPrototype = NSSortDescriptor(key: "kind", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        tableView.addTableColumn(kindColumn)

        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        // Drag & drop: move into sibling subfolder rows, or copy/move
        // files dragged in from outside the pane. Internal in-pane
        // reorder is intentionally disabled — column sort is the only
        // mechanism that determines list order.
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)

        // Double-click → detail preview
        tableView.doubleAction = #selector(ListCoordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        // Set the column-header arrow indicator from the host's
        // current sort. Items themselves come pre-sorted from
        // FolderContentLoader, so we don't reorder anything here.
        if let sort = currentSort {
            tableView.sortDescriptors = [
                NSSortDescriptor(key: sort.key, ascending: sort.ascending),
            ]
        }

        return scrollView
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.actionHandler = actionHandler
        // Each body re-render hands us a fresh handler instance — sync it.
        (coordinator.tableView as? NiblessTableView)?.actionHandler = actionHandler

        syncSelection(with: coordinator)

        if coordinator.isDragging { return }

        syncSortDescriptors(on: coordinator.tableView)

        let itemsSnapshot = DynamicLayoutItemsSnapshot(items: layoutItems)
        guard coordinator.lastItemsSnapshot != itemsSnapshot else { return }

        let newIDs = layoutItems.map(\.id)
        guard coordinator.lastItemIDs != newIDs else { return }

        let oldIDs = coordinator.lastItemIDs
        let tableView = coordinator.tableView

        if oldIDs.isEmpty || tableView == nil {
            // First load (or no table yet) — a 100-row fade-in looks worse
            // than just appearing. Use a plain reloadData and skip the
            // animation pass.
            coordinator.lastItemIDs = newIDs
            coordinator.lastItemsSnapshot = itemsSnapshot
            tableView?.reloadData()
            return
        }

        // Compute removed + inserted indices via UUID set membership.
        // Items that simply moved (same UUID, different index) are left
        // alone — alphabetic sort changes still surface as remove+insert
        // pairs from the diff, which animate fine via .effectFade.
        let newIDSet = Set(newIDs)
        let oldIDSet = Set(oldIDs)
        var removedIndices: [Int] = []
        var insertedIndices: [Int] = []
        for (idx, id) in oldIDs.enumerated() where !newIDSet.contains(id) {
            removedIndices.append(idx)
        }
        for (idx, id) in newIDs.enumerated() where !oldIDSet.contains(id) {
            insertedIndices.append(idx)
        }

        if removedIndices.isEmpty, insertedIndices.isEmpty {
            // Pure reorder of the same set of UUIDs — no add/remove diff
            // to animate. A reloadData would visually flash the whole
            // table; instead update the cached IDs and let
            // `tableViewSelectionDidChange` etc. handle row content.
            coordinator.lastItemIDs = newIDs
            coordinator.lastItemsSnapshot = itemsSnapshot
            tableView?.reloadData()
            return
        }

        if let tableView {
            tableView.beginUpdates()
            tableView.removeRows(at: IndexSet(removedIndices), withAnimation: .effectFade)
            tableView.insertRows(at: IndexSet(insertedIndices), withAnimation: .effectFade)
            tableView.endUpdates()
        }

        coordinator.lastItemIDs = newIDs
        coordinator.lastItemsSnapshot = itemsSnapshot
    }

    /// Syncs the column-header arrow with the host's `currentSort`
    /// without touching item order. The host (FolderContentLoader) is
    /// the source of truth for ordering and pre-sorts `layoutItems`
    /// before they reach this view; here we only mirror the visual
    /// indicator across tab switches and state restores.
    private func syncSortDescriptors(on tableView: NSTableView?) {
        guard let tableView else { return }
        let desired: [NSSortDescriptor] = currentSort.map {
            [NSSortDescriptor(key: $0.key, ascending: $0.ascending)]
        } ?? []
        let existing = tableView.sortDescriptors
        guard existing.count != desired.count
            || existing.first?.key != desired.first?.key
            || existing.first?.ascending != desired.first?.ascending
        else { return }
        tableView.sortDescriptors = desired
    }

    private func syncSelection(with coordinator: ListCoordinator) {
        let validSelection = sanitizedSelection(selection, itemCount: layoutItems.count)
        if validSelection != selection {
            selection = validSelection
        }
        guard let tableView = coordinator.tableView else { return }
        let selectedRows = IndexSet(validSelection.map(\.item))
        if tableView.selectedRowIndexes != selectedRows {
            tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
        }
    }

    public func makeCoordinator() -> ListCoordinator {
        ListCoordinator(self)
    }
}
