//
//  WaterfallLayoutTests.swift
//  DynamicLayoutTests
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct WaterfallLayoutTests {
    // MARK: - Empty / trivial

    @Test func emptyItemsProducesNoFrames() {
        let layout = WaterfallLayout()
        layout.items = []
        let cv = prepareLayout(layout, width: 600, height: 800)
        _ = cv // keep alive

        #expect(layout.layoutAttributesForElements(in: .infinite).isEmpty)
        // Empty content still reserves the section insets vertically.
        #expect(layout.collectionViewContentSize.height == layout.sectionInset.top + layout.sectionInset.bottom)
    }

    @Test func singleItemLandsInFirstColumn() {
        let layout = WaterfallLayout()
        layout.columns = 3
        layout.spacingPercentage = 0
        layout.items = makeItems(aspectRatios: [1.0])
        let cv = prepareLayout(layout, width: 600, height: 800)

        let attr = layout.layoutAttributesForItem(at: .init(item: 0, section: 0))
        #expect(attr != nil)
        // First item's x should equal sectionInset.left (default 20)
        #expect(attr?.frame.origin.x == 20)
        #expect(attr?.frame.origin.y == 20)
    }

    // MARK: - Column balancing

    @Test func itemsDistributeAcrossColumns() {
        let layout = WaterfallLayout()
        layout.columns = 3
        layout.spacingPercentage = 0
        // Three items with same aspect ratio → one per column
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 600, height: 800)

        let xs = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame.origin.x }
        // Three distinct x positions, sorted
        #expect(Set(xs).count == 3)
        #expect(xs == xs.sorted())
    }

    @Test func shortestColumnWinsNextItem() throws {
        let layout = WaterfallLayout()
        layout.columns = 2
        layout.spacingPercentage = 0
        // First item is tall (ratio 0.5 → height 2× width),
        // second item should go in the other column first to balance.
        layout.items = makeItems(aspectRatios: [0.5, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 600, height: 800)

        let f0 = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame)
        let f1 = try #require(layout.layoutAttributesForItem(at: .init(item: 1, section: 0))?.frame)
        let f2 = try #require(layout.layoutAttributesForItem(at: .init(item: 2, section: 0))?.frame)

        // Items 0 and 1 land in different columns (balancing)
        #expect(f0.origin.x != f1.origin.x)
        // Item 2 goes to the shorter column — which is column 1 (item 1 is less tall than item 0)
        #expect(f2.origin.x == f1.origin.x)
    }

    // MARK: - Geometry

    @Test func columnWidthRespectsSectionInsetAndSpacing() throws {
        let layout = WaterfallLayout()
        layout.columns = 2
        layout.spacingPercentage = 0 // simpler math
        layout.sectionInset = .init(top: 0, left: 10, bottom: 0, right: 10)
        layout.items = makeItems(aspectRatios: [1.0, 1.0])
        let cv = prepareLayout(layout, width: 220, height: 400)

        // availableWidth = 220 - 10 - 10 = 200; columnWidth = 100
        let f0 = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame)
        #expect(f0.width == 100)
        #expect(f0.origin.x == 10)
    }

    @Test func contentSizeWidthMatchesViewportWidth() {
        let layout = WaterfallLayout()
        layout.items = makeItems(aspectRatios: [1.0, 1.0])
        let cv = prepareLayout(layout, width: 800, height: 600)

        #expect(layout.collectionViewContentSize.width == 800)
    }
}
