//
//  ItemActionHandler.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Foundation

/// Callback protocol for item actions handled by the app layer. Calls
/// always come from AppKit views on the main thread.
@MainActor
public protocol ItemActionHandler: AnyObject {
    /// Plain double-click on a file. Convention: open in default app.
    func didRequestOpenFile(_ url: URL)

    /// Plain double-click on a directory. Convention: navigate in place.
    func didRequestNavigate(into url: URL)

    /// Cmd-double-click on a directory. Convention: open in a new tab.
    func didRequestOpenInNewTab(_ url: URL)

    /// Context-menu action on a directory: open in a new pane.
    func didRequestOpenInNewPane(_ url: URL)

    /// Context-menu action on a directory: open in a new app window.
    func didRequestOpenInNewWindow(_ url: URL)

    /// Right-click context menu action. Opens the in-app preview window.
    func didRequestDetailPreview(for urls: [URL])

    /// Copy the absolute file paths of the selection to the general
    /// pasteboard. Host picks the pasteboard format so the package stays
    /// platform-agnostic.
    func didRequestCopyPath(_ urls: [URL])

    /// Move the selection to the user's Trash. Host does the file-system
    /// work and decides how to surface failures.
    func didRequestMoveToTrash(_ urls: [URL])

    /// Create a new folder inside the pane's current directory.
    func didRequestNewFolder(in folderURL: URL)

    /// Reveal the *pane's* folder in Finder. Distinct from the item-level
    /// reveal wired inline in `ItemContextMenuBuilder`, which takes a
    /// `[URL]` of items; this one targets the pane's own location.
    func didRequestRevealFolderInFinder(_ folderURL: URL)

    /// Rename `url` to `newName` (last path component only — host
    /// keeps the parent directory). Fired by inline cell editing
    /// (Finder slow-second-click or Return on a single-selected
    /// cell) and by the context menu's "Rename" entry. Has a
    /// default no-op so apps that haven't migrated to v1.2 keep
    /// compiling unchanged.
    func didRequestRename(_ url: URL, to newName: String)
}

public extension ItemActionHandler {
    /// Default no-op preserves source compatibility for callers
    /// upgrading from <1.2 — apps that don't wire rename simply get
    /// a no-effect cell edit.
    func didRequestRename(_: URL, to _: String) {}
}
