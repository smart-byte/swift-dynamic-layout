//
//  DynamicLayoutState.swift
//
//
//  Created by Codex on 02.05.26.
//

import CoreGraphics
import Foundation

struct DynamicLayoutItemsSnapshot: Equatable {
    let count: Int
    let firstID: UUID?
    let lastID: UUID?
    let orderSignature: Int

    init(items: [DynamicLayoutItem]) {
        count = items.count
        firstID = items.first?.id
        lastID = items.last?.id

        var hasher = Hasher()
        hasher.combine(count)
        for item in items {
            hasher.combine(item.id)
        }
        orderSignature = hasher.finalize()
    }
}

func sanitizedSelection(
    _ selection: Set<IndexPath>,
    itemCount: Int
) -> Set<IndexPath> {
    selection.filter { indexPath in
        indexPath.section == 0 && indexPath.item >= 0 && indexPath.item < itemCount
    }
}

/// Effective aspect ratio for a layout cell — the item's image aspect,
/// or 1:1 when the host layout is in square-cells mode (driven by the
/// `.tile` item style). Shared by `JustifiedLayout` and
/// `HorizontalJustifiedLayout`.
func effectiveAspect(for item: DynamicLayoutItem, useSquareCells: Bool) -> CGFloat {
    useSquareCells ? 1.0 : item.aspectRatio
}
