import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct LayoutVisibilityIndexTests {
    @Test func prepareInvalidatesPreviouslyQueriedGeometry() throws {
        let layout = WaterfallLayout()
        layout.columns = 1
        layout.spacingPercentage = 0
        layout.items = [LayoutItemFrame(size: CGSize(width: 100, height: 100))]
        let collection = prepareLayout(layout, width: 200, height: 400)
        let rect = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        let before = try #require(layout.layoutAttributesForElements(in: rect).first?.frame)
        collection.frame.size.width = 400
        layout.prepare()
        let after = try #require(layout.layoutAttributesForElements(in: rect).first?.frame)
        #expect(after.width > before.width)
        layout.items = []
        layout.prepare()
        #expect(layout.layoutAttributesForElements(in: rect).isEmpty)
    }

    @Test(arguments: [false, true])
    func matchesFullScanWithOverlapsAndUnsortedFrames(horizontal: Bool) {
        let attributes = (0 ..< 200).map { index in
            let attribute = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
            // Deterministic mixed sizes/order, including long overlapping items.
            let start = CGFloat((index * 37) % 200) * 20
            let length = index % 7 == 0 ? CGFloat(1800) : CGFloat(35)
            attribute.frame = horizontal
                ? NSRect(x: start, y: CGFloat(index % 3) * 50, width: length, height: 40)
                : NSRect(x: CGFloat(index % 3) * 50, y: start, width: 40, height: length)
            return attribute
        }
        let index = LayoutVisibilityIndex(attributes, horizontal: horizontal)
        for offset in stride(from: -100, to: 6500, by: 73) {
            let rect = horizontal
                ? NSRect(x: offset, y: 20, width: 250, height: 90)
                : NSRect(x: 20, y: offset, width: 90, height: 250)
            #expect(index.attributes(in: rect).map(\.indexPath)
                == attributes.filter { $0.frame.intersects(rect) }.map(\.indexPath))
        }
    }

    @Test func viewportQueryDoesNotInspectTenThousandOffscreenItems() {
        let attributes = (0 ..< 10000).map { item in
            let attribute = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: item, section: 0))
            attribute.frame = NSRect(x: 0, y: item * 100, width: 100, height: 90)
            return attribute
        }
        let index = LayoutVisibilityIndex(attributes)
        let viewport = NSRect(x: 0, y: 500_000, width: 100, height: 800)
        #expect(index.candidateRange(in: viewport).count <= 10)
        #expect(index.attributes(in: viewport).count == 8)
        #expect(LayoutVisibilityIndex([]).attributes(in: viewport).isEmpty)
    }
}
