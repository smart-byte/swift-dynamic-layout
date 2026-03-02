//
//  ListCoordinator+QuickLook.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Quartz

// MARK: - Quick Look DataSource & Delegate

extension ListCoordinator: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
        selectedURLs.count
    }

    public func previewPanel(_: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        let urls = selectedURLs
        guard index < urls.count else { return nil }
        return urls[index] as NSURL
    }

    public func previewPanel(_: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        if event.type == .keyDown, event.characters == " " {
            return true
        }
        return false
    }
}
