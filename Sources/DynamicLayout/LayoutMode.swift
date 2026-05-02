//
//  LayoutMode.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

/// Single enum for all layout modes. Pinboard is NOT a layout mode —
/// it's a separate system.
public enum LayoutMode: String, CaseIterable, Hashable, Codable, Sendable {
    case list
    case verticalFlow
    case waterfall
    case horizontalFlow
    case justified
    case horizontalJustified

    /// Layouts available in the toolbar picker.
    public static let pickerCases: [LayoutMode] = [
        .list, .justified, .horizontalJustified, .horizontalFlow,
    ]

    /// Default item style for each layout.
    public var defaultItemStyle: ItemStyle {
        switch self {
        case .waterfall: .photoFrame
        case .horizontalFlow, .verticalFlow: .borderless
        default: .tile
        }
    }

    public var name: String {
        switch self {
        case .list: "List"
        case .verticalFlow: "Vertical Flow"
        case .waterfall: "Waterfall"
        case .horizontalFlow: "Horizontal Flow"
        case .justified: "Justified"
        case .horizontalJustified: "Horizontal Justified"
        }
    }

    public var icon: String {
        switch self {
        case .list: "list.bullet.rectangle.fill"
        case .verticalFlow: "rectangle.split.1x2.fill"
        case .waterfall: "rectangle.grid.3x2.fill"
        case .horizontalFlow: "rectangle.split.3x1.fill"
        case .justified: "square.grid.2x2.fill"
        case .horizontalJustified: "rectangle.split.2x1.fill"
        }
    }
}
