//
//  ItemActionHandler.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Foundation

/// Callback protocol for item actions that need to be handled by the app
/// layer. Calls always come from AppKit views on the main thread.
///
/// The collection/list views differentiate file vs. directory and forward
/// the right action — the app layer decides what each action means
/// (which window to open, navigate in place, NSWorkspace, etc.).
@MainActor
public protocol ItemActionHandler: AnyObject {
    /// Plain double-click on a file. Convention: open in default app.
    func didRequestOpenFile(_ url: URL)

    /// Plain double-click on a directory. Convention: navigate the current
    /// view into the directory (Finder-style in-place navigation).
    func didRequestNavigate(into url: URL)

    /// Cmd-double-click on a directory. Convention: open in a new pane
    /// alongside the current one.
    func didRequestOpenInNewPane(_ url: URL)

    /// Context-menu action on a directory. Convention: open in a new app
    /// window.
    func didRequestOpenInNewWindow(_ url: URL)

    /// Right-click context menu action. Opens the in-app preview window —
    /// the same one Quick Look would replace if the user prefers system Quick Look.
    func didRequestDetailPreview(for urls: [URL])

    /// Context-menu action: copy the absolute file paths of the selection
    /// to the general pasteboard. The host decides the pasteboard format
    /// so the package stays platform-agnostic.
    func didRequestCopyPath(_ urls: [URL])

    /// Context-menu action: move the selection to the user's Trash. The
    /// host performs the actual file-system work and decides how to log
    /// or surface failures.
    func didRequestMoveToTrash(_ urls: [URL])
}
