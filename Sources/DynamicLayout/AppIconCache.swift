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
@MainActor
public final class AppIconCache {
    public static let shared = AppIconCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 100
        return cache
    }()

    private init() {}

    /// Returns the icon for the application bundle at `applicationURL`. The
    /// returned `NSImage` is the cached instance — callers that need a
    /// different size must copy it before mutating `size`, otherwise the
    /// mutation will leak across cache hits.
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
