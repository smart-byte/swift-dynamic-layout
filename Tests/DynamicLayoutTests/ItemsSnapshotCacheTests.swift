@testable import DynamicLayout
import Foundation
import Testing

struct ItemsSnapshotCacheTests {
    @Test func unchangedRevisionDoesNotReadItems() {
        var cache = ItemsSnapshotCache()
        let revision = UUID()
        let items = (0 ..< 10000).map { _ in LayoutItemFrame(id: UUID(), size: CGSize(width: 100, height: 100)) }
        let initial = cache.resolve(revision: revision) { items }
        var reads = 0
        for _ in 0 ..< 100 {
            #expect(cache.resolve(revision: revision) {
                reads += 1
                return items
            } == initial)
        }
        #expect(reads == 0)
    }

    @Test func geometryChangesAreDetectedWithoutChangingIDs() {
        var cache = ItemsSnapshotCache()
        let id = UUID()
        let initial = cache.resolve(revision: UUID()) {
            [LayoutItemFrame(id: id, size: CGSize(width: 100, height: 100))]
        }
        let updated = cache.resolve(revision: UUID()) {
            [LayoutItemFrame(id: id, size: CGSize(width: 400, height: 100))]
        }
        #expect(initial != updated)
    }

    @Test func hostsWithoutRevisionStillDetectGeometryChanges() {
        var cache = ItemsSnapshotCache()
        let id = UUID()
        let initial = cache.resolve(revision: nil) {
            [LayoutItemFrame(id: id, size: CGSize(width: 100, height: 100))]
        }
        let updated = cache.resolve(revision: nil) {
            [LayoutItemFrame(id: id, size: CGSize(width: 100, height: 400))]
        }
        #expect(initial != updated)
    }
}
