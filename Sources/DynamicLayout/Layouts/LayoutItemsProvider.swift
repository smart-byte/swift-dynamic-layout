//
//  LayoutItemsProvider.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import AppKit

/// Protocol for layouts that manage a list of geometry-only frame items.
/// Allows FileCollectionView to update items generically without
/// type-casting to each concrete layout.
public protocol LayoutItemsProvider: AnyObject {
    var items: [LayoutItemFrame] { get set }
}

public extension LayoutItemsProvider {
    func setItems(_ newItems: [LayoutItemFrame]) {
        items = newItems
    }
}
