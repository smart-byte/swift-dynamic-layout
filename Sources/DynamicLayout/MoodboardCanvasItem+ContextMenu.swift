//
//  MoodboardCanvasItem+ContextMenu.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

extension MoodboardCanvasItem {
    func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let bringToFront = NSMenuItem(title: "Bring to Front", action: #selector(bringToFrontAction), keyEquivalent: "")
        bringToFront.target = self
        menu.addItem(bringToFront)

        let sendToBack = NSMenuItem(title: "Send to Back", action: #selector(sendToBackAction), keyEquivalent: "")
        sendToBack.target = self
        menu.addItem(sendToBack)

        menu.addItem(NSMenuItem.separator())

        let remove = NSMenuItem(title: "Remove", action: #selector(removeAction), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)

        return menu
    }

    @objc func bringToFrontAction() {
        canvas?.coordinator?.itemReordered(itemID, action: .bringToFront)
    }

    @objc func sendToBackAction() {
        canvas?.coordinator?.itemReordered(itemID, action: .sendToBack)
    }

    @objc func removeAction() {
        canvas?.coordinator?.itemRemoved(itemID)
    }
}
