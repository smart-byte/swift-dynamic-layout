//
//  DragSessionState.swift
//
//
//  Created by Codex on 02.05.26.
//

import AppKit

final class DragSessionState {
    private(set) var isCancelled = false
    private var keyMonitor: Any?

    func begin() {
        end()
        isCancelled = false
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // ESC
            self?.isCancelled = true
            Self.cancelActiveDrag()
            return nil
        }
    }

    func end() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isCancelled = false
    }

    private static func cancelActiveDrag() {
        let offScreen = NSPoint(x: -10000, y: -10000)
        guard let up = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: offScreen,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ) else { return }
        NSApp.postEvent(up, atStart: true)
    }
}
