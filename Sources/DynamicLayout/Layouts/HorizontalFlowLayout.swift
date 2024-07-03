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
        
        self.itemSize = CGSize(width: 100, height: availableHeight) 
        self.minimumInteritemSpacing = spacing
        self.minimumLineSpacing = spacing
        self.scrollDirection = .horizontal
    }
    
    public override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return .zero }
        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        let totalWidth = (0..<numberOfItems).reduce(sectionInset.left) { (result, index) -> CGFloat in
            let indexPath = IndexPath(item: index, section: 0)
            let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
            let aspectRatio = items[indexPath.item].aspectRatio
            let itemWidth = itemHeight * aspectRatio
            return result + itemWidth + minimumInteritemSpacing
        } - minimumInteritemSpacing + sectionInset.right
        return CGSize(width: totalWidth, height: collectionView.bounds.height)
    }
    
    public override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard let collectionView = collectionView else { return [] }
        
        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        var attributesArray: [NSCollectionViewLayoutAttributes] = []
        
        var xOffset: CGFloat = sectionInset.left
        let yOffset: CGFloat = sectionInset.top
        
        for index in 0..<numberOfItems {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
            let aspectRatio = items[indexPath.item].aspectRatio
            let itemWidth = itemHeight * aspectRatio
            
            attributes.frame = CGRect(x: xOffset, y: yOffset, width: itemWidth, height: itemHeight)
            if attributes.frame.intersects(rect) {
                attributesArray.append(attributes)
            }
            
            xOffset += itemWidth + minimumInteritemSpacing
        }
        
        return attributesArray
    }
    
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let collectionView = collectionView else { return nil }
        
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        let itemHeight = collectionView.bounds.height - sectionInset.top - sectionInset.bottom
        let aspectRatio = items[indexPath.item].aspectRatio
        let itemWidth = itemHeight * aspectRatio
        
        let xOffset = (0..<indexPath.item).reduce(sectionInset.left) { (result, index) -> CGFloat in
            let prevIndexPath = IndexPath(item: index, section: 0)
            let prevAspectRatio = items[prevIndexPath.item].aspectRatio
            let prevItemWidth = itemHeight * prevAspectRatio
            return result + prevItemWidth + minimumInteritemSpacing
        }
        
        attributes.frame = CGRect(x: xOffset, y: sectionInset.top, width: itemWidth, height: itemHeight)
        
        return attributes
    }
}
