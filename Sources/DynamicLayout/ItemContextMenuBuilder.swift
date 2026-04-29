//
//  ItemContextMenuBuilder.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import AppKit

/// Builds a shared context menu for file items in both collection and list views.
@MainActor
enum ItemContextMenuBuilder {
    static func menu(
        for urls: [URL],
        quickLookToggle: @escaping () -> Void,
        detailPreview: @escaping ([URL]) -> Void,
        openInNewWindow: ((URL) -> Void)? = nil,
        copyPath: (([URL]) -> Void)? = nil,
        moveToTrash: (([URL]) -> Void)? = nil
    ) -> NSMenu {
        let menu = NSMenu()
        guard let firstURL = urls.first else { return menu }
        let isDirectory = (try? firstURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isMulti = urls.count > 1

        // Quick Look — pluralize with the actual selection count for multi.
        let qlTitle = isMulti ? "Quick Look \(urls.count) Items" : "Quick Look"
        let qlItem = NSMenuItem(title: qlTitle, action: nil, keyEquivalent: " ")
        qlItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        let qlTarget = MenuActionTarget { quickLookToggle() }
        qlItem.target = qlTarget
        qlItem.action = #selector(MenuActionTarget.invokeAction)
        qlTarget.retainOn(qlItem)
        menu.addItem(qlItem)

        // Detail Preview — single-item only; multiple Preview windows are
        // rarely intended and noisy.
        if !isMulti {
            let previewItem = NSMenuItem(title: "Preview", action: nil, keyEquivalent: "")
            previewItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
            let previewTarget = MenuActionTarget { detailPreview(urls) }
            previewItem.target = previewTarget
            previewItem.action = #selector(MenuActionTarget.invokeAction)
            previewTarget.retainOn(previewItem)
            menu.addItem(previewItem)
        }

        menu.addItem(.separator())

        // Open With submenu — default app at the top, then a divider, then
        // the rest alphabetically. Matches the Finder layout.
        let allApps = NSWorkspace.shared.urlsForApplications(toOpen: firstURL)
        if !allApps.isEmpty {
            let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: firstURL)
            let submenu = NSMenu()

            if let defaultAppURL {
                submenu.addItem(makeAppItem(appURL: defaultAppURL, urls: urls))
                submenu.addItem(.separator())
            }

            let restApps = allApps
                .filter { $0 != defaultAppURL }
                .sorted {
                    FileManager.default.displayName(atPath: $0.path)
                        .localizedCaseInsensitiveCompare(
                            FileManager.default.displayName(atPath: $1.path)
                        ) == .orderedAscending
                }
            for appURL in restApps {
                submenu.addItem(makeAppItem(appURL: appURL, urls: urls))
            }

            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.submenu = submenu
            menu.addItem(openWithItem)
        }

        // Open in New Window — directories only, single-selection only to
        // avoid spawning many windows by accident.
        if !isMulti, isDirectory, let openInNewWindow {
            let newWindowItem = NSMenuItem(title: "Open in New Window", action: nil, keyEquivalent: "")
            newWindowItem.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
            let newWindowTarget = MenuActionTarget { openInNewWindow(firstURL) }
            newWindowItem.target = newWindowTarget
            newWindowItem.action = #selector(MenuActionTarget.invokeAction)
            newWindowTarget.retainOn(newWindowItem)
            menu.addItem(newWindowItem)
        }

        menu.addItem(.separator())

        // Reveal in Finder
        let revealItem = NSMenuItem(title: "Reveal in Finder", action: nil, keyEquivalent: "")
        revealItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        let revealTarget = MenuActionTarget {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
        revealItem.target = revealTarget
        revealItem.action = #selector(MenuActionTarget.invokeAction)
        revealTarget.retainOn(revealItem)
        menu.addItem(revealItem)

        // Copy Path — title and icon mirror AppAction.copyPath so menu and
        // keyboard shortcut stay in sync. Pluralize for multi-selection.
        if let copyPath {
            let copyTitle = isMulti ? "Copy \(urls.count) Paths" : "Copy Path"
            let copyItem = NSMenuItem(title: copyTitle, action: nil, keyEquivalent: "")
            copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            let copyTarget = MenuActionTarget { copyPath(urls) }
            copyItem.target = copyTarget
            copyItem.action = #selector(MenuActionTarget.invokeAction)
            copyTarget.retainOn(copyItem)
            menu.addItem(copyItem)
        }

        // Move to Trash — destructive, separated and pinned to the bottom.
        // Title and icon mirror AppAction.moveToTrash.
        if let moveToTrash {
            menu.addItem(.separator())
            let trashItem = NSMenuItem(title: "Move to Trash", action: nil, keyEquivalent: "")
            trashItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            let trashTarget = MenuActionTarget { moveToTrash(urls) }
            trashItem.target = trashTarget
            trashItem.action = #selector(MenuActionTarget.invokeAction)
            trashTarget.retainOn(trashItem)
            menu.addItem(trashItem)
        }

        return menu
    }

    private static func iconForApp(at url: URL, size: CGFloat) -> NSImage {
        // Copy the cached image before mutating `size` — otherwise the size
        // change would leak across cache hits and affect later callers.
        let cached = AppIconCache.shared.icon(for: url)
        let icon = cached.copy() as? NSImage ?? cached
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private static func makeAppItem(appURL: URL, urls: [URL]) -> NSMenuItem {
        let name = FileManager.default.displayName(atPath: appURL.path)
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.image = iconForApp(at: appURL, size: 16)
        let target = MenuActionTarget {
            NSWorkspace.shared.open(
                urls, withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
        item.target = target
        item.action = #selector(MenuActionTarget.invokeAction)
        target.retainOn(item)
        return item
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
