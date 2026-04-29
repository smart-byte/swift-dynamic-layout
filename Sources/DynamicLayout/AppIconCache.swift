//
//  AppIconCache.swift
//
//
//  Created by Mario Heubach on 29.04.26.
//

import AppKit

/// Caches application bundle icons keyed by their bundle URL.
///
/// `NSWorkspace.shared.icon(forFile:)` is surprisingly expensive when called
/// repeatedly across a list of candidate apps — building the Open-With submenu
/// on every right-click was visibly laggy. This cache memoises the lookup for
/// the lifetime of the process.
///
/// Scope is intentionally narrow: only system app icons (stable for the
/// session) belong here. User-content thumbnails go through `ImageTools`,
/// which has different keying and invalidation rules.
@MainActor
public final class AppIconCache {
    public static let shared = AppIconCache()

    /// NSCache is internally thread-safe, but the @MainActor annotation makes
    /// the whole class single-threaded by contract — no manual locking needed.
    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        // 100 is plenty of headroom for any realistic application population.
        // We deliberately skip totalCostLimit because NSImage byte size is
        // not cheap to compute and the system cache responds to memory
        // pressure on its own.
        cache.countLimit = 100
        return cache
    }()

    private init() {}

    /// Returns the icon for the application bundle at `applicationURL`.
    ///
    /// On a cache miss the icon is fetched via `NSWorkspace.shared.icon(forFile:)`
    /// and stored for subsequent lookups. The returned `NSImage` is the cached
    /// instance — callers that need a different size should copy it before
    /// mutating `size`, otherwise the mutation will leak across cache hits.
    public func icon(for applicationURL: URL) -> NSImage {
        let key = applicationURL as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
