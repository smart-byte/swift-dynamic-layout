//
//  DynamicLayoutItem.swift
//
//
//  Created by Mario Heubach on 17.04.24.
//

import SwiftUI

public struct DynamicLayoutItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let size: CGSize
    public let aspectRatio: CGFloat

    // File metadata for list view
    public var fileSize: Int64
    public var modificationDate: Date?
    public var fileKind: String

    public init(
        id: UUID = UUID(),
        url: URL,
        size: CGSize,
        fileSize: Int64 = 0,
        modificationDate: Date? = nil,
        fileKind: String = ""
    ) {
        self.id = id
        self.url = url
        self.size = size
        aspectRatio = size.height > 0 ? size.width / size.height : 1.0
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileKind = fileKind
    }

    public static func == (lhs: DynamicLayoutItem, rhs: DynamicLayoutItem) -> Bool {
        lhs.id == rhs.id
    }
}
