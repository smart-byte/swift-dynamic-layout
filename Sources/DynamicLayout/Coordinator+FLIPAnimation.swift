//
//  Coordinator+FLIPAnimation.swift
//
//
//  Created by Mario Heubach on 06.03.26.
//

import AppKit

// MARK: - FLIP Animation Helpers

extension Coordinator {
    /// Captures the current frame of each visible item, keyed by item ID.
    func captureVisibleItemFrames(_ collectionView: NSCollectionView) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        for ip in collectionView.indexPathsForVisibleItems() {
            guard ip.item < parent.layoutItems.count,
                  let item = collectionView.item(at: ip)
            else { continue }
            frames[parent.layoutItems[ip.item].id] = item.view.frame
        }
        return frames
    }

    /// Animates visible items from their old frames to their current (new) positions.
    /// Items that weren't visible before get a short fade-in.
    func animateFromOldFrames(
        _ oldFrames: [UUID: CGRect],
        in collectionView: NSCollectionView,
        duration: TimeInterval = 0.25
    ) {
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        for ip in collectionView.indexPathsForVisibleItems() {
            guard ip.item < parent.layoutItems.count,
                  let viewItem = collectionView.item(at: ip),
                  let layer = viewItem.view.layer
            else { continue }
            let itemID = parent.layoutItems[ip.item].id
            guard let oldFrame = oldFrames[itemID] else {
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 0.0
                anim.duration = duration * 0.5
                layer.add(anim, forKey: "flipFadeIn")
                continue
            }

            let newPos = layer.position
            let oldPos = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
            if oldPos != newPos {
                let anim = CABasicAnimation(keyPath: "position")
                anim.fromValue = oldPos
                anim.duration = duration
                anim.timingFunction = timing
                layer.add(anim, forKey: "flipPos")
            }

            if oldFrame.size != layer.bounds.size {
                let anim = CABasicAnimation(keyPath: "bounds.size")
                anim.fromValue = oldFrame.size
                anim.duration = duration
                anim.timingFunction = timing
                layer.add(anim, forKey: "flipSize")
            }
        }
    }

    /// Variant used by `handleInternalDrop`: works off CALayer position
    /// + bounds snapshots (taken before `reloadData()`) instead of view
    /// frames (which `reloadData` resets). Async-after-completion clears
    /// the drag/processing state so the next `updateNSView` can run.
    func animateReorder(
        collectionView: NSCollectionView,
        oldPositions: [UUID: CGPoint],
        oldBounds: [UUID: CGRect]
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let duration = 0.25
            let timing = CAMediaTimingFunction(name: .easeInEaseOut)

            for ip in collectionView.indexPathsForVisibleItems() {
                guard ip.item < parent.layoutItems.count,
                      let viewItem = collectionView.item(at: ip),
                      let layer = viewItem.view.layer
                else { continue }

                let itemID = parent.layoutItems[ip.item].id
                guard let oldPos = oldPositions[itemID] else { continue }

                if oldPos != layer.position {
                    let anim = CABasicAnimation(keyPath: "position")
                    anim.fromValue = oldPos
                    anim.duration = duration
                    anim.timingFunction = timing
                    layer.add(anim, forKey: "reorderPos")
                }

                if let oldFrame = oldBounds[itemID],
                   oldFrame.size != layer.bounds.size
                {
                    let anim = CABasicAnimation(keyPath: "bounds")
                    anim.fromValue = oldFrame
                    anim.duration = duration
                    anim.timingFunction = timing
                    layer.add(anim, forKey: "reorderBounds")
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                self.isProcessingDrop = false
                self.isDragging = false
                self.draggedIndexPaths = []
            }
        }
    }
}
