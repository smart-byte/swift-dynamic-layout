import AppKit
@testable import DynamicLayout
import SwiftUI
import Testing

@MainActor
struct CollectionSelectionTests {
    nonisolated static let modes = LayoutMode.allCases.filter { $0 != .list }

    @Test(arguments: modes)
    func updatesPreserveNativeMultiSelectionUntilDelegatePublishes(mode: LayoutMode) {
        let fixture = SelectionFixture(mode: mode)
        let collection = fixture.collection
        let coordinator = fixture.coordinator
        #expect(collection.selectionIndexPaths == paths(1))

        // AppKit has extended the native selection, but has not delivered
        // its delegate callback when a focus-triggered update arrives.
        collection.selectionIndexPaths = paths(1, 3, 4)
        fixture.update()
        #expect(collection.selectionIndexPaths == paths(1, 3, 4))
        #expect(fixture.selected == paths(1))

        coordinator.collectionView(collection, didSelectItemsAt: paths(3, 4))
        #expect(fixture.selected == paths(1, 3, 4))
        fixture.update()
        #expect(collection.selectionIndexPaths == fixture.selected)

        collection.selectionIndexPaths = paths(1, 4)
        fixture.update()
        #expect(collection.selectionIndexPaths == paths(1, 4))
        coordinator.collectionView(collection, didDeselectItemsAt: paths(3))
        #expect(fixture.selected == paths(1, 4))

        // Replacement callbacks must publish the full native set even if
        // deselection is delivered before selection (or vice versa).
        collection.selectionIndexPaths = paths(2)
        coordinator.collectionView(collection, didDeselectItemsAt: paths(1, 4))
        fixture.update()
        #expect(collection.selectionIndexPaths == paths(2))
        coordinator.collectionView(collection, didSelectItemsAt: paths(2))
        #expect(fixture.selected == paths(2))

        fixture.selected = paths(0, 4)
        fixture.update()
        #expect(collection.selectionIndexPaths == paths(0, 4))
        fixture.selected = []
        fixture.update()
        #expect(collection.selectionIndexPaths.isEmpty)
    }

    @Test(arguments: modes)
    func reloadsAndContentChangesRestoreCurrentSelection(mode: LayoutMode) {
        let fixture = SelectionFixture(mode: mode)
        fixture.selected = paths(1, 3)
        fixture.update()

        fixture.style = .borderless
        fixture.update()
        #expect(fixture.collection.selectionIndexPaths == paths(1, 3))

        fixture.items.reverse()
        fixture.revision = UUID()
        fixture.update()
        #expect(fixture.collection.selectionIndexPaths == paths(1, 3))

        fixture.items.removeLast(3)
        fixture.revision = UUID()
        fixture.update()
        #expect(fixture.selected == paths(1))
        #expect(fixture.collection.selectionIndexPaths == paths(1))

        fixture.items.append(contentsOf: makeItems(aspectRatios: [1, 1, 1]))
        fixture.revision = UUID()
        fixture.update()
        #expect(fixture.collection.selectionIndexPaths == paths(1))

        fixture.mode = mode == .waterfall ? .horizontalFlow : .waterfall
        fixture.update()
        #expect(fixture.collection.selectionIndexPaths == paths(1))

        fixture.folder = URL(fileURLWithPath: "/selection-test-folder")
        fixture.items = makeItems(aspectRatios: [1, 1, 1, 1, 1])
        fixture.revision = UUID()
        fixture.update()
        #expect(fixture.collection.selectionIndexPaths == paths(1))
    }

    @Test func deferredReloadUsesLatestSelection() async throws {
        let fixture = SelectionFixture(mode: .waterfall)
        fixture.selected = paths(1, 3)
        fixture.update()
        let reloads = fixture.collection.reloadCount
        fixture.coordinator.parent.crossfadeReload(collectionView: fixture.collection, coordinator: fixture.coordinator)
        fixture.selected = paths(2, 4)
        fixture.update()
        // Other AppKit suites can occupy the main actor for several seconds.
        // Give the completion actual scheduling opportunities instead of
        // expiring a wall-clock deadline while this test cannot resume.
        for _ in 0 ..< 100 {
            if fixture.collection.reloadCount > reloads { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(fixture.collection.reloadCount > reloads)
        #expect(fixture.collection.selectionIndexPaths == paths(2, 4))
        #expect(fixture.selected == paths(2, 4))
    }
}

private func paths(_ items: Int...) -> Set<IndexPath> {
    Set(items.map { IndexPath(item: $0, section: 0) })
}

@MainActor
private final class SelectionFixture {
    var items = makeItems(aspectRatios: [1, 1, 1, 1, 1])
    var selected = paths(1)
    var mode: LayoutMode
    var style = ItemStyle.tile
    var revision = UUID()
    var folder: URL?
    let collection = SelectionCollection(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    private(set) lazy var coordinator = view.makeCoordinator()

    init(mode: LayoutMode) {
        self.mode = mode
        coordinator.collectionView = collection
        collection.dataSource = coordinator
        collection.delegate = coordinator
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        for style in ItemStyle.allCases {
            collection.registerProgrammatic(ThumbnailItem.self, forItemWithIdentifier: CollectionLayoutView.itemIdentifier(for: style))
        }
        update()
    }

    var view: CollectionLayoutView {
        CollectionLayoutView(
            layoutItems: Binding(get: { [unowned self] in items }, set: { [unowned self] in items = $0 }),
            itemsRevision: revision,
            selection: Binding(get: { [unowned self] in selected }, set: { [unowned self] in selected = $0 }),
            layoutMode: .constant(mode), itemStyle: .constant(style), itemSpacing: .constant(4),
            folderURL: folder, urlForFrame: { _ in nil },
            syncImageProvider: { _, _ in nil }, asyncImageProvider: { _, _, completion in completion(nil) },
            folderSwitchAnimated: false
        )
    }

    func update() {
        view.updateCollectionView(collection, coordinator: coordinator)
    }
}

@MainActor
private final class SelectionCollection: NiblessCollectionView {
    var reloadCount = 0
    override func reloadData() {
        reloadCount += 1
        super.reloadData()
    }
}
