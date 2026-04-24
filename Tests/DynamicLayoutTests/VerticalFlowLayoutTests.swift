//
//  VerticalFlowLayoutTests.swift
//  DynamicLayoutTests
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct VerticalFlowLayoutTests {
    @Test func emptyItemsProducesNoFrames() {
        let layout = VerticalFlowLayout()
        layout.items = []
        let cv = prepareLayout(layout, width: 600, height: 800)
        _ = cv

        #expect(layout.layoutAttributesForElements(in: .infinite).isEmpty)
    }

    @Test func singleItemSpansAvailableWidth() throws {
        let layout = VerticalFlowLayout()
        layout.spacingPercentage = 0
        layout.sectionInset = .init(top: 10, left: 20, bottom: 10, right: 30)
        layout.items = makeItems(aspectRatios: [1.0])
        let cv = prepareLayout(layout, width: 600, height: 800)
        _ = cv

        let f = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame)
        // availableWidth = 600 - 20 - 30 = 550
        #expect(f.width == 550)
        // Square item → height == width
        #expect(f.height == 550)
        #expect(f.origin.x == 20)
        #expect(f.origin.y == 10)
    }

    @Test func itemsStackVertically() {
        let layout = VerticalFlowLayout()
        layout.spacingPercentage = 0
        layout.items = makeItems(aspectRatios: [1.0, 1.0, 1.0])
        let cv = prepareLayout(layout, width: 600, height: 2000)
        _ = cv

        let ys = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame.origin.y }
        // Strictly increasing
        #expect(ys == ys.sorted())
        #expect(Set(ys).count == 3)
    }

    @Test func allItemsShareSameWidth() {
        let layout = VerticalFlowLayout()
        layout.items = makeItems(aspectRatios: [2.0, 1.0, 0.5])
        let cv = prepareLayout(layout, width: 600, height: 2000)
        _ = cv

        let widths = (0 ..< 3).compactMap { layout.layoutAttributesForItem(at: .init(item: $0, section: 0))?.frame.width }
        #expect(Set(widths).count == 1)
    }

    @Test func heightsFollowInverseAspectRatio() throws {
        let layout = VerticalFlowLayout()
        layout.spacingPercentage = 0
        layout.sectionInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        // 2:1 tall wide item → shorter height; 1:2 narrow → taller height
        layout.items = makeItems(aspectRatios: [2.0, 1.0, 0.5])
        let cv = prepareLayout(layout, width: 400, height: 2000)
        _ = cv

        let h0 = try #require(layout.layoutAttributesForItem(at: .init(item: 0, section: 0))?.frame.height)
        let h1 = try #require(layout.layoutAttributesForItem(at: .init(item: 1, section: 0))?.frame.height)
        let h2 = try #require(layout.layoutAttributesForItem(at: .init(item: 2, section: 0))?.frame.height)

        // availableWidth=400: heights are 400/2=200, 400/1=400, 400/0.5=800
        #expect(h0 == 200)
        #expect(h1 == 400)
        #expect(h2 == 800)
    }
}
