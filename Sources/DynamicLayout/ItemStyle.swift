//
//  ItemStyle.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

/// Visual presentation style for collection view items.
public enum ItemStyle: String, CaseIterable, Hashable {
    case photoFrame
    case contactSheet
    case borderless

    public var name: String {
        switch self {
        case .photoFrame: "Photo Frame"
        case .contactSheet: "Contact Sheet"
        case .borderless: "Borderless"
        }
    }

    public var icon: String {
        switch self {
        case .photoFrame: "photo.on.rectangle"
        case .contactSheet: "rectangle.grid.2x2"
        case .borderless: "rectangle"
        }
    }
}
