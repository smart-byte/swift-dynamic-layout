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
        collectionView.registerForDraggedTypes([.string])
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
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString( "\(indexPath.item)", forType: .string)
        return pasteboardItem
    }

    public func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath indexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        proposedDropOperation.pointee = .before
        return .move
    }

    public func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {

        guard let itemIndexString = info.draggingPasteboard.string(forType: .string),
              let itemIndex = Int(itemIndexString) else {
            return false
        }

        let item = layoutItems.remove(at: itemIndex)
        layoutItems.insert(item, at: indexPath.item)

        updateRowScaling()

        collectionView.animator().moveItem(at: IndexPath(item: itemIndex, section: 0), to: indexPath)

        return true
    }
}

extension CGSize {
    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        return CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}
