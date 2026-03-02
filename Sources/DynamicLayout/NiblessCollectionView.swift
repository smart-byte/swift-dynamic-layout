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
    weak var actionHandler: ItemActionHandler?

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

        // Select item under cursor if not already selected
        if let indexPath = indexPathForItem(at: point),
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
            detailPreview: { [weak self] urls in self?.actionHandler?.didRequestDetailPreview(for: urls) }
        )
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Double-Click

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)

        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            guard let indexPath = indexPathForItem(at: point),
                  let coordinator = quickLookCoordinator
            else { return }

            let urls = coordinator.selectedURLs
            if !urls.isEmpty {
                actionHandler?.didRequestDetailPreview(for: urls)
            }
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
