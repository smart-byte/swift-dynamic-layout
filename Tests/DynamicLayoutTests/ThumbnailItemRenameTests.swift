//
//  ThumbnailItemRenameTests.swift
//  DynamicLayoutTests
//
//  Verifies the inline-rename surface added in v1.2.0:
//  representedFileURL exposure, the cancel-on-no-window guard, and
//  the edit-state flag.
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct ThumbnailItemRenameTests {
    /// `representedFileURL` exposes whatever was last passed to
    /// `configure(with:maxDimension:syncProvider:asyncProvider:)`.
    /// Hosts use this to resolve cell-level interactions without a
    /// parallel index-path map.
    @Test func representedFileURLReflectsConfiguredURL() {
        let item = ThumbnailItem(nibName: nil, bundle: nil)
        item.itemStyle = .photoFrame
        // Touch `view` so loadView fires and the captionLabel exists.
        _ = item.view

        let url = URL(fileURLWithPath: "/tmp/voila-test/foo.txt")
        item.configure(
            with: url,
            syncProvider: { _, _ in nil },
            asyncProvider: { _, _, _ in }
        )

        #expect(item.representedFileURL == url)
    }

    /// Without a host window the cell can't transfer first-responder
    /// status to the caption label, so `beginCaptionEditing` fires
    /// `cancel` immediately rather than leaving the field in a half-
    /// edit state. Documents the contract for hosts that try to
    /// trigger rename on offscreen / pre-installed cells.
    @Test func beginCaptionEditingCancelsWithoutWindow() {
        let item = ThumbnailItem(nibName: nil, bundle: nil)
        item.itemStyle = .tile
        _ = item.view

        let url = URL(fileURLWithPath: "/tmp/voila-test/bar.txt")
        item.configure(
            with: url,
            syncProvider: { _, _ in nil },
            asyncProvider: { _, _, _ in }
        )

        var commitFired = false
        var cancelFired = false
        item.beginCaptionEditing(
            commit: { _ in commitFired = true },
            cancel: { cancelFired = true }
        )

        #expect(!commitFired)
        #expect(cancelFired)
        #expect(!item.isEditingCaption)
    }

    /// `prepareForReuse` cancels any in-flight inline rename — a
    /// cell scrolled out mid-rename must not commit the typed value
    /// against a different file. Smoke test that the cancel path
    /// doesn't crash and clears the edit flag.
    @Test func prepareForReuseCancelsInFlightEdit() {
        let item = ThumbnailItem(nibName: nil, bundle: nil)
        item.itemStyle = .borderless
        _ = item.view
        item.configure(
            with: URL(fileURLWithPath: "/tmp/voila-test/baz.png"),
            syncProvider: { _, _ in nil },
            asyncProvider: { _, _, _ in }
        )

        item.prepareForReuse()

        #expect(!item.isEditingCaption)
        #expect(item.representedFileURL == nil)
    }
}
