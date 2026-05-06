//
//  ImageProvider.swift
//
//
//  Created by Mario Heubach on 06.05.26.
//

import AppKit

// Why typealiases instead of a protocol:
// A protocol would introduce an existential (`any ImageProviding`) at every
// call site in the hot cell-configuration path — that means a witness-table
// lookup per call. A plain @Sendable closure compiles to a direct call
// through the function pointer; Swift monomorphises it at the call site when
// the concrete closure type is visible, and even in the non-inlined case the
// overhead is a single indirect call — identical to a direct method dispatch.
//
// Why two separate typealiases (sync + async):
// `ImageCache` (in ImageTools) exposes exactly this split API:
//   - `cachedImage(for:maxDimension:)` — synchronous, returns nil on miss
//   - `image(for:maxDimension:completion:)` — async, delivers on main queue
// `ThumbnailItem.configure` uses the same two-phase strategy: try the
// synchronous path first (zero latency on a cache hit), fall back to the
// async variant only on a miss. Merging them into one async-only provider
// would lose the synchronous fast path and cause unnecessary layout flicker
// during cell reuse of already-cached images.

/// Synchronous image lookup — typically a cache hit. Returns `nil` when the
/// image isn't available immediately; the caller should follow up with the
/// async variant for an eventual result.
public typealias SyncImageProvider = @Sendable (URL, CGFloat) -> NSImage?

/// Asynchronous image lookup — completes once the image is loaded or
/// rendered. Completion may be called on any thread; callers that mutate
/// UI state must dispatch to the main queue themselves.
public typealias ImageProvider = @Sendable (URL, CGFloat, @escaping @Sendable (NSImage?) -> Void) -> Void
