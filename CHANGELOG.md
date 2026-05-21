# Changelog

## v1.3.0 — 2026-05-21

Optional opt-out from the folder-switch crossfade. The 240 ms alpha
fade on every folder change made navigation feel sluggish to users
working at speed; the new toggle keeps the historical look as default
while letting hosts expose an "instant folder switch" preference.

### `CollectionLayoutView.folderSwitchAnimated`

- New init parameter `folderSwitchAnimated: Bool = true`. Defaults
  preserve the existing crossfade behavior — no source break for
  existing call sites.
- When `false`, folder swaps reload synchronously via
  `CATransaction`-disabled updates. Selection + scroll-position
  restoration is preserved.
- When `false`, the diff path also detects fully disjoint UUID sets
  (the async two-phase case where the folder URL and the items
  publish on separate ticks) and falls back to the same instant
  reload, so the per-cell `.effectFade` doesn't sneak in for what
  is really a folder swap.

## v1.2.0 — 2026-05-07

Inline rename for collection-mode cells, plus the protocol +
context-menu plumbing to drive it from the host.

### `ItemActionHandler.didRequestRename(_:to:)`

New protocol method (with a default no-op so apps that haven't
migrated keep compiling unchanged). Fired when the user commits a
new name via inline edit; the host performs the actual filesystem
rename and decides how to surface failures.

### Inline caption editing on `ThumbnailItem`

- `public var representedFileURL: URL?` — read-only access to the
  cell's current URL so hosts can resolve cell-level interactions
  without a parallel index-path map.
- `public func beginCaptionEditing(commit:cancel:)` — flips the
  caption label into edit mode, makes it first responder, and
  pre-selects the basename (everything before the file extension)
  for files or the whole name for folders, matching Finder.
- `public var isEditingCaption: Bool` — snapshot flag for hosts
  that need to gate competing UI.
- `prepareForReuse()` cancels any in-flight edit — the cell is
  about to host a different file, so committing whatever the
  user typed against the old URL would be wrong.

### Collection-view triggers

`NiblessCollectionView` now fires inline rename on:

- **Single click on the already-singly-selected cell**, debounced
  by ~0.5 s so a fast double-click doesn't get misread as a slow
  second click.
- **Return key** when exactly one cell is selected.
- **Right-click → Rename** entry, single-selection only.

`ItemContextMenuBuilder.menu(for:…)` accepts an optional
`rename: ((URL) -> Void)?` — collection callers route this back
through the cell's begin-edit flow; list callers can wire their
own host-side rename trigger when the time comes.

### Notes

- List-mode rename (NSTableView side) stays host-driven for now —
  the package couldn't subclass-promote `NiblessTableView` here
  without further breaking-change risk; voila already wires its
  own NSEvent monitors locally and drives the text field via
  `ListRenameController`.
- 48 unit tests still green.

## v1.1.2 — 2026-05-07

Bug fix for host-driven selection getting wiped by `NSCollectionView.reloadData()`.

`reloadData()` clears `selectionIndexPaths`, but `updateNSView` was
syncing the host's selection onto the collection view BEFORE the
apply-* branches that trigger the reload — so any selection the host
pushed (e.g. via a "reveal in folder" action landing on a freshly-
mounted or hidden tab) got wiped immediately.

Two prongs:
- `updateNSView` sanitises selection up-front but defers the actual
  push to NSCollectionView until AFTER any reload.
- `crossfadeReload` (deferred reload inside an alpha-fade
  `NSAnimationContext`) captures the host's selection BEFORE the
  animation kicks off and re-applies it inside the completion handler
  right after the reload lands.

48 unit tests still green.

## v1.1.1 — 2026-05-07

Patch over v1.1.0 that broke the layout test suite. The
sectionInset auto-derivation introduced in v1.1.0 was overwriting
explicit insets unconditionally; tests that pin `sectionInset` and
disable spacing (`spacingPercentage = 0`) to verify item placement
were failing as a result. Auto-derivation now only fires when
`spacing > 0`, so production calls keep gutter-matches-gap
behaviour while pinned-inset tests stay valid.

## v1.1.0 — 2026-05-07

Finder-feel polish over the v1.0.0 extraction baseline.

### `photoFrame` chrome
- Matte thickness driven by the host's `scaleReference` (`targetSize` for most layouts, cell height for `horizontalFlow`) instead of per-cell bounds, so the white border around every photo reads at the same visual weight regardless of aspect.
- Drop shadow lives on the matte sublayer with an explicit `shadowPath` for a crisp halo that survives parent `masksToBounds` clipping.
- Selection renders as a 4 pt accent border on the matte's outer edge plus a Finder-style accent pill behind the caption (white text on tint).
- `CaptionSelectionPill` manages its own capsule cornerRadius from `layout()` so the pill stays cleanly round across collection-layout switches and zoom-slider changes.

### Selection state
- `NiblessCollectionView` observes window-key changes and overrides `becomeFirstResponder` / `resignFirstResponder` (with an async hop to read the post-transit firstResponder) so cells fade to a secondary tint when their pane / window loses focus, matching `NSTableView`'s native list-pane behaviour.

### Spacing & gutter
- `WaterfallLayout`, `VerticalFlowLayout` and `HorizontalFlowLayout` mirror their computed inter-item spacing into `sectionInset` during `prepare()`, so the edge gutter reads as the same visual gap as between items instead of a fixed 20 pt slab. `JustifiedLayout` / `HorizontalJustifiedLayout` use matching small fixed insets.

### `HorizontalFlowLayout`
- New `useSquareCells` flag — tile style now produces perfect squares instead of aspect-stretched rects.
- New `onLayoutPrepared` callback fires `availableHeight` after each `prepare()`; the host pushes that as `scaleReference` to visible cells so the photoFrame matte stays uniform across cells regardless of toolbar slider, and updates correctly when the window resizes or new cells scroll into view.
- Default `spacingPercentage` `0.05 → 0.02`; spacing is slider-driven via the host's `itemSpacing` instead of hard-coded.
- `collectionViewContentSize` is now O(1) — `contentWidth` is cached from `prepare()` instead of iterating items per scroll frame.

### Internal reorder is opt-in
- `CollectionLayoutView.allowsInternalReorder` (default `false`). Same-pane drags only allow drops onto sibling folder cells, not whitespace / cell-reordering. Cross-pane drags between two collection views are unaffected.

### Race-condition fix
- `applyLayoutChange` / `applyItemsChange` schedule a deferred `invalidateLayout` on the next runloop. Covers the timing window where `prepare()` runs against transient (zero / mid-resize) cv bounds before `NSScrollView` has propagated final size — without this the cache occasionally landed a 2×2-pixel layout that `shouldInvalidateLayout` couldn't recover from on the silent bounds-update AppKit applies right after `layoutSubtreeIfNeeded`.

### Drop affordance parity with `NSTableView`
- Folder-cell hit checked before the `isInternal` branch, so a same-pane drag onto a sibling subfolder is a real move (matches list behaviour). Internal drag landing on whitespace / non-folder refuses cleanly without painting a misleading pane border.

### Borderless polish (carried over from feat branch)
- Image-only drag preview (caption pill no longer rides along).
- Caption pill is hover-only with a short fade.
- Adaptive flying preview swaps the source's drag image to the target collection's style at the boundary.

### Performance
- `BorderImageView` `shadowPath` only rebuilt when matte size actually changes (cached `lastMatteSize`).
- `BorderImageView.noImplicitActions` is now a `static let` — one shared dictionary instead of one per cell-reuse.
- `HorizontalFlow.onLayoutPrepared` fires only when `availableHeight` changes, eliminating the redundant cell-`needsLayout` cascade on every routine `prepare()` pass.

48 unit tests pass on CI.

## v1.0.0 — 2026-05-06

Initial public release. Extracted from [smart-byte/voila](https://github.com/smart-byte/voila) after a five-phase decoupling effort that left the package free of file-domain concerns:

- `LayoutItemFrame` (32 B `UUID` + `CGSize` value type) replaces the previous file-flavoured `DynamicLayoutItem`. Layout passes operate on a 6× smaller per-item footprint than before; cache-line behaviour during `prepare()` improves accordingly for large item sets.
- `ImageProvider` and `SyncImageProvider` typealiases let the host inject any thumbnail pipeline. The package no longer depends on a specific image cache.
- `DropValidator` and `DropPerformer` typealiases route file-system drops back through the host.
- `CollectionLayoutView` (renamed from `FileCollectionView`) is the only `NSViewRepresentable` entry point. All file-browser machinery (FileListView, ListCoordinator, FileDropPerformer, ListSortDescriptor) was moved out before this release.
- Pinboard / free-form-canvas code was extracted into a separate package earlier in the decoupling path.

Public surface:

- Layouts: `WaterfallLayout`, `JustifiedLayout`, `HorizontalJustifiedLayout`, `HorizontalFlowLayout`, `VerticalFlowLayout`
- Cell building blocks: `ThumbnailItem`, `BorderImageView`, `CaptionPill`
- Enums: `LayoutMode`, `ItemStyle`, `DragImageStyle`
- Wrappers: `CollectionLayoutView`, `NiblessTableView`, `NiblessTableViewCoordinating`
- Helpers: `DragImageComposer`, `DragSessionState`, `QuickLookHelpers`, `BackgroundContextMenuBuilder`, `ItemContextMenuBuilder`, `DynamicLayoutItemsSnapshot`, `sanitizedSelection`
- Closure typealiases: `SyncImageProvider`, `ImageProvider`, `DropValidator`, `DropPerformer`
- Callbacks: `ItemActionHandler`

Targets macOS 14+, Swift 5.9+ (Swift 6.0 strict concurrency compatible). 48 unit tests pass on CI.
