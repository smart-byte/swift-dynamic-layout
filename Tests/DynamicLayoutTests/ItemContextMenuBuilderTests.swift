//
//  ItemContextMenuBuilderTests.swift
//  DynamicLayoutTests
//
//  Covers the rename entry added in v1.2.0 — visibility (single
//  selection only) and click forwarding.
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct ItemContextMenuBuilderTests {
    @Test func renameEntryAppearsForSingleSelection() {
        let menu = ItemContextMenuBuilder.menu(
            for: [URL(fileURLWithPath: "/tmp/foo.txt")],
            quickLookToggle: {},
            detailPreview: { _ in },
            rename: { _ in }
        )

        #expect(menu.items.contains { $0.title == "Rename" })
    }

    @Test func renameEntryHiddenForMultiSelection() {
        let menu = ItemContextMenuBuilder.menu(
            for: [
                URL(fileURLWithPath: "/tmp/foo.txt"),
                URL(fileURLWithPath: "/tmp/bar.txt"),
            ],
            quickLookToggle: {},
            detailPreview: { _ in },
            rename: { _ in }
        )

        #expect(!menu.items.contains { $0.title == "Rename" })
    }

    @Test func renameEntryHiddenWhenCallbackIsNil() {
        let menu = ItemContextMenuBuilder.menu(
            for: [URL(fileURLWithPath: "/tmp/foo.txt")],
            quickLookToggle: {},
            detailPreview: { _ in }
        )

        #expect(!menu.items.contains { $0.title == "Rename" })
    }

    @Test func renameEntryFiresWithFirstURL() {
        var receivedURL: URL?
        let menu = ItemContextMenuBuilder.menu(
            for: [URL(fileURLWithPath: "/tmp/foo.txt")],
            quickLookToggle: {},
            detailPreview: { _ in },
            rename: { receivedURL = $0 }
        )
        let renameItem = menu.items.first { $0.title == "Rename" }
        // Use the menu item's own action target rather than NSApp.sendAction
        // so the test doesn't need an attached app instance.
        if let item = renameItem,
           let target = item.target,
           let action = item.action
        {
            _ = target.perform(action, with: item)
        }

        #expect(receivedURL?.lastPathComponent == "foo.txt")
    }
}
