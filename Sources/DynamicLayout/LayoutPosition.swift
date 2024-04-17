//
//  LayoutPosition.swift
//  
//
//  Created by Mario Heubach on 17.04.24.
//

import SwiftUI

internal struct LayoutPosition {
    var index: Int
    var row: Int
    var column: Int
    var scale: CGFloat

    static let zero = LayoutPosition(index: 0, row: 0, column: 0, scale: 1)
}
