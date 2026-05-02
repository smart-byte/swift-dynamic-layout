//
//  DynamicLayoutState.swift
//
//
//  Created by Codex on 02.05.26.
//

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
