//
//  NiblessTableViewCoordinating.swift
//
//
//  Created by Mario Heubach on 06.05.26.
//

import Quartz

/// Coordinator protocol consumed by `NiblessTableView` for Quick Look and context
/// menu functionality. Defined here so the package-level table view doesn't depend
/// on the concrete `ListCoordinator` type, which lives in the app target.
@MainActor
public protocol NiblessTableViewCoordinating: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// The URLs currently selected in the table. Used to populate the
    /// Quick Look panel and item context menus.
    var selectedURLs: [URL] { get }

    /// The folder URL the host pane is currently displaying.
    /// Used by the background context menu to build folder-level actions.
    var currentFolderURL: URL? { get }
}
