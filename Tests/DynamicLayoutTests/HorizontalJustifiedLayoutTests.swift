//
//  HorizontalJustifiedLayoutTests.swift
//  DynamicLayoutTests
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct HorizontalJustifiedLayoutTests {
    @Test func emptyItemsProducesNoFrames() {
        let layout = HorizontalJustifiedLayout()
        layout.items = []
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        #expect(layout.layoutAttributesForElements(in: .infinite).isEmpty)
    }

    @Test func singleItemDoesNotStretchToFill() throws {
        let layout = HorizontalJustifiedLayout()
        layout.targetColumnWidth = 150
        layout.spacing = 0
        layout.items = makeItems(aspectRatios: [1.0])
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        let f = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame)
        // Last column shouldn't stretch: width stays at targetColumnWidth.
        #expect(f.width == 150)
    }

    @Test func itemsInFullColumnShareSameX() {
        let layout = HorizontalJustifiedLayout()
        layout.targetColumnWidth = 100
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Three 1:1 items, each 100 tall at target → fit within 400 height (no wrap).
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        let xs = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame.origin.x }
        #expect(Set(xs).count == 1)
    }

    @Test func columnWrapsWhenProjectedHeightExceedsAvailable() throws {
        let layout = HorizontalJustifiedLayout()
        layout.targetColumnWidth = 100
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Five items each 100 tall, available height 400 → 4th item wraps to next column.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 1000, height: 400)
        _ = cv

        let x0 = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame.origin.x)
        let x4 = try #require(layout.layoutAttributesForItem(at: .init(item: 4, section: 0))?.frame.origin.x)
        #expect(x4 > x0)
    }

    @Test func fullColumnStretchesToFillAvailableHeight() {
        let layout = HorizontalJustifiedLayout()
        layout.targetColumnWidth = 100
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Five 1:1 items wrap at availableHeight=400 → col 0 has 4 items stretched to fill.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 1000, height: 400)
        _ = cv

        let colItems = (0 ..< 4).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame }
        let totalHeight = colItems.reduce(0) { $0 + $1.height }
        #expect(abs(totalHeight - 400) < 0.5)
    }

    @Test func contentWidthGrowsWithColumns() {
        let layout = HorizontalJustifiedLayout()
        layout.targetColumnWidth = 100
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Force two columns.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 1000, height: 400)
        _ = cv

        #expect(layout.collectionViewContentSize.width > 100)
    }
}
