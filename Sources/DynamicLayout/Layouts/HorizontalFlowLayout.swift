//
//  File.swift
//
//
//  Created by Mario Heubach on 08.05.24.
//

import AppKit

public class HorizontalFlowLayout: NSCollectionViewFlowLayout {
    public var spacingPercentage: CGFloat = 0.05
    
    var items: [DynamicLayoutItem] = []
    
    public override func prepare() {
        super.prepare()
        
        guard let collectionView = collectionView else { return }
        
        let availableHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
        let spacing = availableHeight * spacingPercentage
        
        self.minimumInteritemSpacing = spacing
        self.minimumLineSpacing = spacing
        self.scrollDirection = .horizontal
    }
    
    public override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return .zero }
        let totalWidth = items.reduce(sectionInset.left) { (result, item) -> CGFloat in
            let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
            let itemWidth = itemHeight * item.aspectRatio
            return result + itemWidth + minimumInteritemSpacing
        } - minimumInteritemSpacing + sectionInset.right
        return CGSize(width: totalWidth, height: collectionView.bounds.height)
    }
    
    public override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard let collectionView = collectionView else { return [] }
        
        let availableHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
        let spacing = availableHeight * spacingPercentage
        
        var attributesArray: [NSCollectionViewLayoutAttributes] = []
        
        var xOffset: CGFloat = sectionInset.left
        let yOffset: CGFloat = sectionInset.top
        
        for (index, item) in items.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            let itemWidth = availableHeight * item.aspectRatio
            
            attributes.frame = CGRect(x: xOffset, y: yOffset, width: itemWidth, height: availableHeight)
            if attributes.frame.intersects(rect) {
                attributesArray.append(attributes)
            }
            
            xOffset += itemWidth + spacing
        }
        
        return attributesArray
    }
    
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let collectionView = collectionView else { return nil }
        
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        let item = items[indexPath.item]
        let availableHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
        let itemWidth = availableHeight * item.aspectRatio
        
        let xOffset = items.prefix(indexPath.item).reduce(sectionInset.left) { (result, item) -> CGFloat in
            let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
            let itemWidth = itemHeight * item.aspectRatio
            return result + itemWidth + minimumInteritemSpacing
        }
        
        attributes.frame = CGRect(x: xOffset, y: sectionInset.top, width: itemWidth, height: availableHeight)
        
        return attributes
    }
}
