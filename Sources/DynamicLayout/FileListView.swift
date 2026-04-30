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

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        folderURL: URL? = nil,
        actionHandler: ItemActionHandler? = nil
    ) {
        _layoutItems = layoutItems
        _selection = selection
        self.folderURL = folderURL
        self.actionHandler = actionHandler
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

        // Enable drag & drop reordering
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.every, forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .delete], forLocal: false)

        // Double-click → detail preview
        tableView.doubleAction = #selector(ListCoordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView

        return scrollView
    }

    public func updateNSView(_: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.actionHandler = actionHandler
        // Each body re-render hands us a fresh handler instance — sync it.
        (coordinator.tableView as? NiblessTableView)?.actionHandler = actionHandler

        if coordinator.isDragging { return }

        // Cheap pre-check before the full ID diff: if count is the same
        // AND first/last IDs match, the array hasn't changed (assuming
        // stable IDs, which our pipeline guarantees). Skips the O(N)
        // `map(\.id)` allocation per resize frame at e.g. 1000 items.
        let countChanged = coordinator.lastItemCount != layoutItems.count
        let endpointsChanged = coordinator.lastFirstID != layoutItems.first?.id
            || coordinator.lastLastID != layoutItems.last?.id
        guard countChanged || endpointsChanged else { return }

        let newIDs = layoutItems.map(\.id)
        guard coordinator.lastItemIDs != newIDs else { return }

        let oldIDs = coordinator.lastItemIDs
        let tableView = coordinator.tableView

        if oldIDs.isEmpty || tableView == nil {
            // First load (or no table yet) — a 100-row fade-in looks worse
            // than just appearing. Use a plain reloadData and skip the
            // animation pass.
            coordinator.lastItemIDs = newIDs
            coordinator.lastItemCount = layoutItems.count
            coordinator.lastFirstID = layoutItems.first?.id
            coordinator.lastLastID = layoutItems.last?.id
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
            coordinator.lastItemCount = layoutItems.count
            coordinator.lastFirstID = layoutItems.first?.id
            coordinator.lastLastID = layoutItems.last?.id
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
        coordinator.lastItemCount = layoutItems.count
        coordinator.lastFirstID = layoutItems.first?.id
        coordinator.lastLastID = layoutItems.last?.id
    }

    public func makeCoordinator() -> ListCoordinator {
        ListCoordinator(self)
    }
}
