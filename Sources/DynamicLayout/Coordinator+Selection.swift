import AppKit

extension Coordinator {
    /// A native selection can be ahead of the binding during mouse tracking.
    /// Only a changed host value or an explicit reload may overwrite it.
    func syncSelection() {
        let selected = sanitizedSelection(parent.selection, itemCount: parent.layoutItems.count)
        if parent.selection != selected { parent.selection = selected }
        guard let collectionView, lastAppliedSelection != selected else { return }
        lastAppliedSelection = selected
        if collectionView.selectionIndexPaths != selected {
            collectionView.selectionIndexPaths = selected
        }
    }

    func reloadCollection() {
        collectionView?.reloadData()
        lastAppliedSelection = nil
    }

    func publishSelection(from collectionView: NSCollectionView) {
        // Selection and deselection callbacks can describe one replacement.
        // Publish the complete native state, not a delta onto a stale binding.
        let selected = collectionView.selectionIndexPaths
        lastAppliedSelection = selected
        if parent.selection != selected { parent.selection = selected }
    }
}
