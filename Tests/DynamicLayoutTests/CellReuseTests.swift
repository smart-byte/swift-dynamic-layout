import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct CellReuseTests {
    /// Scrolling through the whole content must dequeue cells, not build one per item.
    @Test func scrollingReusesCellsInsteadOfCreatingNewOnes() throws {
        let layout = WaterfallLayout()
        layout.columns = 4
        layout.items = makeItems(aspectRatios: Array(repeating: 1, count: 400))
        let source = ProbeDataSource(count: layout.items.count)
        let collection = NiblessCollectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        collection.collectionViewLayout = layout
        collection.dataSource = source
        CountingCell.instances = 0
        collection.registerProgrammatic(CountingCell.self, forItemWithIdentifier: .init("probe"))
        let scroll = NSScrollView(frame: collection.frame)
        scroll.documentView = collection
        let window = NSWindow(contentRect: collection.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }

        collection.reloadData()
        settle(scroll)
        let visible = collection.visibleItems().count
        #expect(visible > 0)

        var offset: CGFloat = 0
        while offset < layout.collectionViewContentSize.height {
            offset += 300
            scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle(scroll)
        }
        #expect(CountingCell.instances < layout.items.count)
        #expect(CountingCell.instances <= visible * 3)
    }

    @Test func hoverFollowsTheCellUnderTheCursor() throws {
        let layout = WaterfallLayout()
        layout.columns = 3
        layout.items = makeItems(aspectRatios: Array(repeating: 1, count: 12))
        let source = ThumbnailDataSource(count: layout.items.count)
        let collection = NiblessCollectionView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        collection.collectionViewLayout = layout
        collection.dataSource = source
        collection.registerProgrammatic(ThumbnailItem.self, forItemWithIdentifier: ThumbnailDataSource.identifier)
        let scroll = NSScrollView(frame: collection.frame)
        scroll.documentView = collection
        let window = NSWindow(contentRect: collection.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        defer { window.close() }

        collection.reloadData()
        settle(scroll)
        let first = try #require(collection.item(at: IndexPath(item: 0, section: 0)) as? ThumbnailItem)
        let second = try #require(collection.item(at: IndexPath(item: 1, section: 0)) as? ThumbnailItem)
        let firstFrame = collection.frameForItem(at: 0)
        let secondFrame = collection.frameForItem(at: 1)

        collection.updateHover(at: NSPoint(x: firstFrame.midX, y: firstFrame.midY))
        #expect(first.isHovered)
        #expect(!second.isHovered)

        collection.updateHover(at: NSPoint(x: secondFrame.midX, y: secondFrame.midY))
        #expect(!first.isHovered)
        #expect(second.isHovered)

        collection.updateHover(at: NSPoint(x: -50, y: -50))
        #expect(!second.isHovered)
    }

    private func settle(_ view: NSView) {
        for _ in 0 ..< 4 {
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

@MainActor
private final class ProbeDataSource: NSObject, NSCollectionViewDataSource {
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

@MainActor
private final class ThumbnailDataSource: NSObject, NSCollectionViewDataSource {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem.tile")
    let count: Int
    init(count: Int) {
        self.count = count
    }

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.identifier, for: indexPath)
        (item as? ThumbnailItem)?.itemStyle = .tile
        return item
    }
}

@MainActor
private final class CountingCell: NSCollectionViewItem {
    static var instances = 0

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        CountingCell.instances += 1
        super.init(nibName: nibName, bundle: bundle)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()
    }
}
