//
//  BackgroundContextMenuBuilder.swift
//
//
//  Created by Mario Heubach on 29.04.26.
//

import AppKit

/// Builds the context menu shown when the user right-clicks the empty
/// background of a pane (no item under the cursor). Mirrors SwiftUI's
/// `.contextMenu(forSelectionType:)` empty-selection branch — the items
/// here operate on the pane's *current folder*, not on file selection.
///
/// The `forFolder` URL is currently unused inside the builder (the
/// closures already know what to do), but is part of the signature so
/// future entries (Sort By, View Options, Open in Terminal) can read
/// folder context without forcing every call site to grow new closures.
@MainActor
enum BackgroundContextMenuBuilder {
    static func menu(
        forFolder _: URL,
        newFolder: (() -> Void)? = nil,
        revealInFinder: (() -> Void)? = nil
    ) -> NSMenu {
        let menu = NSMenu()

        // New Folder — keyEquivalent is decorative here; the real binding
        // (⇧⌘N) belongs to a future File-menu entry. AppKit still renders
        // the modifier glyphs in the contextual menu when set.
        let newFolderItem = NSMenuItem(title: "New Folder", action: nil, keyEquivalent: "N")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        newFolderItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        if let newFolder {
            let target = MenuActionTarget { newFolder() }
            newFolderItem.target = target
            newFolderItem.action = #selector(MenuActionTarget.invokeAction)
            target.retainOn(newFolderItem)
        } else {
            newFolderItem.isEnabled = false
        }
        menu.addItem(newFolderItem)

        menu.addItem(.separator())

        // Reveal in Finder — opens Finder with the pane's folder selected.
        let revealItem = NSMenuItem(title: "Reveal in Finder", action: nil, keyEquivalent: "")
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        if let revealInFinder {
            let target = MenuActionTarget { revealInFinder() }
            revealItem.target = target
            revealItem.action = #selector(MenuActionTarget.invokeAction)
            target.retainOn(revealItem)
        } else {
            revealItem.isEnabled = false
        }
        menu.addItem(revealItem)

        return menu
    }
}

// MARK: - Closure-based menu action target

/// Retains an action closure for an NSMenuItem via associated objects.
/// Mirrors the helper in `ItemContextMenuBuilder.swift`; kept file-private
/// here so the two builders stay independently auditable.
private class MenuActionTarget: NSObject {
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invokeAction() {
        action()
    }

    /// Retain self on the menu item so the target stays alive.
    func retainOn(_ item: NSMenuItem) {
        objc_setAssociatedObject(item, Unmanaged.passUnretained(self).toOpaque(), self, .OBJC_ASSOCIATION_RETAIN)
    }
}
