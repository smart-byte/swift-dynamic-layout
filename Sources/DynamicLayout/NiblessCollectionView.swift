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
public class NiblessCollectionView: NSCollectionView {
    private var programmaticClasses: [NSUserInterfaceItemIdentifier: NSCollectionViewItem.Type] = [:]

    public weak var quickLookCoordinator: Coordinator?
    public var actionHandler: (any ItemActionHandler)?

    public func registerProgrammatic(
        _ itemClass: NSCollectionViewItem.Type,
        forItemWithIdentifier identifier: NSUserInterfaceItemIdentifier
    ) {
        programmaticClasses[identifier] = itemClass
    }

    override public func makeItem(
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

    override public func keyDown(with event: NSEvent) {
        if event.characters == " " {
            QuickLookHelpers.togglePanel()
        } else {
            super.keyDown(with: event)
        }
    }

    override public func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
        true
    }

    override public func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookCoordinator
        panel.delegate = quickLookCoordinator
    }

    override public func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: - Context Menu

    override public func rightMouseDown(with event: NSEvent) {
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

    override public func mouseDown(with event: NSEvent) {
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
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        view.layer?.cornerRadius = 1.5
        view.isHidden = true
        addSubview(view)
        return view
    }()

    public func showDropIndicator(at frame: CGRect) {
        dropIndicatorView.frame = frame
        dropIndicatorView.isHidden = false
    }

    public func hideDropIndicator() {
        dropIndicatorView.isHidden = true
    }

    /// Hide the default gap indicator that NSCollectionView adds
    /// for .before drop operations — we draw our own.
    override public func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        let className = String(describing: type(of: subview))
        if className.contains("Gap") || className.contains("Drop") {
            if subview !== dropIndicatorView {
                subview.isHidden = true
            }
        }
    }

    // MARK: - Pane-Level Drop Target Highlight

    /// Paints an accent-coloured border around the enclosing scroll view
    /// while a Finder / cross-pane drag hovers over the pane's whitespace
    /// (NOT over a folder cell — those use NSCollectionView's built-in
    /// `.asDropTarget` highlight via `ThumbnailItem.highlightState`).
    /// Apple has no built-in for "drop into the whole view", so this is
    /// custom.
    public func setDropTargetHighlight(_ highlighted: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.wantsLayer = true
        let layer = scrollView.layer
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = highlighted ? 3 : 0
        layer?.cornerRadius = highlighted ? 6 : 0
    }

    /// Cleans up the pane border + insertion line when the cursor leaves
    /// without a drop. Neither `endedAt` (target side) nor `acceptDrop`
    /// fires in that case.
    override public func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        setDropTargetHighlight(false)
        hideDropIndicator()
    }
}
