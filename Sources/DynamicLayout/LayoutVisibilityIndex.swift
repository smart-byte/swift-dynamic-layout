import AppKit

/// Narrows viewport queries along the scrolling axis. Prefix maxima preserve
/// tall/wide overlapping items (not just items whose origin is in the viewport).
struct LayoutVisibilityIndex {
    private struct Entry {
        let ordinal: Int
        let start: CGFloat
        let attribute: NSCollectionViewLayoutAttributes
    }

    private let horizontal: Bool
    private let entries: [Entry]
    private let maximumEnds: [CGFloat]

    init(_ attributes: [NSCollectionViewLayoutAttributes], horizontal: Bool = false) {
        self.horizontal = horizontal
        entries = attributes.enumerated().map { offset, attribute in
            Entry(ordinal: offset, start: horizontal ? attribute.frame.minX : attribute.frame.minY, attribute: attribute)
        }.sorted { $0.start < $1.start }
        var maximum = -CGFloat.infinity
        maximumEnds = entries.map { entry in
            maximum = max(maximum, horizontal ? entry.attribute.frame.maxX : entry.attribute.frame.maxY)
            return maximum
        }
    }

    func attributes(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        entries[candidateRange(in: rect)]
            .filter { $0.attribute.frame.intersects(rect) }
            .sorted { $0.ordinal < $1.ordinal }
            .map(\.attribute)
    }

    /// Exposed internally for deterministic work-budget tests, not wall-clock assertions.
    func candidateRange(in rect: NSRect) -> Range<Int> {
        let lower = horizontal ? rect.minX : rect.minY
        let upper = horizontal ? rect.maxX : rect.maxY
        let start = firstIndex { maximumEnds[$0] >= lower }
        let end = firstIndex { entries[$0].start > upper }
        return min(start, end) ..< end
    }

    private func firstIndex(where predicate: (Int) -> Bool) -> Int {
        var low = 0
        var high = entries.count
        while low < high {
            let middle = low + (high - low) / 2
            if predicate(middle) { high = middle } else { low = middle + 1 }
        }
        return low
    }
}
