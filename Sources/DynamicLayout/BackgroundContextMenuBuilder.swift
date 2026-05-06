//
//  BackgroundContextMenuBuilder.swift
//
//
//  Created by Mario Heubach on 29.04.26.
//

import AppKit

/// Builds the context menu shown when the user right-clicks the empty
/// background of a pane (no item under the cursor). The items operate on
/// the pane's *current folder*, not on file selection.
///
/// The `forFolder` URL is part of the signature even though existing
/// closures already capture it, so future entries (Sort By, View Options,
/// Open in Terminal) can read folder context without forcing every call
/// site to grow new closures.
@MainActor
public enum BackgroundContextMenuBuilder {
    public static func menu(
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
