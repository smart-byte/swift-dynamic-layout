//
//  DropHandling.swift
//
//
//  Created by Mario Heubach on 06.05.26.
//

import AppKit

/// Validates a dragging operation and returns the proposed `NSDragOperation`.
/// The host app provides an implementation backed by `FileDropPerformer` or
/// equivalent logic. Returning `[]` shows the not-allowed drag cursor.
public typealias DropValidator = (NSDraggingInfo, URL?) -> NSDragOperation

/// Executes the actual file-system drop after the user releases the mouse.
/// Returns `true` if at least one URL was processed successfully.
public typealias DropPerformer = (NSDraggingInfo, URL?) -> Bool
