//
//  LayoutItemsProvider.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import AppKit

/// Protocol for layouts that manage a list of items.
/// Allows FileCollectionView to update items generically without
/// type-casting to each concrete layout.
public protocol LayoutItemsProvider: AnyObject {
    var items: [DynamicLayoutItem] { get set }
}

public extension LayoutItemsProvider {
    func setItems(_ newItems: [DynamicLayoutItem]) {
        items = newItems
    }
}
