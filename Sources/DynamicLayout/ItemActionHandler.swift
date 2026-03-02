//
//  ItemActionHandler.swift
//
//
//  Created by Mario Heubach on 02.03.26.
//

import Foundation

/// Callback protocol for item actions that need to be handled by the app layer.
public protocol ItemActionHandler: AnyObject {
    func didRequestDetailPreview(for urls: [URL])
}
