//
//  DynamicLayoutItem.swift
//
//
//  Created by Mario Heubach on 17.04.24.
//

import SwiftUI

public struct DynamicLayoutItem: Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public var image: NSImage?
    public let size: CGSize
    public var frame: CGRect
    public var rotation: CGFloat
    public let aspectRatio: CGFloat
    public var isSelected: Bool

    // File metadata for list view
    public var fileSize: Int64
    public var modificationDate: Date?
    public var fileKind: String

    public init(
        id: UUID = UUID(),
        url: URL,
        size: CGSize,
        frame: CGRect = .zero,
        rotation: CGFloat = 0,
        fileSize: Int64 = 0,
        modificationDate: Date? = nil,
        fileKind: String = ""
    ) {
        self.id = id
        self.url = url
        self.size = size
        aspectRatio = size.height > 0 ? size.width / size.height : 1.0
        isSelected = false
        self.frame = frame
        self.rotation = rotation
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileKind = fileKind
    }

    public static func == (lhs: DynamicLayoutItem, rhs: DynamicLayoutItem) -> Bool {
        lhs.id == rhs.id
    }
}
