//
//  NiblessCollectionView.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import AppKit
import Quartz

/// NSCollectionView subclass that bypasses nib loading, supports Quick Look,
/// context menus, double-click, and a custom drop indicator.
class NiblessCollectionView: NSCollectionView {
    private var programmaticClasses: [NSUserInterfaceItemIdentifier: NSCollectionViewItem.Type] = [:]

    weak var quickLookCoordinator: Coordinator?
    var actionHandler: ItemActionHandler?

    func registerProgrammatic(
        _ itemClass: NSCollectionViewItem.Type,
        forItemWithIdentifier identifier: NSUserInterfaceItemIdentifier
    ) {
        programmaticClasses[identifier] = itemClass
    }

    override func makeItem(
        withIdentifier identifier: NSUserInterfaceItemIdentifier,
        for _: IndexPath
    ) -> NSCollectionViewItem {
        if let itemClass = programmaticClasses[identifier] {
            let item = itemClass.init(nibName: nil, bundle: nil)
            item.identifier = identifier
            return item
        }
        fatalError("Unknown item identifier: \(identifier.rawValue)")
    }

    // MARK: - Quick Look

    override func keyDown(with event: NSEvent) {
        if event.characters == " " {
            QuickLookHelpers.togglePanel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookCoordinator
        panel.delegate = quickLookCoordinator
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - Context Menu

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)

        // Background click — no item under cursor. Show the pane-level
        // menu (New Folder, Reveal in Finder, …) instead of falling
        // through to a no-op.
        if clickedIndexPath == nil {
            if let coordinator = quickLookCoordinator,
               let folderURL = coordinator.currentFolderURL
            {
                let menu = BackgroundContextMenuBuilder.menu(
                    forFolder: folderURL,
                    newFolder: { [weak self] in self?.actionHandler?.didRequestNewFolder(in: folderURL) },
                    revealInFinder: { [weak self] in self?.actionHandler?.didRequestRevealFolderInFinder(folderURL) }
                )
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return
            }
            super.rightMouseDown(with: event)
            return
        }

        // Select item under cursor if not already selected
        if let indexPath = clickedIndexPath,
           !selectionIndexPaths.contains(indexPath)
        {
            selectionIndexPaths = [indexPath]
        }

        guard let coordinator = quickLookCoordinator else {
            super.rightMouseDown(with: event)
            return
        }

        let urls = coordinator.selectedURLs
        guard !urls.isEmpty else {
            super.rightMouseDown(with: event)
            return
        }

        let menu = ItemContextMenuBuilder.menu(
            for: urls,
            quickLookToggle: { QuickLookHelpers.togglePanel() },
            detailPreview: { [weak self] urls in self?.actionHandler?.didRequestDetailPreview(for: urls) },
            openInNewTab: { [weak self] url in self?.actionHandler?.didRequestOpenInNewTab(url) },
            openInNewWindow: { [weak self] url in self?.actionHandler?.didRequestOpenInNewWindow(url) },
            openInNewPane: { [weak self] url in self?.actionHandler?.didRequestOpenInNewPane(url) },
            copyPath: { [weak self] urls in self?.actionHandler?.didRequestCopyPath(urls) },
            moveToTrash: { [weak self] urls in self?.actionHandler?.didRequestMoveToTrash(urls) }
        )
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Double-Click

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        guard event.clickCount == 2 else { return }

        let point = convert(event.locationInWindow, from: nil)
        guard indexPathForItem(at: point) != nil,
              let coordinator = quickLookCoordinator,
              let url = coordinator.selectedURLs.first
        else { return }

        let cmdHeld = event.modifierFlags.contains(.command)
        dispatchDoubleClick(url: url, cmdHeld: cmdHeld)
    }

    private func dispatchDoubleClick(url: URL, cmdHeld: Bool) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if isDir {
            if cmdHeld {
                // Finder convention: ⌘-double-click opens in a new tab in
                // the current pane, not a new split. Split is reachable
                // explicitly via the context menu.
                actionHandler?.didRequestOpenInNewTab(url)
            } else {
                actionHandler?.didRequestNavigate(into: url)
            }
        } else {
            actionHandler?.didRequestOpenFile(url)
        }
    }

    // MARK: - Custom Drop Indicator

    private lazy var dropIndicatorView: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        v.layer?.cornerRadius = 1.5
        v.isHidden = true
        addSubview(v)
        return v
    }()

    func showDropIndicator(at frame: CGRect) {
        dropIndicatorView.frame = frame
        dropIndicatorView.isHidden = false
    }

    func hideDropIndicator() {
        dropIndicatorView.isHidden = true
    }

    /// Hide the default gap indicator that NSCollectionView adds
    /// for .before drop operations — we draw our own.
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        let className = String(describing: type(of: subview))
        if className.contains("Gap") || className.contains("Drop") {
            if subview !== dropIndicatorView {
                subview.isHidden = true
            }
        }
    }
}
