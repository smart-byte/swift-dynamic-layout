//
//  QuickLookHelpers.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Quartz

/// Shared Quick Look utilities used by both collection and list views.
enum QuickLookHelpers {
    /// Toggle QL panel visibility.
    static func togglePanel() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           QLPreviewPanel.shared().isVisible
        {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    /// Reload QL panel data if currently visible.
    static func reloadPanelIfVisible() {
        if QLPreviewPanel.sharedPreviewPanelExists(),
           QLPreviewPanel.shared().isVisible
        {
            QLPreviewPanel.shared().reloadData()
        }
    }
}
