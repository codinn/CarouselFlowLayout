//
//  CarouselFlowLayout.swift
//
//  Created by Paul Ulric on 23/06/2016.
//  Copyright © 2016 Paul Ulric. All rights reserved.
//

import UIKit

open class CarouselFlowLayout: UICollectionViewFlowLayout {
    
    public enum SpacingMode {
        case fixed(spacing: CGFloat)
        case overlap(visibleOffset: CGFloat)
    }
    
    fileprivate struct LayoutState {
        var size: CGSize
        var direction: UICollectionView.ScrollDirection
        func isEqual(_ otherState: LayoutState) -> Bool {
            return self.size.equalTo(otherState.size) && self.direction == otherState.direction
        }
    }
    
    fileprivate var indexPathsOnDeletion = [IndexPath]()
    fileprivate var indexPathsOnInsertion = [IndexPath]()
    
    @IBInspectable open var sideItemScale: CGFloat = 0.6
    @IBInspectable open var sideItemAlpha: CGFloat = 0.6
    @IBInspectable open var sideItemShift: CGFloat = 0.0
    open var spacingMode = SpacingMode.fixed(spacing: 40)
    
    fileprivate var state = LayoutState(size: CGSize.zero, direction: .horizontal)
    
    
    override open func prepare() {
        super.prepare()
        guard let collectionView = self.collectionView else { return }
        
        let currentState = LayoutState(size: collectionView.safeAreaLayoutGuide.layoutFrame.size, direction: self.scrollDirection)
        
        if state.isEqual(currentState) { return }
        
        // setup collection view
        if collectionView.decelerationRate != UIScrollView.DecelerationRate.fast {
            collectionView.decelerationRate = UIScrollView.DecelerationRate.fast
        }
        
        // setup layout
        let collectionSize = collectionView.safeAreaLayoutGuide.layoutFrame.size
        let isHorizontal = (self.scrollDirection == .horizontal)
        
        let yInset = (collectionSize.height - self.itemSize.height) / 2
        let xInset = (collectionSize.width - self.itemSize.width) / 2
        
        if isHorizontal {
            self.sectionInset = UIEdgeInsets.init(top: 0, left: xInset, bottom: 0, right: xInset)
        } else {
            self.sectionInset = UIEdgeInsets.init(top: yInset, left: 0, bottom: yInset, right: 0)
        }
        
        let side = isHorizontal ? self.itemSize.width : self.itemSize.height
        let scaledItemOffset =  (side - side*self.sideItemScale) / 2
        switch self.spacingMode {
        case .fixed(let spacing):
            self.minimumLineSpacing = spacing - scaledItemOffset
        case .overlap(let visibleOffset):
            let fullSizeSideItemOverlap = visibleOffset + scaledItemOffset
            let inset = isHorizontal ? xInset : yInset
            self.minimumLineSpacing = inset - fullSizeSideItemOverlap
        }
        
        state = currentState
    }
    
    override open func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        return true
    }
    
    override open func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let attributes = super.layoutAttributesForElements(in: rect)
            else { return nil }
        return attributes.map({ self.transformLayoutAttributes($0.copy() as! UICollectionViewLayoutAttributes) })
    }
    
    open override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        //        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        guard let attributes = super.layoutAttributesForItem(at: indexPath)?.copy() as? UICollectionViewLayoutAttributes else {
            return nil
        }
        
        return transformLayoutAttributes(attributes)
    }
    
    fileprivate func transformLayoutAttributes(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let collectionView = self.collectionView else { return attributes }
        let isHorizontal = (self.scrollDirection == .horizontal)
        
        let collectionCenter = isHorizontal ? collectionView.frame.size.width/2 : collectionView.frame.size.height/2
        let offset = isHorizontal ? collectionView.contentOffset.x : collectionView.contentOffset.y
        let normalizedCenter = (isHorizontal ? attributes.center.x : attributes.center.y) - offset
        
        let maxDistance = (isHorizontal ? self.itemSize.width : self.itemSize.height) + self.minimumLineSpacing
        let distance = min(abs(collectionCenter - normalizedCenter), maxDistance)
        let ratio = (maxDistance - distance)/maxDistance
        
        let alpha = ratio * (1 - self.sideItemAlpha) + self.sideItemAlpha
        let scale = ratio * (1 - self.sideItemScale) + self.sideItemScale
        let shift = (1 - ratio) * self.sideItemShift
        attributes.alpha = alpha
        attributes.transform3D = CATransform3DScale(CATransform3DIdentity, scale, scale, 1)
        attributes.zIndex = Int(alpha * 10)
        
        if isHorizontal {
            attributes.center.y = attributes.center.y + shift
        } else {
            attributes.center.x = attributes.center.x + shift
        }
        
        return attributes
    }
    
    override open func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView = collectionView , !collectionView.isPagingEnabled,
            let layoutAttributes = self.layoutAttributesForElements(in: collectionView.bounds)
            else { return super.targetContentOffset(forProposedContentOffset: proposedContentOffset) }
        
        let isHorizontal = (self.scrollDirection == .horizontal)
        
        let midSide = (isHorizontal ? collectionView.bounds.size.width : collectionView.bounds.size.height) / 2
        let proposedContentOffsetCenterOrigin = (isHorizontal ? proposedContentOffset.x + 1000 * velocity.x : proposedContentOffset.y + 1000 * velocity.y) + midSide
        
        var targetContentOffset: CGPoint
        if isHorizontal {
            let closest = layoutAttributes.sorted { abs($0.center.x - proposedContentOffsetCenterOrigin) < abs($1.center.x - proposedContentOffsetCenterOrigin) }.first ?? UICollectionViewLayoutAttributes()
            targetContentOffset = CGPoint(x: floor(closest.center.x - midSide), y: proposedContentOffset.y)
        }
        else {
            let closest = layoutAttributes.sorted { abs($0.center.y - proposedContentOffsetCenterOrigin) < abs($1.center.y - proposedContentOffsetCenterOrigin) }.first ?? UICollectionViewLayoutAttributes()
            targetContentOffset = CGPoint(x: proposedContentOffset.x, y: floor(closest.center.y - midSide))
        }
        
        return targetContentOffset
    }
    
}

extension CarouselFlowLayout {
    
    override open func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        
        indexPathsOnInsertion.removeAll()
        indexPathsOnDeletion.removeAll()
        
        for item in updateItems {
            switch item.updateAction {
            case .insert:
                if let inserted = item.indexPathAfterUpdate {
                    indexPathsOnInsertion.append(inserted)
                }
            case .delete:
                if let deleted = item.indexPathBeforeUpdate {
                    indexPathsOnDeletion.append(deleted)
                }
            case .move:
                if let defore = item.indexPathBeforeUpdate, let after = item.indexPathAfterUpdate {
                    //  indexPaths.append(defore)
                    //  indexPaths.append(after)
                }
            default:
                break
            }
        }
    }
    
    override open func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        indexPathsOnInsertion.removeAll()
        indexPathsOnDeletion.removeAll()
    }
    
    override open func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let i = indexPathsOnInsertion.firstIndex(of: itemIndexPath) else {
            return super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
        }
        
        guard let attributes = layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes else {
            return nil
        }
        
        var centerPoint = attributes.center
        centerPoint.y = -attributes.frame.height / 2
        attributes.center = centerPoint
        // attributes.alpha = 0.2
        indexPathsOnInsertion.remove(at: i)
        
        return attributes
    }
    
    override open func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let i = indexPathsOnDeletion.firstIndex(of: itemIndexPath) else {
            return super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
        }
        
        guard let attributes = layoutAttributesForItem(at: itemIndexPath)?.copy() as? UICollectionViewLayoutAttributes else {
            return nil
        }
        
        var centerPoint = attributes.center
        centerPoint.y = -attributes.frame.height / 2
        attributes.center = centerPoint
        // attributes.alpha = 0.2
        indexPathsOnDeletion.remove(at: i)
        
        return attributes
    }
    
}
