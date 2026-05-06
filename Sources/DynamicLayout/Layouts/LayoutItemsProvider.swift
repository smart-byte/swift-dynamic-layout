//
//  LayoutItemsProvider.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import AppKit

/// Protocol for layouts that manage a list of geometry-only frame items.
/// Allows CollectionLayoutView to update items generically without
/// type-casting to each concrete layout.
///
/// Internal to the package — external callers configure layouts through
/// CollectionLayoutView's bindings, not by casting to this protocol directly.
protocol LayoutItemsProvider: AnyObject {
    var items: [LayoutItemFrame] { get set }
}

extension LayoutItemsProvider {
    func setItems(_ newItems: [LayoutItemFrame]) {
        items = newItems
    }
}
