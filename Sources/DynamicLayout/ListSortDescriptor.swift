//
//  ListSortDescriptor.swift
//  DynamicLayout
//

import Foundation

/// Persistable description of a `FileListView` column sort. Mirrors the
/// data of `NSSortDescriptor` but in a Codable, Sendable shape so the
/// host app can store it in user-storage and replay it after a tab
/// switch, app restart, or folder reload.
///
/// The `key` matches the column identifier strings that
/// `FileListView` sets up internally: `"name"`, `"date"`, `"size"`,
/// `"kind"`. Anything else is treated as "no sort" by the coordinator.
public struct ListSortDescriptor: Codable, Hashable, Sendable {
    public let key: String
    public let ascending: Bool

    public init(key: String, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }
}
