//
//  FileCollectionView.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import SwiftUI
import AppKit

public enum LayoutItemType {
    case thumbnail
    case contactSheet
}

public struct FileCollectionView: NSViewRepresentable, Equatable {
    @Binding var layoutItems: [DynamicLayoutItem]
    @Binding var selection: Set<IndexPath>
    @Binding var layoutItemType: LayoutItemType
    @Binding var itemSpacing: CGFloat
    @Binding var columns: Int

    var collectionView = NSCollectionView()

    public init(
        layoutItems: Binding<[DynamicLayoutItem]>,
        selection: Binding<Set<IndexPath>> = .constant([]),
        layoutItemType: Binding<LayoutItemType>,
        itemSpacing: Binding<CGFloat>,
        Columns: Binding<Int> = .constant(5)
    ) {
        _layoutItems = layoutItems
        _selection = selection
        _layoutItemType = layoutItemType
        _itemSpacing = itemSpacing
        _columns = Columns
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let layout = MasonryLayout() // ContactSheetLayout() // HorizontalFlowLayout() // ContactSheetLayout()

        layout.items = layoutItems
        layout.columns = columns
        layout.spacingPercentage = itemSpacing
        layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let collectionView = NSCollectionView()
        collectionView.registerForDraggedTypes([.fileURL ])
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            ThumbnailItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(
                rawValue: "ThumbnailItem"
            )
        )
        collectionView.register(
            ContactSheetItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(
                rawValue: "ContactSheetItem"
            )
        )
        collectionView.selectionIndexPaths = selection

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let collectionView = nsView.documentView as? NSCollectionView else { return }

        collectionView.reloadData()

        if let layout = collectionView.collectionViewLayout as? MasonryLayout {
            layout.spacingPercentage = itemSpacing
            layout.items = layoutItems
        } else if let layout = collectionView.collectionViewLayout as? ContactSheetLayout {
            layout.spacingPercentage = itemSpacing
            //layout.items = layoutItems
        }

    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public static func == (lhs: FileCollectionView, rhs: FileCollectionView) -> Bool {
        lhs.layoutItems == rhs.layoutItems && lhs.selection == rhs.selection
    }
}

public class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var parent: FileCollectionView
    var selection: Set<IndexPath> = []

    init(_ parent: FileCollectionView) {
        self.parent = parent
    }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return parent.layoutItems.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let identifier: NSUserInterfaceItemIdentifier
        let layoutItem = parent.layoutItems[indexPath.item]

        if parent.layoutItemType == .thumbnail {
            identifier = NSUserInterfaceItemIdentifier(rawValue: "ThumbnailItem" )
            let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath) as! ThumbnailItem
            item.configure(with: layoutItem.url)
            return item
        }

        identifier = NSUserInterfaceItemIdentifier(rawValue: "ContactSheetItem" )
        let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath) as! ContactSheetItem
        item.configure(with: layoutItem.url)

        return item
    }

    public func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        selection.formUnion( indexPaths )
    }

    public func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        selection.subtract( indexPaths )
    }

    public func collectionView(_ collectionView: NSCollectionView, draggingImageForItemsAt indexPaths: Set<IndexPath>, with event: NSEvent, offset: NSPointPointer) -> NSImage {
        let image = NSImage(size: NSSize(width: 100, height: 100))

        return image
    }

    public func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {

        let url = parent.layoutItems[indexPath.item].url
        //        guard let layoutItem = collectionView.item(at: indexPath) as? LayoutItem else {
        //            return nil
        //        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(url.absoluteString, forType: .fileURL)
        pasteboardItem.setString(url.lastPathComponent, forType: .string )
        return pasteboardItem
    }

    public func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {

        let urls = indexPaths.compactMap { indexPath -> URL? in
            return parent.layoutItems[indexPath.item].url
        }
        session.draggingPasteboard.writeObjects(urls as [NSPasteboardWriting])
        session.draggingFormation = .default
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    public func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    public func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        //        let pasteboard = info.draggingPasteboard

        //        guard let layoutItems = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
        //            return false
        //        }
        //
        //        let index = indexPath.item
        //       // let layoutItem = parent.layoutItems[indexPath.item]
        //
        //        for layoutItem in layoutItems {
        //            if let index = parent.layoutItems.firstIndex(of: layoutItem) {
        //                parent.layoutItems.remove(at: index)
        //                parent.layoutItems.insert(layoutItem, at: index)
        //                collectionView.animator().moveItem(at: IndexPath(item: index, section: 0), to: IndexPath(item: index, section: 0))
        //            } else {
        //                parent.fileURLs.insert(url, at: index)
        //            }
        //        }

        return true
    }


    //    public func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, index: Int, dropOperation: NSCollectionView.DropOperation) -> Bool {
    //        let pasteboard = draggingInfo.draggingPasteboard
    //
    //        guard let itemIndexUrl = pasteboard.data(forType: .fileURL),
    //              let itemUrl = URL(dataRepresentation: itemIndexUrl, relativeTo: nil)
    //        else {
    //            print("Fehler beim Ziehen")
    //            return false
    //        }
    //
    //        if let itemIndex = parent.fileURLs.firstIndex(of: itemUrl) {
    //            let item = parent.fileURLs.remove(at: itemIndex)
    //            parent.fileURLs.insert(item, at: index )
    //
    //            //collectionView.animator().moveItem(at: itemIndex, to: itemIndex)
    //        } else {
    //            parent.fileURLs.insert(itemUrl, at: index)
    //        }
    //
    //        return true
    //    }

    //    public func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath indexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
    //
    //        proposedDropOperation.pointee = .on

    //        if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
    //            return .copy
    //        } else if info.draggingSource as? NSCollectionView == collectionView {
    //            return .move
    //        } else {
    //            return .generic
    //        }
    //    }
}

extension Coordinator: NSPasteboardItemDataProvider {
    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .fileURL, let url = item.string(forType: .fileURL) {
            pasteboard?.setString(url, forType: .fileURL)
        }
    }
}

extension NSView {
    func snapshot() -> NSImage {
        let pdfData = dataWithPDF(inside: bounds)
        return NSImage(data: pdfData)!
    }
}
