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
    /// Cheap-diff endpoints used by `FileListView.updateNSView` to skip
    /// the full `layoutItems.map(\.id)` allocation when nothing changed.
    var lastItemCount: Int = 0
    var lastFirstID: UUID?
    var lastLastID: UUID?
    var draggedRows: IndexSet = []
    var isDragging = false
    var dragKeyMonitor: Any?
    var dragCancelled = false

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

        // AppKit's NSDraggingSession does not honour ESC out of the box for
        // NSCollectionView/NSTableView sources. Install a local key monitor
        // that swallows ESC during the drag and triggers a cancel with the
        // standard bounce-back animation.
        dragCancelled = false
        dragKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // 53 = ESC
            guard let self else { return event }
            dragCancelled = true
            cancelActiveDrag()
            return nil // swallow ESC
        }
    }

    public func tableView(
        _: NSTableView, draggingSession _: NSDraggingSession,
        endedAt _: NSPoint, operation _: NSDragOperation
    ) {
        isDragging = false
        draggedRows = []

        if let monitor = dragKeyMonitor {
            NSEvent.removeMonitor(monitor)
            dragKeyMonitor = nil
        }
        dragCancelled = false
    }

    public func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo,
        proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        // ESC pressed during the drag → refuse any drop, regardless of the
        // synthetic mouse-up's landing point.
        if dragCancelled {
            return []
        }

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
        // Race-condition guard: validateDrop usually catches the cancel,
        // but if AppKit raced past it, refuse the drop here too. The flag
        // gets reset in the ended hook.
        if dragCancelled {
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

    // MARK: - Cancel Active Drag

    /// Synthesizes a mouse-up event far off-screen so the active dragging
    /// session ends as cancelled (no valid drop target). NSDraggingSession
    /// picks up the event from the queue and runs its bounce-back animation
    /// thanks to `animatesToStartingPositionsOnCancelOrFail = true`.
    private func cancelActiveDrag() {
        let offScreen = NSPoint(x: -10000, y: -10000)
        if let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: offScreen,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) {
            NSApp.postEvent(up, atStart: true)
        }
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
