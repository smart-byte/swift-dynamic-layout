//
//  LayoutItemFrame.swift
//
//
//  Created by Mario Heubach on 06.05.26.
//

import CoreGraphics
import Foundation

/// Geometry-only item descriptor consumed by the layout-pass algorithms.
///
/// Layout subclasses (`WaterfallLayout`, `JustifiedLayout`, …) need only
/// `size` (and the derived `aspectRatio`) when running `prepare()`. Keeping
/// this struct at 32 B (16 B UUID + 16 B CGSize) vs the old `DynamicLayoutItem`
/// at ~200 B (URL heap-pointer + String + Int64 + Date) gives a ~6× smaller
/// cache-line footprint for the O(N) layout pass over large folders.
///
/// The host app (Voila) keeps a richer `FileLayoutItem` (with `url`,
/// `fileSize`, `modificationDate`, `fileKind`) and projects it to
/// `LayoutItemFrame` via `FileLayoutItem.asFrame` before handing the array
/// to `FileCollectionView`. Item identity (UUID) is shared, so the Coordinator
/// can resolve a frame back to its `FileLayoutItem` by matching `id`.
public struct LayoutItemFrame: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let size: CGSize

    /// Aspect ratio (width / height). Returns 1.0 for zero-height items so
    /// layout algorithms never divide by zero.
    public var aspectRatio: CGFloat {
        size.height > 0 ? size.width / size.height : 1.0
    }

    public init(id: UUID = UUID(), size: CGSize) {
        self.id = id
        self.size = size
    }
}
