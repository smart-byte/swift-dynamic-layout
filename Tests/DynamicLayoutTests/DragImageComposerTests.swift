//
//  DragImageComposerTests.swift
//  DynamicLayoutTests
//

import AppKit
@testable import DynamicLayout
import Testing

struct DragImageComposerTests {
    @Test func layoutModeDragImageStyleMapping() {
        #expect(LayoutMode.list.dragImageStyle == .compact)
        #expect(LayoutMode.justified.dragImageStyle == .medium)
        #expect(LayoutMode.horizontalJustified.dragImageStyle == .medium)
        #expect(LayoutMode.horizontalFlow.dragImageStyle == .medium)
        #expect(LayoutMode.verticalFlow.dragImageStyle == .medium)
        #expect(LayoutMode.waterfall.dragImageStyle == .large)
    }

    /// Stub provider that always returns nil — simulates a cold cache.
    /// DragImageComposer must fall back to the workspace icon in this case.
    private let noCache: SyncImageProvider = { _, _ in nil }

    @Test func composeReturnsTwoComponents() {
        let url = URL(fileURLWithPath: "/tmp/voila-drag-test.txt")
        for style in [DragImageStyle.compact, .medium, .large] {
            let components = DragImageComposer.compose(for: url, style: style, syncProvider: noCache)
            #expect(components.count == 2)
            let keys = components.map(\.key)
            #expect(keys.contains(.icon))
            #expect(keys.contains(.label))
        }
    }

    @Test func compactPlacesIconBesideLabel() {
        let url = URL(fileURLWithPath: "/tmp/voila-drag-test.txt")
        let components = DragImageComposer.compose(for: url, style: .compact, syncProvider: noCache)
        guard let icon = components.first(where: { $0.key == .icon }),
              let label = components.first(where: { $0.key == .label })
        else {
            Issue.record("Missing icon or label component")
            return
        }
        // Compact: label sits to the right of the icon.
        #expect(label.frame.minX >= icon.frame.maxX)
    }

    @Test func mediumAndLargeStackIconAboveLabel() {
        let url = URL(fileURLWithPath: "/tmp/voila-drag-test.txt")
        for style in [DragImageStyle.medium, .large] {
            let components = DragImageComposer.compose(for: url, style: style, syncProvider: noCache)
            guard let icon = components.first(where: { $0.key == .icon }),
                  let label = components.first(where: { $0.key == .label })
            else {
                Issue.record("Missing icon or label component for \(style)")
                continue
            }
            // Stacked: icon's bottom is at or above label's top
            // (origin in bottom-left coords, so icon.minY > label.maxY ish).
            #expect(icon.frame.minY >= label.frame.maxY - 1)
        }
    }

    @Test func iconDimensionMatchesStyle() {
        #expect(DragImageStyle.compact.iconDimension == 16)
        #expect(DragImageStyle.medium.iconDimension == 64)
        #expect(DragImageStyle.large.iconDimension == 128)
    }
}
