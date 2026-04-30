//
//  FileDropPerformer.swift
//
//
//  Performs the real file-system side of a drop-into-pane: move/copy each
//  source URL into the destination folder, mirroring Finder's semantics.
//  External (Finder) and pane-to-pane drops use the same code path — a URL
//  is a URL.
//

import AppKit
import Foundation
import Logging

/// Stateless helper that resolves drop semantics (move vs. copy) and
/// performs the actual `FileManager` operation per source URL. Failures are
/// logged via `Logger(label: "voila.drop")` and do not abort the batch — a
/// partial drop is better than nothing.
enum FileDropPerformer {
    private static let logger = Logger(label: "voila.drop")

    /// Moves or copies each `urls` entry into `destinationFolder`.
    ///
    /// Rules:
    /// - `forceCopy` → unconditional copy (⌥ modifier)
    /// - same volume → `moveItem`
    /// - cross volume → `copyItem`
    ///
    /// Conflicts are resolved silently by appending " 2", " 3", … before the
    /// file extension. Source-equals-destination is a silent no-op.
    static func perform(urls: [URL], into destinationFolder: URL, forceCopy: Bool) {
        let fileManager = FileManager.default
        for source in urls {
            let useCopy = forceCopy || !sameVolume(source, destinationFolder)
            let proposed = destinationFolder.appendingPathComponent(source.lastPathComponent)

            // Move into the file's own folder is a no-op — without this
            // check, uniqueDestination would see the source as a conflict
            // and rename the file to "Foo 2.ext" inside the same folder,
            // clobbering the user's name. For copy operations the same
            // path means Finder's "Duplicate" semantics: keep going so
            // uniqueDestination produces "Foo 2.ext" intentionally.
            if !useCopy, source.standardizedFileURL == proposed.standardizedFileURL {
                continue
            }

            let destination = uniqueDestination(for: source, in: destinationFolder)
            if source == destination { continue }

            do {
                if useCopy {
                    try fileManager.copyItem(at: source, to: destination)
                } else {
                    try fileManager.moveItem(at: source, to: destination)
                }
            } catch {
                logger.error(
                    "File drop failed",
                    metadata: [
                        "source": .string(source.path),
                        "destination": .string(destination.path),
                        "operation": .string(forceCopy ? "copy(forced)" : "auto"),
                        "error": .string(String(describing: error)),
                    ]
                )
                // Keep going — one bad URL shouldn't block the rest.
                continue
            }
        }
    }

    /// Returns a non-conflicting URL inside `folder` for `source`. If
    /// `folder/source.lastPathComponent` is free, returns it directly;
    /// otherwise inserts " 2", " 3", … before the path extension. Mirrors
    /// the silent-disambiguation pattern used in
    /// `ContentViewActionHandler.didRequestNewFolder`.
    static func uniqueDestination(for source: URL, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let original = folder.appendingPathComponent(source.lastPathComponent)
        if !fileManager.fileExists(atPath: original.path) {
            return original
        }

        let ext = source.pathExtension
        let base = source.deletingPathExtension().lastPathComponent

        var counter = 2
        while counter < 1000 {
            let candidateName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
        // Pathological folder — fall back to original; the caller's
        // FileManager call will surface the clobber error via the logger.
        return original
    }

    /// Pre-flight check used by `validateDrop` so the drag cursor flips to
    /// the not-allowed badge before the user releases the mouse for cases
    /// `perform` would silently skip:
    ///   - dragging a folder onto itself
    ///   - dragging a folder into its own subtree
    ///   - dragging an item back into its own folder for a non-copy op
    ///     (move = no-op, copy = "Foo 2.ext" duplicate is intentional)
    /// Returns `true` if at least one source URL would actually transfer.
    static func canTransferAny(
        urls: [URL], into destinationFolder: URL, forceCopy: Bool
    ) -> Bool {
        guard !urls.isEmpty else { return false }
        return urls.contains {
            canTransferOne($0, into: destinationFolder, forceCopy: forceCopy)
        }
    }

    private static func canTransferOne(
        _ source: URL, into destinationFolder: URL, forceCopy: Bool
    ) -> Bool {
        let dest = destinationFolder.standardizedFileURL
        let src = source.standardizedFileURL

        // Dragging a folder onto itself: pure no-op.
        if isDirectory(source), src == dest { return false }

        // Dragging a folder into its own subtree creates a recursive loop —
        // FileManager would reject it; reject here so the cursor reflects.
        if isDirectory(source), isDescendant(dest, of: src) { return false }

        // Move into the file's own folder is a silent no-op (matches
        // FileDropPerformer.perform). Copy is allowed because Finder's
        // ⌥-Duplicate semantics are intentional.
        let useCopy = forceCopy || !sameVolume(source, destinationFolder)
        if !useCopy, src.deletingLastPathComponent() == dest { return false }

        return true
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let ancestorComponents = ancestor.standardizedFileURL.pathComponents
        guard candidateComponents.count > ancestorComponents.count else { return false }
        return Array(candidateComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    /// Volume-equality test used to choose move vs. copy. Cross-volume
    /// `moveItem` would silently fall back to copy+delete in the kernel —
    /// we do the choice explicitly so the cursor badge in `validateDrop`
    /// agrees with reality.
    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        let aID = (try? a.resourceValues(forKeys: keys).volumeIdentifier) as? NSObject
        let bID = (try? b.resourceValues(forKeys: keys).volumeIdentifier) as? NSObject
        guard let aID, let bID else { return false }
        return aID.isEqual(bID)
    }
}
