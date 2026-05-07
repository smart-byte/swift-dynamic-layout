//
//  ItemStyle.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

/// Visual presentation style for collection view items.
public enum ItemStyle: String, CaseIterable, Hashable, Sendable {
    case photoFrame
    case tile
    case borderless

    public var name: String {
        switch self {
        case .photoFrame: "Photo Frame"
        case .tile: "Tile"
        case .borderless: "Borderless"
        }
    }

    public var icon: String {
        switch self {
        case .photoFrame: "photo.on.rectangle"
        case .tile: "app"
        case .borderless: "rectangle"
        }
    }

    /// Whether a layout using this item style wants the filename
    /// rendered next to the icon in the *flying* drag preview when it
    /// acts as a drop target. Borderless deliberately strips chrome
    /// down to the bare image, so when the cursor enters a borderless
    /// target the preview drops the capsule too. Other styles already
    /// surface the filename in their cells; the preview keeps it for
    /// continuity. Source-side preview (the cell snapshot at drag
    /// start) is unaffected — this only drives the target-adapted
    /// rendering during the drag session.
    public var dragShowsLabel: Bool {
        switch self {
        case .borderless: false
        case .photoFrame, .tile: true
        }
    }
}

extension ItemStyle: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Legacy raw value from the previous "Contact Sheet" naming —
        // accept on decode so existing UserStorage entries keep working.
        if raw == "contactSheet" {
            self = .tile
            return
        }
        guard let value = ItemStyle(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ItemStyle raw value: \(raw)"
            )
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
