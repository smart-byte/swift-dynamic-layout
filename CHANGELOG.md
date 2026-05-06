# Changelog

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
