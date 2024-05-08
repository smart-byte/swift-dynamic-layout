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
    public let aspectRatio: CGFloat
    public var isSelected: Bool

    var layoutPosition: LayoutPosition

    public init(id: UUID = UUID(), url: URL, size: CGSize ) {
        self.id = id
        self.url = url
        self.size = size
        self.aspectRatio = size.width / size.height
        self.layoutPosition = .zero
        self.isSelected = false
    }

    public func sizeToFit( height: CGFloat ) -> CGSize {
        CGSize(
            width: height * aspectRatio * layoutPosition.scale,
            height: height * layoutPosition.scale
        )
    }

    public static func == (lhs: DynamicLayoutItem, rhs: DynamicLayoutItem) -> Bool {
        lhs.id == rhs.id
    }
}


