//
//  ItemContextMenuBuilder.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import AppKit

/// Builds a shared context menu for file items in both collection and list views.
@MainActor
public enum ItemContextMenuBuilder {
    public static func menu(
        for urls: [URL],
        quickLookToggle: @escaping () -> Void,
        detailPreview: @escaping ([URL]) -> Void,
        openInNewTab: ((URL) -> Void)? = nil,
        openInNewWindow: ((URL) -> Void)? = nil,
        openInNewPane: ((URL) -> Void)? = nil,
        copyPath: (([URL]) -> Void)? = nil,
        moveToTrash: (([URL]) -> Void)? = nil
    ) -> NSMenu {
        let menu = NSMenu()
        guard let firstURL = urls.first else { return menu }
        let isDirectory = (try? firstURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isMulti = urls.count > 1

        addPreviewItems(to: menu, urls: urls, isMulti: isMulti, quickLookToggle: quickLookToggle, detailPreview: detailPreview)
        menu.addItem(.separator())
        addOpenWithSubmenu(to: menu, urls: urls, firstURL: firstURL)
        if !isMulti, isDirectory {
            addOpenElsewhereItems(
                to: menu,
                firstURL: firstURL,
                openInNewTab: openInNewTab,
                openInNewWindow: openInNewWindow,
                openInNewPane: openInNewPane
            )
        }
        menu.addItem(.separator())
        addRevealAndCopyItems(to: menu, urls: urls, isMulti: isMulti, copyPath: copyPath)
        if let moveToTrash {
            menu.addItem(.separator())
            menu.addItem(makeItem(title: "Move to Trash", icon: "trash") { moveToTrash(urls) })
        }
        return menu
    }

    // MARK: - Section builders

    private static func addPreviewItems(
        to menu: NSMenu,
        urls: [URL],
        isMulti: Bool,
        quickLookToggle: @escaping () -> Void,
        detailPreview: @escaping ([URL]) -> Void
    ) {
        let qlTitle = isMulti ? "Quick Look \(urls.count) Items" : "Quick Look"
        let qlItem = makeItem(title: qlTitle, icon: "eye", keyEquivalent: " ", action: quickLookToggle)
        menu.addItem(qlItem)

        // Single-item only; multiple Preview windows are rarely intended
        // and noisy.
        if !isMulti {
            menu.addItem(makeItem(title: "Preview", icon: "macwindow") { detailPreview(urls) })
        }
    }

    private static func addOpenWithSubmenu(to menu: NSMenu, urls: [URL], firstURL: URL) {
        // Default app at the top, then a divider, then the rest
        // alphabetically — matches the Finder layout.
        let allApps = NSWorkspace.shared.urlsForApplications(toOpen: firstURL)
        guard !allApps.isEmpty else { return }

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

    /// Directory-only "open elsewhere" group. Single-selection only so
    /// accidental clicks on a wide selection don't spawn dozens of
    /// tabs/windows. Order follows Finder/Safari convention: Tab first,
    /// Window second; the Pane variant is Voila-specific and trails.
    private static func addOpenElsewhereItems(
        to menu: NSMenu,
        firstURL: URL,
        openInNewTab: ((URL) -> Void)?,
        openInNewWindow: ((URL) -> Void)?,
        openInNewPane: ((URL) -> Void)?
    ) {
        if let openInNewTab {
            menu.addItem(makeItem(title: "Open in New Tab", icon: "plus.rectangle.on.rectangle") {
                openInNewTab(firstURL)
            })
        }
        if let openInNewWindow {
            menu.addItem(makeItem(title: "Open in New Window", icon: "macwindow.badge.plus") {
                openInNewWindow(firstURL)
            })
        }
        if let openInNewPane {
            menu.addItem(makeItem(title: "Open in New Pane", icon: "rectangle.split.2x1") {
                openInNewPane(firstURL)
            })
        }
    }

    private static func addRevealAndCopyItems(
        to menu: NSMenu,
        urls: [URL],
        isMulti: Bool,
        copyPath: (([URL]) -> Void)?
    ) {
        menu.addItem(makeItem(title: "Reveal in Finder", icon: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        })

        if let copyPath {
            let copyTitle = isMulti ? "Copy \(urls.count) Paths" : "Copy Path"
            menu.addItem(makeItem(title: copyTitle, icon: "doc.on.doc") { copyPath(urls) })
        }
    }

    // MARK: - Item factories

    /// `keyEquivalent` defaults to `""`; passing `" "` matches Quick Look's
    /// space-bar shortcut for visual cue (no actual key dispatch happens
    /// from a context menu).
    private static func makeItem(
        title: String,
        icon: String?,
        keyEquivalent: String = "",
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: keyEquivalent)
        if let icon {
            item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        let target = MenuActionTarget(action)
        item.target = target
        item.action = #selector(MenuActionTarget.invokeAction)
        target.retainOn(item)
        return item
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
