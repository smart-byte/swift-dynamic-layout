import Foundation

/// Hosts may supply a new identity whenever items or geometry change. Selection
/// and toolbar updates then avoid hashing the entire collection again.
struct ItemsSnapshotCache {
    private var revision: UUID?
    private var snapshot: DynamicLayoutItemsSnapshot?

    mutating func resolve(revision: UUID?, items: () -> [LayoutItemFrame]) -> DynamicLayoutItemsSnapshot {
        if let revision, revision == self.revision, let snapshot { return snapshot }
        let next = DynamicLayoutItemsSnapshot(items: items())
        self.revision = revision
        snapshot = next
        return next
    }
}
