//
//  AutoScrollView.swift
//
//
//  Created by Mario Heubach on 01.03.26.
//

import AppKit

/// NSScrollView subclass that redirects vertical scroll to horizontal
/// when the content only scrolls horizontally.
class AutoScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard let documentView else {
            super.scrollWheel(with: event)
            return
        }

        let canScrollHorizontally = documentView.frame.width > contentView.bounds.width
        let canScrollVertically = documentView.frame.height > contentView.bounds.height

        if canScrollHorizontally, !canScrollVertically {
            guard let cgEvent = event.cgEvent?.copy() else {
                super.scrollWheel(with: event)
                return
            }
            redirectVerticalToHorizontal(cgEvent)
            guard let modified = NSEvent(cgEvent: cgEvent) else {
                super.scrollWheel(with: event)
                return
            }
            super.scrollWheel(with: modified)
        } else {
            super.scrollWheel(with: event)
        }
    }

    private func redirectVerticalToHorizontal(_ cgEvent: CGEvent) {
        let lineY = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let lineX = cgEvent.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lineX + lineY)

        let pointY = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let pointX = cgEvent.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointX + pointY)

        let fixedY = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixedX = cgEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        cgEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedX + fixedY)
    }
}
