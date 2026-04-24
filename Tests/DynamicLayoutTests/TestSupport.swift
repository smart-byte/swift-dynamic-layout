//
//  TestSupport.swift
//  DynamicLayoutTests
//
//  Shared helpers for layout algorithm tests.
//

import AppKit
@testable import DynamicLayout
import Foundation

/// Builds an array of `DynamicLayoutItem` for testing. Each item's size is
/// synthesized from the given aspect ratio (width / height) by using a
/// fixed height of 100 and computing width accordingly.
func makeItems(aspectRatios: [CGFloat]) -> [DynamicLayoutItem] {
    aspectRatios.enumerated().map { index, ratio in
        let height: CGFloat = 100
        let width = height * ratio
        return DynamicLayoutItem(
            url: URL(fileURLWithPath: "/tmp/voila-test-item-\(index)"),
            size: CGSize(width: width, height: height)
        )
    }
}

/// Attaches the given layout to an in-memory `NSCollectionView` with the
/// supplied viewport bounds and triggers `prepare()`. No window, no
/// rendering — pure in-process setup so tests stay unit-test-fast.
///
/// The returned collection view MUST be held by the caller for the duration
/// of the assertions: `NSCollectionViewLayout.collectionView` is a weak
/// reference, and `collectionViewContentSize` reads its bounds.
func prepareLayout(_ layout: NSCollectionViewLayout, width: CGFloat, height: CGFloat) -> NSCollectionView {
    let cv = NSCollectionView()
    cv.frame = CGRect(x: 0, y: 0, width: width, height: height)
    cv.collectionViewLayout = layout
    layout.prepare()
    return cv
}
