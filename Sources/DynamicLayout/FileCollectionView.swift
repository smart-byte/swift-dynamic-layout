//
//  FileCollectionView.swift
//
//
//  Created by Mario Heubach on 29.04.24.
//

import SwiftUI
import AppKit

typealias LayoutItem = ThumbnailItem // ContactSheetItem // ThumbnailItem

public struct FileCollectionView: NSViewRepresentable, Equatable {
    @Binding var fileURLs: [URL]
    @Binding var selection: Set<IndexPath>

    var collectionView = NSCollectionView()

    public init(fileURLs: Binding<[URL]>, selection: Binding<Set<IndexPath>> = .constant([]) ) {
        _fileURLs = fileURLs
        _selection = selection
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let layout = ContactSheetLayout()
        layout.scrollDirection = .vertical
        //        layout.itemSize = NSSize(width: 120, height: 120)
        layout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let collectionView = NSCollectionView()
        collectionView.registerForDraggedTypes([.fileURL ])
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            LayoutItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier(
                rawValue: String(describing: LayoutItem.self)
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

    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public static func == (lhs: FileCollectionView, rhs: FileCollectionView) -> Bool {
        lhs.fileURLs == rhs.fileURLs && lhs.selection == rhs.selection
    }
}

public class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var parent: FileCollectionView
    var selection: Set<IndexPath> = []

    init(_ parent: FileCollectionView) {
        self.parent = parent
    }

    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return parent.fileURLs.count
    }

    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {

        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier(
                rawValue: String(describing: LayoutItem.self) ),
            for: indexPath
        ) as! LayoutItem

        let fileURL = parent.fileURLs[indexPath.item]
        item.configure(with: fileURL)
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

        let url = parent.fileURLs[indexPath.item]
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
            return parent.fileURLs[indexPath.item]
        }
        session.draggingPasteboard.writeObjects(urls as [NSPasteboardWriting])
        session.draggingFormation = .none
    }

    public func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool {
        true
    }

    public func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let pasteboard = info.draggingPasteboard

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }

        let index = indexPath.item

        for url in urls {
            if let index = parent.fileURLs.firstIndex(of: url) {
                parent.fileURLs.remove(at: index)
                parent.fileURLs.insert(url, at: index)
                collectionView.animator().moveItem(at: IndexPath(item: index, section: 0), to: IndexPath(item: index, section: 0))
            } else {
                parent.fileURLs.insert(url, at: index)
            }
        }

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

    public func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath indexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {

        proposedDropOperation.pointee = .before

        if NSApp.currentEvent?.modifierFlags.contains(.option) ?? false {
            return .copy
        } else if info.draggingSource as? NSCollectionView == collectionView {
            return .move
        } else {
            return .generic
        }
    }
}

extension Coordinator: NSPasteboardItemDataProvider {
    public func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .fileURL, let url = item.string(forType: .fileURL) {
            pasteboard?.setString(url, forType: .fileURL)
        }
    }
}
