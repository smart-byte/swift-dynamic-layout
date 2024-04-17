//
//  DynamicLayout.swift
//  DynamicLayout
//
//  Created by Mario Heubach on 23.02.24.
//

import SwiftUI

public struct DynamicLayout: NSViewRepresentable, Equatable {
    let items: [DynamicLayoutItem]
    let rowHeight: CGFloat
    let spacing: CGFloat
    let animated: Bool
    let wrapItems: Bool

    @Binding var selection: Set<IndexPath>

    public init(
        items: [DynamicLayoutItem] = [],
        selection: Binding<Set<IndexPath>> = .constant([]),
        rowHeight: CGFloat = 150,
        spacing: CGFloat = 10,
        wrapItems: Bool = false,
        animated: Bool = true
    ) {
        self.items = items
        _selection = selection
        self.rowHeight = rowHeight
        self.spacing = spacing
        self.animated = animated
        self.wrapItems = wrapItems
    }

    public func makeNSView(context: Context) -> LayoutCollectionView {
        let view = LayoutCollectionView()
      //  view.collectionView.delegate = context.coordinator
        return view
    }

    public func updateNSView(_ nsView: LayoutCollectionView, context: Context) {

        nsView.rowHeight = rowHeight
        nsView.cellSpacing = spacing
        nsView.wrapItems = wrapItems
        nsView.layoutItems = items

        if animated {
            nsView.animate()
        }
    }

    public static func == (lhs: DynamicLayout, rhs: DynamicLayout) -> Bool {
        lhs.rowHeight == rhs.rowHeight &&
        lhs.spacing == rhs.spacing &&
        ArraysEqual(lhs.items, rhs.items)
    }

//    public func makeCoordinator() -> Coordinator {
//        Coordinator(selection: $selection)
//    }
//
//    class Coordinator: NSObject, NSCollectionViewDelegate {
//        var selection: Binding<Set<IndexPath>>
//
//        init(selection: Binding<Set<IndexPath>>) {
//            self.selection = selection
//        }
//
//        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
//            selection.wrappedValue.formUnion(indexPaths)
//        }
//
//        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
//            selection.wrappedValue.subtract(indexPaths)
//        }
//    }
}

func ArraysEqual(_ array1: [DynamicLayoutItem], _ array2: [DynamicLayoutItem]) -> Bool {
    return array1.count == array2.count && array1.enumerated().allSatisfy { (index, element) in
        return element.id == array2[index].id
    }
}
