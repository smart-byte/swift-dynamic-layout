//
//  ItemContextMenuBuilder.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import AppKit

/// Builds a shared context menu for file items in both collection and list views.
enum ItemContextMenuBuilder {
    static func menu(
        for urls: [URL],
        quickLookToggle: @escaping () -> Void,
        detailPreview: @escaping ([URL]) -> Void
    ) -> NSMenu {
        let menu = NSMenu()
        guard let firstURL = urls.first else { return menu }

        // Quick Look
        let qlItem = NSMenuItem(title: "Quick Look", action: nil, keyEquivalent: " ")
        qlItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
        let qlTarget = MenuActionTarget { quickLookToggle() }
        qlItem.target = qlTarget
        qlItem.action = #selector(MenuActionTarget.invokeAction)
        qlTarget.retainOn(qlItem)
        menu.addItem(qlItem)

        // Detail Preview
        let previewItem = NSMenuItem(title: "Preview", action: nil, keyEquivalent: "")
        previewItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        let previewTarget = MenuActionTarget { detailPreview(urls) }
        previewItem.target = previewTarget
        previewItem.action = #selector(MenuActionTarget.invokeAction)
        previewTarget.retainOn(previewItem)
        menu.addItem(previewItem)

        menu.addItem(.separator())

        // Open With default app
        if let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: firstURL) {
            let appName = FileManager.default.displayName(atPath: defaultAppURL.path)
            let openItem = NSMenuItem(title: "Open with \(appName)", action: nil, keyEquivalent: "")
            openItem.image = iconForApp(at: defaultAppURL, size: 16)
            let openTarget = MenuActionTarget {
                NSWorkspace.shared.open(
                    urls, withApplicationAt: defaultAppURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
            }
            openItem.target = openTarget
            openItem.action = #selector(MenuActionTarget.invokeAction)
            openTarget.retainOn(openItem)
            menu.addItem(openItem)
        }

        // Open With submenu
        let allApps = NSWorkspace.shared.urlsForApplications(toOpen: firstURL)
        if allApps.count > 1 {
            let submenu = NSMenu()
            let sortedApps = allApps.sorted {
                FileManager.default.displayName(atPath: $0.path)
                    .localizedCaseInsensitiveCompare(
                        FileManager.default.displayName(atPath: $1.path)
                    ) == .orderedAscending
            }
            for appURL in sortedApps {
                let name = FileManager.default.displayName(atPath: appURL.path)
                let appItem = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                appItem.image = iconForApp(at: appURL, size: 16)
                let appTarget = MenuActionTarget {
                    NSWorkspace.shared.open(
                        urls, withApplicationAt: appURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
                appItem.target = appTarget
                appItem.action = #selector(MenuActionTarget.invokeAction)
                appTarget.retainOn(appItem)
                submenu.addItem(appItem)
            }
            let openWithItem = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            openWithItem.submenu = submenu
            menu.addItem(openWithItem)
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

        return menu
    }

    private static func iconForApp(at url: URL, size: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
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
