//
//  JustifiedLayoutTests.swift
//  DynamicLayoutTests
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct JustifiedLayoutTests {
    @Test func emptyItemsProducesNoFrames() {
        let layout = JustifiedLayout()
        layout.items = []
        let cv = prepareLayout(layout, width: 600, height: 800)
        _ = cv

        #expect(layout.layoutAttributesForElements(in: .infinite).isEmpty)
        #expect(layout.collectionViewContentSize.height == 0)
    }

    @Test func singleItemDoesNotStretchToFill() throws {
        let layout = JustifiedLayout()
        layout.targetRowHeight = 200
        layout.spacing = 4
        layout.items = makeItems(aspectRatios: [1.5])
        let cv = prepareLayout(layout, width: 1000, height: 400)
        _ = cv

        let f = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame)
        // Last row shouldn't stretch: height stays at targetRowHeight,
        // width = targetRowHeight * aspectRatio = 300
        #expect(f.height == 200)
        #expect(f.width == 300)
    }

    @Test func itemsInFullRowShareSameY() {
        let layout = JustifiedLayout()
        layout.targetRowHeight = 200
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Three 1:1 items, each ~200px wide → fit within 700 but overflow wraps next.
        // Width 700 can hold 3 × 200 = 600 (fits), so all three are in row 1.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 700, height: 400)
        _ = cv

        let ys = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame.origin.y }
        #expect(Set(ys).count == 1)
    }

    @Test func rowWrapsWhenProjectedWidthExceedsAvailable() throws {
        let layout = JustifiedLayout()
        layout.targetRowHeight = 200
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Four 1:1 items, each 200 wide at target → 800 total > 700 width → wrap after 3.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 700, height: 400)
        _ = cv

        let y0 = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame.origin.y)
        let y3 = try #require(layout.layoutAttributesForItem(at: .init(item: 3, section: 0))?.frame.origin.y)
        #expect(y3 > y0)
    }

    @Test func fullRowStretchesToFillAvailableWidth() {
        let layout = JustifiedLayout()
        layout.targetRowHeight = 200
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Four 1:1 items wrap at availableWidth=700 → row 0 has 3 items stretched to fill.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 700, height: 400)
        _ = cv

        let rowItems = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame }
        let totalWidth = rowItems.reduce(0) { $0 + $1.width }
        #expect(abs(totalWidth - 700) < 0.5)
    }

    @Test func contentHeightGrowsWithRows() {
        let layout = JustifiedLayout()
        layout.targetRowHeight = 100
        layout.spacing = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // Force two rows.
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 300, height: 800)
        _ = cv

        // At width 300 with row-height 100, each item is ~100 wide → 3 per row,
        // wrap after 3. Two rows → content height ~200.
        #expect(layout.collectionViewContentSize.height > 100)
    }
}
