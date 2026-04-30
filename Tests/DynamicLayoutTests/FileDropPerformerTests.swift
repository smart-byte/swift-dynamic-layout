//
//  FileDropPerformerTests.swift
//
//
//  Created by Mario Heubach on 30.04.26.
//

import AppKit
@testable import DynamicLayout
import Testing

@MainActor
struct FileDropPerformerTests {
    /// Sandbox per test: each test gets a fresh, isolated tmp directory.
    /// `tearDown` removes the whole tree so we don't leak between runs.
    private final class Sandbox {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("voilaTests-FileDropPerformer-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func makeFile(_ name: String, in folder: URL? = nil) throws -> URL {
            let dir = folder ?? root
            let url = dir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data())
            return url
        }

        func makeFolder(_ name: String, in folder: URL? = nil) throws -> URL {
            let dir = folder ?? root
            let url = dir.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }

    // MARK: - canTransferAny

    @Test func happyPathReturnsTrue() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.makeFile("a.txt")
        let target = try sandbox.makeFolder("dest")

        #expect(FileDropPerformer.canTransferAny(
            urls: [source], into: target, forceCopy: false
        ))
    }

    @Test func emptyURLsReturnsFalse() throws {
        let sandbox = try Sandbox()
        let target = try sandbox.makeFolder("dest")

        #expect(!FileDropPerformer.canTransferAny(
            urls: [], into: target, forceCopy: false
        ))
    }

    @Test func targetNotADirectoryReturnsFalse() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.makeFile("a.txt")
        let notAFolder = try sandbox.makeFile("not-a-folder.txt")

        #expect(!FileDropPerformer.canTransferAny(
            urls: [source], into: notAFolder, forceCopy: false
        ))
    }

    @Test func folderDraggedOntoItselfReturnsFalse() throws {
        let sandbox = try Sandbox()
        let folder = try sandbox.makeFolder("self")

        #expect(!FileDropPerformer.canTransferAny(
            urls: [folder], into: folder, forceCopy: false
        ))
    }

    @Test func folderDraggedIntoOwnSubtreeReturnsFalse() throws {
        let sandbox = try Sandbox()
        let outer = try sandbox.makeFolder("outer")
        let inner = try sandbox.makeFolder("inner", in: outer)

        #expect(!FileDropPerformer.canTransferAny(
            urls: [outer], into: inner, forceCopy: false
        ))
    }

    @Test func moveIntoOwnFolderReturnsFalse() throws {
        let sandbox = try Sandbox()
        let folder = try sandbox.makeFolder("home")
        let file = try sandbox.makeFile("a.txt", in: folder)

        #expect(!FileDropPerformer.canTransferAny(
            urls: [file], into: folder, forceCopy: false
        ))
    }

    /// `⌥` Duplicate intent: copying a file back into its own folder is
    /// a valid Finder action — we let it through so `perform` produces
    /// `Foo 2.ext`.
    @Test func copyIntoOwnFolderReturnsTrue() throws {
        let sandbox = try Sandbox()
        let folder = try sandbox.makeFolder("home")
        let file = try sandbox.makeFile("a.txt", in: folder)

        #expect(FileDropPerformer.canTransferAny(
            urls: [file], into: folder, forceCopy: true
        ))
    }

    /// Mixed batch with one no-op and one valid item still allows the drop
    /// — `perform` will skip the no-op and process the valid one.
    @Test func mixedBatchAllowsDropIfAnyValid() throws {
        let sandbox = try Sandbox()
        let folder = try sandbox.makeFolder("home")
        let inFolder = try sandbox.makeFile("here.txt", in: folder)
        let elsewhere = try sandbox.makeFile("from-outside.txt")

        #expect(FileDropPerformer.canTransferAny(
            urls: [inFolder, elsewhere], into: folder, forceCopy: false
        ))
    }

    // MARK: - uniqueDestination

    @Test func uniqueDestinationReturnsOriginalWhenFree() throws {
        let sandbox = try Sandbox()
        let source = try sandbox.makeFile("a.txt")
        let target = try sandbox.makeFolder("dest")

        let result = FileDropPerformer.uniqueDestination(for: source, in: target)
        #expect(result.lastPathComponent == "a.txt")
    }

    @Test func uniqueDestinationAppendsCounterOnCollision() throws {
        let sandbox = try Sandbox()
        let target = try sandbox.makeFolder("dest")
        _ = try sandbox.makeFile("a.txt", in: target)
        let source = try sandbox.makeFile("a.txt")

        let result = FileDropPerformer.uniqueDestination(for: source, in: target)
        #expect(result.lastPathComponent == "a 2.txt")
    }

    @Test func uniqueDestinationSkipsExistingCounters() throws {
        let sandbox = try Sandbox()
        let target = try sandbox.makeFolder("dest")
        _ = try sandbox.makeFile("a.txt", in: target)
        _ = try sandbox.makeFile("a 2.txt", in: target)
        _ = try sandbox.makeFile("a 3.txt", in: target)
        let source = try sandbox.makeFile("a.txt")

        let result = FileDropPerformer.uniqueDestination(for: source, in: target)
        #expect(result.lastPathComponent == "a 4.txt")
    }

    @Test func uniqueDestinationHandlesNoExtension() throws {
        let sandbox = try Sandbox()
        let target = try sandbox.makeFolder("dest")
        _ = try sandbox.makeFile("README", in: target)
        let source = try sandbox.makeFile("README")

        let result = FileDropPerformer.uniqueDestination(for: source, in: target)
        #expect(result.lastPathComponent == "README 2")
    }

    // MARK: - sameVolume

    @Test func sameVolumeForFilesOnSameDiskReturnsTrue() throws {
        let sandbox = try Sandbox()
        let a = try sandbox.makeFile("a.txt")
        let b = try sandbox.makeFile("b.txt")

        #expect(FileDropPerformer.sameVolume(a, b))
    }
}
