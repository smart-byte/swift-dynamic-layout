import AppKit

/// Tracks scalar geometry inputs without hashing every item on each prepare pass.
/// Layouts invalidate this state whenever their item array is assigned or mutated.
struct LayoutPreparationState {
    private var parameters: [CGFloat]?

    mutating func invalidate() {
        parameters = nil
    }

    mutating func needsPreparation(_ parameters: [CGFloat]) -> Bool {
        guard self.parameters != parameters else { return false }
        self.parameters = parameters
        return true
    }
}

extension [NSCollectionViewLayoutAttributes] {
    /// Preserve attribute objects while resizing; batch animation snapshots are
    /// independent copies owned by each layout's oldCache.
    mutating func resizeForItemCount(_ count: Int) {
        if self.count > count {
            removeLast(self.count - count)
        }
        while self.count < count {
            append(NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: self.count, section: 0)))
        }
    }
}
