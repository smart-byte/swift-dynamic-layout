//
//  NiblessTableView.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Quartz

/// NSTableView subclass with Quick Look (Space), context menu, and double-click support.
class NiblessTableView: NSTableView {
    weak var quickLookCoordinator: ListCoordinator?
    var actionHandler: ItemActionHandler?

    // MARK: - Quick Look

    override func keyDown(with event: NSEvent) {
        if event.characters == " " {
            QuickLookHelpers.togglePanel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookCoordinator
        panel.delegate = quickLookCoordinator
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)

        // Background click — clickedRow is -1 when the cursor is below the
        // last row or in the empty area of an otherwise empty table. Show
        // the pane-level menu instead of the item menu.
        if clickedRow < 0 {
            return backgroundMenu()
        }

        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }

        let urls = selectedURLs
        guard !urls.isEmpty else { return nil }

        return ItemContextMenuBuilder.menu(
            for: urls,
            quickLookToggle: { QuickLookHelpers.togglePanel() },
            detailPreview: { [weak self] urls in self?.actionHandler?.didRequestDetailPreview(for: urls) },
            openInNewTab: { [weak self] url in self?.actionHandler?.didRequestOpenInNewTab(url) },
            openInNewWindow: { [weak self] url in self?.actionHandler?.didRequestOpenInNewWindow(url) },
            openInNewPane: { [weak self] url in self?.actionHandler?.didRequestOpenInNewPane(url) },
            copyPath: { [weak self] urls in self?.actionHandler?.didRequestCopyPath(urls) },
            moveToTrash: { [weak self] urls in self?.actionHandler?.didRequestMoveToTrash(urls) }
        )
    }

    private func backgroundMenu() -> NSMenu? {
        guard let folderURL = quickLookCoordinator?.currentFolderURL else { return nil }
        return BackgroundContextMenuBuilder.menu(
            forFolder: folderURL,
            newFolder: { [weak self] in self?.actionHandler?.didRequestNewFolder(in: folderURL) },
            revealInFinder: { [weak self] in self?.actionHandler?.didRequestRevealFolderInFinder(folderURL) }
        )
    }

    // MARK: - Helpers

    private var selectedURLs: [URL] {
        quickLookCoordinator?.selectedURLs ?? []
    }

    // MARK: - Pane-Level Drop Target Highlight

    /// Mirror of `NiblessCollectionView.setDropTargetHighlight`. Used while
    /// a Finder / cross-pane drag hovers over this list pane's whitespace.
    /// Folder-row highlights come from `setDropRow(_:dropOperation:.on)` —
    /// NSTableView paints those automatically.
    func setDropTargetHighlight(_ highlighted: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.wantsLayer = true
        let layer = scrollView.layer
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = highlighted ? 3 : 0
        layer?.cornerRadius = highlighted ? 6 : 0
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        setDropTargetHighlight(false)
    }
}
