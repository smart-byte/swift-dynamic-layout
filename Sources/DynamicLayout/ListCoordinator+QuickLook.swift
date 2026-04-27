//
//  ListCoordinator+QuickLook.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Quartz

// MARK: - Quick Look DataSource & Delegate

extension ListCoordinator: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        selectedURLs.count
    }

    public func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let urls = selectedURLs
        guard index < urls.count else { return nil }
        return urls[index] as NSURL
    }

    public func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        switch event.specialKey {
        case .upArrow?:
            moveSelection(by: -1, panel: panel)
            return true
        case .downArrow?:
            moveSelection(by: 1, panel: panel)
            return true
        default:
            // Keep the panel open on space (existing behavior).
            return event.characters == " "
        }
    }

    private func moveSelection(by delta: Int, panel: QLPreviewPanel) {
        guard let tableView, !parent.layoutItems.isEmpty else { return }
        let current = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        let next = max(0, min(parent.layoutItems.count - 1, current + delta))
        guard next != current else { return }
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
        panel.reloadData()
    }
}
