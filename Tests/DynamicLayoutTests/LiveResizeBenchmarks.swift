import AppKit
@testable import DynamicLayout
import XCTest

/// A repeatable layout microbenchmark, not an end-to-end window/FPS measurement.
@MainActor
final class LiveResizeBenchmarks: XCTestCase {
    func testWaterfallResizeWorkload() {
        let layout = WaterfallLayout()
        layout.items = (0 ..< 10000).map { index in
            LayoutItemFrame(size: CGSize(width: 100 + index % 7 * 25, height: 100))
        }
        let collection = prepareLayout(layout, width: 800, height: 700)
        measure {
            for step in 0 ..< 12 {
                collection.frame.size.width = CGFloat(800 + step * 8)
                layout.prepare()
                _ = layout.layoutAttributesForElements(in: NSRect(x: 0, y: 1000, width: 1000, height: 700))
                // AppKit can request preparation again without any input change.
                layout.prepare()
            }
        }
        withExtendedLifetime(collection) {}
    }
}
