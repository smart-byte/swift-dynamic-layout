//
//  HorizontalFlowLayoutTests.swift
//  DynamicLayoutTests
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct HorizontalFlowLayoutTests {
    @Test func emptyItemsProducesNoFrames() {
        let layout = HorizontalFlowLayout()
        layout.items = []
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        #expect(layout.layoutAttributesForElements(in: .infinite).isEmpty)
    }

    @Test func singleItemOccupiesFullAvailableHeight() throws {
        let layout = HorizontalFlowLayout()
        layout.spacingPercentage = 0
        layout.sectionInset = .init(top: 10, left: 20, bottom: 10, right: 20)
        layout.items = makeItems(aspectRatios: [1.0])
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        let f = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame)
        // availableHeight = 400 - 10 - 10 = 380
        #expect(f.height == 380)
        // Square item → width == height
        #expect(f.width == 380)
        #expect(f.origin.y == 10)
        #expect(f.origin.x == 20)
    }

    @Test func itemsAreLaidOutLeftToRight() {
        let layout = HorizontalFlowLayout()
        layout.spacingPercentage = 0
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        let xs = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame.origin.x }
        // Strictly increasing
        #expect(xs == xs.sorted())
        #expect(Set(xs).count == 3)
    }

    @Test func itemWidthFollowsAspectRatio() throws {
        let layout = HorizontalFlowLayout()
        layout.spacingPercentage = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // 2:1, 1:1, 1:2 aspect ratios
        layout.items = makeItems(aspectRatios: [2.0, 1.0, 0.5])
        let cv = prepareLayout(layout, width: 1000, height: 400)
        _ = cv

        let w0 = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame.width)
        let w1 = try #require(layout.layoutAttributesForItem(at: .init(item: 1, section: 0))?.frame.width)
        let w2 = try #require(layout.layoutAttributesForItem(at: .init(item: 2, section: 0))?.frame.width)

        // With 400 height and zero insets, widths should be: 800, 400, 200
        #expect(w0 == 800)
        #expect(w1 == 400)
        #expect(w2 == 200)
    }

    @Test func contentWidthGrowsWithItemCount() {
        let layout = HorizontalFlowLayout()
        layout.spacingPercentage = 0
        layout.items = makeItems(aspectRatios: [1.0])
        let cv = prepareLayout(layout, width: 800, height: 400)
        _ = cv

        let width1 = layout.collectionViewContentSize.width

        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0])
        layout.prepare()
        let width3 = layout.collectionViewContentSize.width

        #expect(width3 > width1)
    }
}
