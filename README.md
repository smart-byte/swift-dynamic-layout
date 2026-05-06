# swift-dynamic-layout

A Swift package providing pluggable `NSCollectionViewLayout` algorithms for macOS apps that need richer alternatives to the system flow layout — Pinterest-style waterfall, Google-Photos-style justified rows, horizontal flow, and vertical/horizontal variants — plus the cell-rendering and drag-and-drop primitives to back them.

Originally built for the [Voilà file browser](https://github.com/smart-byte/voila), extracted as a standalone package once the engine had been fully decoupled from any file-domain concerns.

## Requirements

- macOS 14+
- Swift 5.9+ (Swift 6.0 strict concurrency compatible)

## Installation

```swift
.package(url: "https://github.com/smart-byte/swift-dynamic-layout.git", from: "1.0.0"),
```

Add `DynamicLayout` to your target's dependencies.

## Layout algorithms

| Layout | Description |
|---|---|
| `WaterfallLayout` | Pinterest-style masonry. Multi-column, items flow into the shortest column. |
| `JustifiedLayout` | Google-Photos-style rows. Each row stretches to fill width with aspect-ratio-aware widths and a configurable target height. |
| `HorizontalJustifiedLayout` | Horizontal variant of `JustifiedLayout`. |
| `HorizontalFlowLayout` | Single horizontal row with auto-scrolling. Fixed item height. |
| `VerticalFlowLayout` | Single vertical column. |

All layouts conform to a shared internal `LayoutItemsProvider` protocol; the host sets `[LayoutItemFrame]` on the layout and the engine handles the rest.

## Quick start

```swift
import DynamicLayout
import SwiftUI

struct GalleryView: View {
    @State var items: [LayoutItemFrame] = []
    @State var layoutMode: LayoutMode = .waterfall
    @State var itemStyle: ItemStyle = .photoFrame
    @State var spacing: CGFloat = 0.05
    @State var targetSize: CGFloat = 200

    var body: some View {
        CollectionLayoutView(
            layoutItems: $items,
            selection: .constant([]),
            layoutMode: $layoutMode,
            itemStyle: $itemStyle,
            itemSpacing: $spacing,
            targetSize: $targetSize,
            urlForFrame: { id in
                // Resolve the URL for the given frame id from your data source.
                myItems.first(where: { $0.id == id })?.url
            },
            syncImageProvider: { url, dim in
                MyImageCache.shared.cachedImage(for: url, maxDimension: dim)
            },
            asyncImageProvider: { url, dim, completion in
                MyImageCache.shared.image(for: url, maxDimension: dim, completion: completion)
            }
        )
    }
}
```

`LayoutItemFrame` is a tiny value type (`UUID` + `CGSize`) the layout pass operates on. The host keeps its own richer item type and projects to frames at the API boundary.

## Item style

Orthogonal to layout mode, `ItemStyle` controls how each cell is presented:

- `.photoFrame` — bordered image with caption below
- `.tile` — flat tinted tile with caption
- `.borderless` — image only, optional centred caption pill overlay

## Image providers

The package doesn't ship its own thumbnail cache. Cell rendering and drag-image generation accept synchronous and asynchronous image providers as closures:

```swift
public typealias SyncImageProvider = @Sendable (URL, CGFloat) -> NSImage?
public typealias ImageProvider = @Sendable (URL, CGFloat, @escaping (NSImage?) -> Void) -> Void
```

This keeps the engine cache-agnostic; you wire in your existing thumbnail pipeline.

## Drag and drop

`CollectionLayoutView` accepts optional drop callbacks:

```swift
public typealias DropValidator = (NSDraggingInfo, URL?) -> NSDragOperation
public typealias DropPerformer = (NSDraggingInfo, URL?) -> Bool
```

These are called for both whitespace drops and folder-row drops; the second `URL?` parameter is the destination folder when the drop targets a directory.

## Status

`v1.0.0` — the initial public release after extraction from voila. Production-tested in a real file browser with thousands of items per folder.

## License

MIT — see [LICENSE](LICENSE).

## Releases

Driven by the `VERSION` file: bump it on `main`, push, and CI tags + creates the GitHub release automatically.
