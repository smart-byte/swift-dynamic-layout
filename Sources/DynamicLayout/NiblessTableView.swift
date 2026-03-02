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
    weak var actionHandler: ItemActionHandler?

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

        if clickedRow >= 0, !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }

        let urls = selectedURLs
        guard !urls.isEmpty else { return nil }

        return ItemContextMenuBuilder.menu(
            for: urls,
            quickLookToggle: { QuickLookHelpers.togglePanel() },
            detailPreview: { [weak self] urls in self?.actionHandler?.didRequestDetailPreview(for: urls) }
        )
    }

    // MARK: - Helpers

    private var selectedURLs: [URL] {
        quickLookCoordinator?.selectedURLs ?? []
    }
}
