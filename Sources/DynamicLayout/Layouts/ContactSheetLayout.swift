//
//  File.swift
//
//
//  Created by Mario Heubach on 07.05.24.
//

import AppKit

public class ContactSheetLayout: NSCollectionViewFlowLayout {

    let columns: Int = 5
    let spacingPercentage: CGFloat = 0.05  // 5% der Item-Breite

    public override func prepare() {
        super.prepare()

        guard let collectionView = self.collectionView else { return }
        guard let scrollView = collectionView.enclosingScrollView else { return }

        let availableWidth = scrollView.contentSize.width - self.sectionInset.left - self.sectionInset.right
        let baseItemWidth = floor(availableWidth / CGFloat(columns))
        let itemSpacing = floor(baseItemWidth * spacingPercentage)
        let totalSpacing = itemSpacing * CGFloat(columns - 1)
        let adjustedWidth = availableWidth - totalSpacing
        let itemWidth = floor(adjustedWidth / CGFloat(columns))

        self.itemSize = CGSize(width: itemWidth, height: itemWidth)
        self.minimumInteritemSpacing = itemSpacing
        self.minimumLineSpacing = itemSpacing * 1.2
    }
}
