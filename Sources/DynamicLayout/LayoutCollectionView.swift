//
//  DynamicLayoutView.swift
//  DynamicLayout
//
//  Created by Mario Heubach on 23.02.24.
//

import AppKit
import SwiftUI

public class LayoutCollectionView: NSScrollView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelectionChange: ((Set<IndexPath>) -> Void) = { _ in }

    var collectionView: NSCollectionView!

    var layoutItems: [DynamicLayoutItem] = [] {
        didSet {
            collectionView.reloadData()
        }
    }

    var rowHeight: CGFloat = 150
    {
        willSet(newValue) {
            if newValue != rowHeight {
                updateRowScaling()
            }
        }
    }

    var cellSpacing: CGFloat = 10 {
        didSet {
            updateRowScaling()
        }
    }

    var wrapItems: Bool = false
    {
        didSet {
            updateRowScaling()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCollectionView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCollectionView()
    }

    func setupCollectionView() {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        applyCellSpacing(layout: layout )

        collectionView = NSCollectionView(frame: self.bounds)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.delegate = self
        collectionView.dataSource = self

        collectionView.register(
            LayoutCollectionViewItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(
                rawValue: "CustomCollectionViewItem"
            )
        )

        self.documentView = collectionView
    }

    func animate( completion: ((Bool) -> Void)? = nil ) {
        collectionView.animator().performBatchUpdates({
            collectionView.collectionViewLayout?.invalidateLayout()
        }, completionHandler: completion )
    }

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)

        if wrapItems && frame.width != oldSize.width {
            let factor = frame.width / oldSize.width
            rowHeight *= factor
        }

        updateRowScaling()
    }

    private func updateRowScaling() {
        updateRowScaling(maxRowHeight: rowHeight )
    }

    private func updateRowScaling(maxRowHeight: CGFloat) {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else {
            return
        }

        applyCellSpacing(layout: layout )

        let availableWidth = collectionView.bounds.width - layout.sectionInset.left - layout.sectionInset.right
        var totalRowWidth: CGFloat = 0
        var currentRow: Int = 0
        var rowItemIndices: [Int] = []

        for index in layoutItems.indices {
            let itemSize = CGSize(
                width: maxRowHeight * layoutItems[index].aspectRatio,
                height: maxRowHeight
            )

            let newTotalRowWidth = totalRowWidth + itemSize.width + (rowItemIndices.isEmpty ? 0 : layout.minimumInteritemSpacing)

            if newTotalRowWidth > availableWidth {
                if !rowItemIndices.isEmpty {
                    applyScaling(to: rowItemIndices, with: availableWidth / totalRowWidth)
                }

                currentRow += 1
                rowItemIndices.removeAll()
                totalRowWidth = 0
            }

            totalRowWidth += itemSize.width + (rowItemIndices.isEmpty ? 0 : layout.minimumInteritemSpacing)
            rowItemIndices.append(index)
            layoutItems[index].layoutPosition.row = currentRow
        }

        if !rowItemIndices.isEmpty {
            applyScaling(to: rowItemIndices, with: min(1, availableWidth / totalRowWidth))
        }
    }

    private func updateRowScaling( minRowHeight: CGFloat ) {
        guard let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else {
            return
        }

        let availableWidth = collectionView.bounds.width - layout.sectionInset.left - layout.sectionInset.right
        var totalRowWidth: CGFloat = 0
        var currentRow: Int = 0

        var rowItemIndices: [Int] = []

        for index in layoutItems.indices {
            let itemSize = CGSize(
                width: minRowHeight * layoutItems[index].aspectRatio,
                height: minRowHeight
            )

            if totalRowWidth + itemSize.width + layout.minimumInteritemSpacing <= availableWidth {
                totalRowWidth += itemSize.width + (rowItemIndices.isEmpty ? 0 : layout.minimumInteritemSpacing)
                rowItemIndices.append(index)
            } else {
                applyScaling( to: rowItemIndices, with: availableWidth / totalRowWidth )

                currentRow += 1
                totalRowWidth = itemSize.width
                rowItemIndices.removeAll()
                rowItemIndices.append(index)
            }

            layoutItems[index].layoutPosition.row = currentRow
        }

        if !rowItemIndices.isEmpty {
            applyScaling( to: rowItemIndices, with: min( 1 , availableWidth / totalRowWidth ) )
        }
    }

    private func applyCellSpacing( layout: NSCollectionViewFlowLayout ) {
        layout.minimumLineSpacing = rowHeight / cellSpacing
        layout.minimumInteritemSpacing = rowHeight / cellSpacing / 3 * 2
    }

    private func applyScaling(to rowItemIndices: [Int], with rowScale: CGFloat ) {
        for rowItemIndex in rowItemIndices {
            layoutItems[rowItemIndex].layoutPosition.scale = rowScale
        }
    }
}

extension LayoutCollectionView: NSCollectionViewDelegateFlowLayout {
    public func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        layoutItems[indexPath.item].sizeToFit( height: rowHeight )
    }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return layoutItems.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("CustomCollectionViewItem"), for: indexPath) as! LayoutCollectionViewItem
        let layoutItem = layoutItems[indexPath.item]
        item.configure(with: layoutItem)
        return item
    }

    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        onSelectionChange( indexPaths )
    }

    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        onSelectionChange( indexPaths )
    }

    public func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        return true
    }

    public func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let item = layoutItems[indexPath.item]
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .string)
        pasteboardItem.setData(item.url.dataRepresentation, forType: .fileURL)
        return item.url as NSPasteboardWriting
    }

    public func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath indexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        proposedDropOperation.pointee = .before

        if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
            return .copy
        } else if info.draggingSource as? NSCollectionView == collectionView {
            return .move
        } else {
            return .every
        }
    }

    public func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        // Füge hier deine Logik hinzu, um die URLs zu verarbeiten
        
        return urls != nil

        //        guard let itemIndexUrl = info.draggingPasteboard.data(forType: .fileURL),
        //              let itemUrl = URL(dataRepresentation: itemIndexUrl, relativeTo: nil)
        //        else {
        //            return false
        //        }
        //
        //        let itemIndex = layoutItems.firstIndex(where: { $0.url == itemUrl })!
        //        let item = layoutItems.remove(at: itemIndex)
        //        layoutItems.insert(item, at: indexPath.item)
        //
        //        updateRowScaling()
        //
        //        collectionView.moveItem(at: IndexPath(item: itemIndex, section: 0), to: indexPath)

     //   return true
    }
}

extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
