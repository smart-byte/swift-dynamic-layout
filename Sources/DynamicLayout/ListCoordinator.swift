//
//  ListCoordinator.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit
import ImageTools

/// NSTableView data-source / delegate / drag handler backing `FileListView`.
@MainActor
public class ListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var parent: FileListView
    weak var tableView: NSTableView?
    var actionHandler: ItemActionHandler?
    var lastItemIDs: [UUID] = []
    var lastItemsSnapshot: DynamicLayoutItemsSnapshot?
    var draggedRows: IndexSet = []
    var isDragging = false
    let dragSession = DragSessionState()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
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

            // Ask for a larger size than we actually display (24×24) so
            // QLThumbnailGenerator returns a real preview instead of the
            // system file-type icon — the cache later feeds the drag
            // preview from this same entry.
            ImageCache.shared.image(for: item.url, maxDimension: 64) { img in
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

        lastItemIDs = parent.layoutItems.map(\.id)
        lastItemsSnapshot = DynamicLayoutItemsSnapshot(items: parent.layoutItems)
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

    /// Folder URL the host pane is displaying. Read by `NiblessTableView`
    /// to build the background context menu.
    var currentFolderURL: URL? {
        parent.folderURL
    }

    // MARK: - Double-Click

    @objc func handleDoubleClick(_: Any?) {
        guard let url = selectedURLs.first,
              let actionHandler = (tableView as? NiblessTableView)?.actionHandler
        else { return }
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        switch (isDir, cmdHeld) {
        // Finder convention: ⌘-double-click on a directory opens it in a
        // new tab in the current pane, not a new split.
        case (true, true): actionHandler.didRequestOpenInNewTab(url)
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
        _ tableView: NSTableView, draggingSession session: NSDraggingSession,
        willBeginAt _: NSPoint, forRowIndexes rowIndexes: IndexSet
    ) {
        isDragging = true
        draggedRows = rowIndexes

        // List view always uses the .compact drag-image style at source.
        // The destination overrides this in its own validateDrop.
        let style = LayoutMode.list.dragImageStyle
        session.enumerateDraggingItems(
            options: [],
            for: tableView,
            classes: [NSURL.self],
            searchOptions: [:]
        ) { item, _, _ in
            guard let url = item.item as? URL else { return }
            let urlValue = url
            item.imageComponentsProvider = {
                DragImageComposer.compose(for: urlValue, style: style)
            }
        }

        dragSession.begin()
    }

    public func tableView(
        _ tableView: NSTableView, draggingSession _: NSDraggingSession,
        endedAt _: NSPoint, operation _: NSDragOperation
    ) {
        isDragging = false
        draggedRows = []
        (tableView as? NiblessTableView)?.setDropTargetHighlight(false)

        dragSession.end()
    }

    public func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo,
        proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let nibless = tableView as? NiblessTableView

        // ESC pressed during the drag → refuse any drop, regardless of the
        // synthetic mouse-up's landing point.
        if dragSession.isCancelled {
            nibless?.setDropTargetHighlight(false)
            return []
        }

        // Internal reorder: in-pane move semantics with `.above` indicator.
        if info.draggingSource as? NSTableView == tableView {
            if dropOperation == .on {
                tableView.setDropRow(row, dropOperation: .above)
            }
            nibless?.setDropTargetHighlight(false)
            return .move
        }

        // Folder-row drop target: when the cursor is over a directory row,
        // route the drop INTO that subfolder. NSTableView paints the row
        // blue automatically when we keep `.on` with that row index.
        if row >= 0,
           row < parent.layoutItems.count,
           let folderURL = directoryURL(atRow: row),
           FileDropPerformer.proposedOperation(for: info, destinationFolder: folderURL) != []
        {
            tableView.setDropRow(row, dropOperation: .on)
            nibless?.setDropTargetHighlight(false)
            return FileDropPerformer.proposedOperation(
                for: info, destinationFolder: folderURL
            )
        }

        // Whitespace drop into the pane's own folder. -1 + .on suppresses
        // the row indicator, the pane border is the visual cue.
        let op = FileDropPerformer.proposedOperation(
            for: info,
            destinationFolder: parent.folderURL
        )
        tableView.setDropRow(-1, dropOperation: .on)
        nibless?.setDropTargetHighlight(op != [])
        return op
    }

    /// Returns the URL at `row` IFF it points to a directory. Used by
    /// the folder-row drop-target hit test.
    private func directoryURL(atRow row: Int) -> URL? {
        guard row >= 0, row < parent.layoutItems.count else { return nil }
        let url = parent.layoutItems[row].url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true ? url : nil
    }

    public func tableView(
        _ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
        row: Int, dropOperation: NSTableView.DropOperation
    ) -> Bool {
        (tableView as? NiblessTableView)?.setDropTargetHighlight(false)

        // Race-condition guard: validateDrop usually catches the cancel,
        // but if AppKit raced past it, refuse the drop here too. The flag
        // gets reset in the ended hook.
        if dragSession.isCancelled {
            return false
        }

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
            lastItemsSnapshot = DynamicLayoutItemsSnapshot(items: parent.layoutItems)

            tableView.beginUpdates()
            tableView.moveRow(at: draggedRow, to: adjustedTarget)
            tableView.endUpdates()

            return true
        }

        // Folder-row drop: validateDrop set `.on` with that row's index,
        // so the destination is the directory at that row, not the pane's
        // own folder.
        let destinationFolder: URL? = {
            if dropOperation == .on, row >= 0 {
                return directoryURL(atRow: row) ?? parent.folderURL
            }
            return parent.folderURL
        }()
        return FileDropPerformer.perform(info: info, into: destinationFolder)
    }
}
