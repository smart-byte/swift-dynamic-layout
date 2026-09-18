import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct RenderedResizeTests {
    @Test(arguments: LiveResizeTests.Kind.allCases, [false, true])
    func visibleCellsFollowResizedLayout(kind: LiveResizeTests.Kind, afterHiddenResize: Bool) throws {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        defer { NSAnimationContext.endGrouping() }
        let layout = kind.make()
        let horizontal = kind == .horizontal || kind == .horizontalJustified
        layout.items = makeItems(aspectRatios: (0 ..< 150).map { 0.5 + CGFloat($0 % 9) / 3 })
        let source = ResizeDataSource(count: layout.items.count)
        let collection = NiblessCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        collection.collectionViewLayout = layout
        collection.dataSource = source
        collection.registerProgrammatic(ResizeCell.self, forItemWithIdentifier: .init("probe"))
        collection.autoresizingMask = horizontal ? [.height] : [.width]
        collection.isSelectable = true
        let scroll = NSScrollView(frame: collection.frame)
        // This fixture compares raw document bounds, without the standalone
        // test window's automatic titlebar inset/flow-layout adaptation.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = collection
        scroll.autoresizingMask = [.width, .height]
        let window = NSWindow(contentRect: collection.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: scroll.frame)
        root.addSubview(scroll)
        window.contentView = root
        defer { window.close() }
        collection.reloadData()
        settle(root)
        #expect(!collection.visibleItems().isEmpty)
        let selected: Set<IndexPath> = [IndexPath(item: 0, section: 0)]
        collection.selectionIndexPaths = selected
        for width in [500.0, 900.0, 450.0, 800.0] {
            if afterHiddenResize {
                scroll.isHidden = true
                scroll.autoresizingMask = []
            }
            let frozenSize = scroll.frame.size
            window.setContentSize(CGSize(width: width, height: width * 0.75))
            settle(root)
            if afterHiddenResize {
                #expect(scroll.frame.size == frozenSize)
                scroll.frame = root.bounds
                scroll.isHidden = false
                scroll.autoresizingMask = [.width, .height]
                settle(root)
            }
            if horizontal {
                #expect(abs(collection.bounds.height - scroll.contentSize.height) < 1)
            } else {
                #expect(abs(collection.bounds.width - scroll.contentSize.width) < 1)
            }
            let fresh = kind.make()
            fresh.items = layout.items
            let reference = prepareLayout(fresh, width: collection.bounds.width, height: collection.bounds.height)
            for path in collection.indexPathsForVisibleItems() {
                let item = try #require(collection.item(at: path))
                let expected = try #require(fresh.layoutAttributesForItem(at: path))
                #expect(layout.layoutAttributesForItem(at: path)?.frame == expected.frame)
                #expect(abs(item.view.frame.minX - expected.frame.minX) <= 0.5)
                #expect(abs(item.view.frame.minY - expected.frame.minY) <= 0.5)
                #expect(abs(item.view.frame.width - expected.frame.width) <= 0.5)
                #expect(abs(item.view.frame.height - expected.frame.height) <= 0.5,
                        "windowWidth=\(width) item=\(path.item) actual=\(item.view.frame) expected=\(expected.frame) collection=\(collection.bounds)")
            }
            #expect(collection.selectionIndexPaths == selected)
            #expect(layout.collectionViewContentSize == fresh.collectionViewContentSize)
            withExtendedLifetime(reference) {}
        }
        withExtendedLifetime(source) {}
    }

    private func settle(_ view: NSView) {
        for _ in 0 ..< 4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

@MainActor
private final class ResizeDataSource: NSObject, NSCollectionViewDataSource {
    let count: Int
    init(count: Int) {
        self.count = count
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: .init("probe"), for: indexPath)
    }
}

private final class ResizeCell: NSCollectionViewItem {
    override func loadView() {
        view = NSView()
    }
}
