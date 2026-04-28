//
//  FileListView.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import ImageTools
import Quartz
import SwiftUI

/// Finder-style table view wrapping NSTableView.
/// Columns: Name, Date, Size, Kind — sortable by header click.
public struct FileListView: NSViewRepresentable {
    @Binding var layoutItems: [DynamicLayoutItem]
    @Binding var selection: Set<IndexPath>
    var actionHandler: ItemActionHandler?

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        actionHandler: ItemActionHandler? = nil
    ) {
        _layoutItems = layoutItems
        _selection = selection
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

        let itemsChanged = coordinator.lastItemIDs != layoutItems.map(\.id)
        if itemsChanged {
            coordinator.lastItemIDs = layoutItems.map(\.id)
            coordinator.tableView?.reloadData()
        }
    }

    public func makeCoordinator() -> ListCoordinator {
        ListCoordinator(self)
    }
}

// MARK: - Coordinator

@MainActor
public class ListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: FileListView
    weak var tableView: NSTableView?
    var actionHandler: ItemActionHandler?
    var lastItemIDs: [UUID] = []
    var draggedRows: IndexSet = []
    var isDragging = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    init(_ parent: FileListView) {
        self.parent = parent
    }

    // MARK: - DataSource

    public func numberOfRows(in _: NSTableView) -> Int {
        parent.layoutItems.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < parent.layoutItems.count, let columnID = tableColumn?.identifier else { return nil }
        let item = parent.layoutItems[row]

        let cellID = NSUserInterfaceItemIdentifier("Cell_\(columnID.rawValue)")

        switch columnID.rawValue {
        case "name":
            let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView ?? makeNameCell(identifier: cellID)
            cell.textField?.stringValue = item.url.lastPathComponent
            cell.imageView?.image = nil

            // Load thumbnail async
            ImageCache.shared.image(for: item.url, maxDimension: 48) { img in
                DispatchQueue.main.async {
                    cell.imageView?.image = img
                }
            }
            return cell

        case "date":
            let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView ?? makeTextCell(identifier: cellID)
            cell.textField?.alignment = .right
            if let date = item.modificationDate {
                cell.textField?.stringValue = Self.dateFormatter.string(from: date)
            } else {
                cell.textField?.stringValue = "—"
            }
            return cell

        case "size":
            let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView ?? makeTextCell(identifier: cellID)
            cell.textField?.alignment = .right
            if item.fileSize > 0 {
                cell.textField?.stringValue = Self.sizeFormatter.string(fromByteCount: item.fileSize)
            } else {
                cell.textField?.stringValue = "—"
            }
            return cell

        case "kind":
            let cell = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView ?? makeTextCell(identifier: cellID)
            cell.textField?.alignment = .right
            cell.textField?.stringValue = item.fileKind
            return cell

        default:
            return nil
        }
    }

    // MARK: - Sorting

    public func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first else { return }

        switch descriptor.key {
        case "name":
            let ascending = descriptor.ascending
            parent.layoutItems.sort {
                ascending
                    ? $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
                    : $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedDescending
            }
        case "date":
            let ascending = descriptor.ascending
            parent.layoutItems.sort {
                let d0 = $0.modificationDate ?? .distantPast
                let d1 = $1.modificationDate ?? .distantPast
                return ascending ? d0 < d1 : d0 > d1
            }
        case "size":
            let ascending = descriptor.ascending
            parent.layoutItems.sort {
                ascending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            }
        case "kind":
            let ascending = descriptor.ascending
            parent.layoutItems.sort {
                ascending
                    ? $0.fileKind.localizedCaseInsensitiveCompare($1.fileKind) == .orderedAscending
                    : $0.fileKind.localizedCaseInsensitiveCompare($1.fileKind) == .orderedDescending
            }
        default:
            break
        }

        tableView.reloadData()
    }

    // MARK: - Selection

    public func tableViewSelectionDidChange(_: Notification) {
        guard let tableView else { return }
        let selectedRows = tableView.selectedRowIndexes
        parent.selection = Set(selectedRows.map { IndexPath(item: $0, section: 0) })
        QuickLookHelpers.reloadPanelIfVisible()
    }

    // MARK: - Quick Look Helpers

    var selectedURLs: [URL] {
        guard let tableView else { return [] }
        return tableView.selectedRowIndexes.sorted().compactMap { row in
            row < parent.layoutItems.count ? parent.layoutItems[row].url : nil
        }
    }

    // MARK: - Double-Click

    @objc func handleDoubleClick(_: Any?) {
        guard let url = selectedURLs.first,
              let actionHandler = (tableView as? NiblessTableView)?.actionHandler
        else { return }
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        switch (isDir, cmdHeld) {
        case (true, true): actionHandler.didRequestOpenInNewPane(url)
        case (true, false): actionHandler.didRequestNavigate(into: url)
        case (false, _): actionHandler.didRequestOpenFile(url)
        }
    }

    // MARK: - Drag

    public func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < parent.layoutItems.count else { return nil }
        return parent.layoutItems[row].url as NSURL
    }

    public func tableView(
        _: NSTableView, draggingSession _: NSDraggingSession,
        willBeginAt _: NSPoint, forRowIndexes rowIndexes: IndexSet
    ) {
        isDragging = true
        draggedRows = rowIndexes
    }

    public func tableView(
        _: NSTableView, draggingSession _: NSDraggingSession,
        endedAt _: NSPoint, operation _: NSDragOperation
    ) {
        isDragging = false
        draggedRows = []
    }

    public func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo,
        proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        if info.draggingSource as? NSTableView == tableView {
            return .move
        }
        return .copy
    }

    public func tableView(
        _ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
        row: Int, dropOperation _: NSTableView.DropOperation
    ) -> Bool {
        let isInternal = info.draggingSource as? NSTableView == tableView

        if isInternal, let draggedRow = draggedRows.first {
            let targetRow = min(row, parent.layoutItems.count)
            let adjustedTarget: Int = if targetRow > draggedRow {
                min(targetRow - 1, parent.layoutItems.count - 1)
            } else {
                targetRow
            }
            guard adjustedTarget != draggedRow else { return false }

            let movedItem = parent.layoutItems.remove(at: draggedRow)
            parent.layoutItems.insert(movedItem, at: min(adjustedTarget, parent.layoutItems.count))

            lastItemIDs = parent.layoutItems.map(\.id)

            tableView.beginUpdates()
            tableView.moveRow(at: draggedRow, to: adjustedTarget)
            tableView.endUpdates()

            return true
        }

        // External drop — insert from Finder
        let pasteboard = info.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first
        else {
            return false
        }

        let targetRow = min(row, parent.layoutItems.count)
        parent.layoutItems.insert(
            DynamicLayoutItem(url: url, size: CGSize(width: 100, height: 100)),
            at: targetRow
        )
        lastItemIDs = parent.layoutItems.map(\.id)
        tableView.insertRows(at: IndexSet(integer: targetRow), withAnimation: .slideDown)

        return true
    }

    // MARK: - Cell Factories

    private func makeNameCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(imageView)
        cell.imageView = imageView

        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
