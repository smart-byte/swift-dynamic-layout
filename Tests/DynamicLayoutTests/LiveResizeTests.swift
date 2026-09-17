import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct LiveResizeTests {
    enum Kind: CaseIterable {
        case waterfall, vertical, horizontal, justified, horizontalJustified

        @MainActor func make() -> NSCollectionViewLayout & LayoutItemsProvider {
            switch self {
            case .waterfall: WaterfallLayout()
            case .vertical: VerticalFlowLayout()
            case .horizontal: HorizontalFlowLayout()
            case .justified: JustifiedLayout()
            case .horizontalJustified: HorizontalJustifiedLayout()
            }
        }
    }

    @Test func preparationStateSkipsOnlyIdenticalInputs() {
        var state = LayoutPreparationState()
        let initial = state.needsPreparation([800, 5, 0.05])
        let repeated = state.needsPreparation([800, 5, 0.05])
        let resized = state.needsPreparation([808, 5, 0.05])
        #expect(initial)
        #expect(!repeated)
        #expect(resized)
        state.invalidate()
        let invalidated = state.needsPreparation([808, 5, 0.05])
        #expect(invalidated)
    }

    @Test(arguments: Kind.allCases)
    func resizingReusesAttributesAndMatchesFreshLayout(kind: Kind) throws {
        let layout = kind.make()
        layout.items = makeItems(aspectRatios: (0 ..< 150).map { 0.5 + CGFloat($0 % 9) / 3 })
        let collection = prepareLayout(layout, width: 800, height: 600)
        let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        for step in 0 ..< 8 {
            let size = CGSize(width: 420 + step * 51, height: 380 + step * 37)
            collection.frame.size = size
            layout.prepare()
            let fresh = kind.make()
            fresh.items = layout.items
            let reference = prepareLayout(fresh, width: size.width, height: size.height)
            #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) === first)
            #expect(layout.collectionViewContentSize == fresh.collectionViewContentSize)
            for item in layout.items.indices {
                let path = IndexPath(item: item, section: 0)
                #expect(layout.layoutAttributesForItem(at: path)?.frame == fresh.layoutAttributesForItem(at: path)?.frame)
            }
            let viewport = NSRect(x: 200, y: 200, width: size.width, height: size.height)
            #expect(layout.layoutAttributesForElements(in: viewport).map(\.indexPath)
                == fresh.layoutAttributesForElements(in: viewport).map(\.indexPath))
            layout.prepare()
            #expect(layout.collectionViewContentSize == fresh.collectionViewContentSize)
            withExtendedLifetime(reference) {}
        }
        withExtendedLifetime(collection) {}
    }

    @Test(arguments: Kind.allCases)
    func itemMutationGrowthAndEmptyStateInvalidateGeometry(kind: Kind) throws {
        let layout = kind.make()
        layout.items = makeItems(aspectRatios: [1, 1, 1])
        let collection = prepareLayout(layout, width: 800, height: 600)
        let path = IndexPath(item: 0, section: 0)
        let before = try #require(layout.layoutAttributesForItem(at: path)?.frame)
        layout.items[0] = LayoutItemFrame(id: layout.items[0].id, size: CGSize(width: 300, height: 100))
        layout.prepare()
        #expect(layout.layoutAttributesForItem(at: path)?.frame != before)
        layout.items.append(LayoutItemFrame(size: CGSize(width: 100, height: 100)))
        layout.prepare()
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 3, section: 0)) != nil)
        layout.items.removeLast(3)
        layout.prepare()
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)) == nil)
        layout.items = []
        layout.prepare()
        #expect(layout.layoutAttributesForElements(in: NSRect(x: 0, y: 0, width: 10000, height: 10000)).isEmpty)
        withExtendedLifetime(collection) {}
    }

    @Test(arguments: Kind.allCases)
    func batchSnapshotRetainsOldFramesDuringResize(kind: Kind) throws {
        let layout = kind.make()
        layout.items = makeItems(aspectRatios: [1, 2, 0.5])
        let collection = prepareLayout(layout, width: 800, height: 600)
        let path = IndexPath(item: 0, section: 0)
        let before = try #require(layout.layoutAttributesForItem(at: path)?.frame)
        layout.prepare(forCollectionViewUpdates: [])
        collection.frame.size = CGSize(width: 500, height: 400)
        layout.prepare()
        #expect(layout.layoutAttributesForItem(at: path)?.frame != before)
        #expect(layout.finalLayoutAttributesForDisappearingItem(at: path)?.frame == before)
        layout.finalizeCollectionViewUpdates()
        withExtendedLifetime(collection) {}
    }

    @Test(arguments: Kind.allCases)
    func configurationChangesInvalidateGeometry(kind: Kind) throws {
        let layout = kind.make()
        layout.items = makeItems(aspectRatios: [2, 1, 0.5, 3, 1])
        let collection = prepareLayout(layout, width: 800, height: 600)
        let path = IndexPath(item: 0, section: 0)
        let before = try #require(layout.layoutAttributesForItem(at: path)?.frame)
        switch layout {
        case let value as WaterfallLayout: value.columns = 3
        case let value as VerticalFlowLayout: value.spacingPercentage = 0.07
        case let value as HorizontalFlowLayout: value.useSquareCells = true
        case let value as JustifiedLayout: value.useSquareCells = true
        case let value as HorizontalJustifiedLayout: value.useSquareCells = true
        default: Issue.record("Unexpected layout")
        }
        layout.prepare()
        #expect(layout.layoutAttributesForItem(at: path)?.frame != before)
        withExtendedLifetime(collection) {}
    }
}
