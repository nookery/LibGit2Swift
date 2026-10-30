import Foundation
@testable import LibGit2Swift
import XCTest

/// Tests for `unstageFiles()` / `unstageFile()` — the Swift equivalent of
/// `git reset HEAD -- <paths>`.
final class UnstageTests: LibGit2SwiftTestCase {

    // MARK: - Single file

    /// Unstage a tracked file that was modified and staged.
    /// After unstage the index should match HEAD; the working-tree file is untouched.
    func testUnstageTrackedModifiedFile() throws {
        // Setup: commit a file, modify it, then stage it.
        let fileName = "tracked.txt"
        try testRepo.createFileAndCommit(
            fileName: fileName,
            content: "original",
            message: "Initial commit"
        )

        let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
        try "modified".write(to: fileURL, atomically: true, encoding: .utf8)
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)

        // Sanity: file is staged.
        XCTAssertTrue(try LibGit2.getStagedFiles(at: testRepo.repositoryPath).contains(fileName))

        // Act
        try LibGit2.unstageFile(fileName, at: testRepo.repositoryPath, verbose: false)

        // Assert: no longer staged
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(staged.contains(fileName), "File should no longer be staged")

        // Assert: working directory untouched
        let content = try testRepo.readFile(fileName)
        XCTAssertEqual(content, "modified", "Working-tree content must not change")
    }

    /// Unstage a newly added file (not present in HEAD).
    /// The index entry should be removed; the working-tree file must remain.
    func testUnstageNewFile() throws {
        // Setup: create an initial commit so we have a HEAD.
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        // Create and stage a new file.
        let newFile = "brand_new.txt"
        let fileURL = testRepo.tempDirectory.appendingPathComponent(newFile)
        try "new content".write(to: fileURL, atomically: true, encoding: .utf8)
        try LibGit2.addFiles([newFile], at: testRepo.repositoryPath)

        // Sanity
        XCTAssertTrue(try LibGit2.getStagedFiles(at: testRepo.repositoryPath).contains(newFile))

        // Act
        try LibGit2.unstageFile(newFile, at: testRepo.repositoryPath, verbose: false)

        // Assert: no longer staged
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(staged.contains(newFile), "New file should no longer be staged")

        // Assert: file still exists on disk
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "new content")
    }

    // MARK: - Multiple files

    /// Unstage multiple files at once.
    func testUnstageMultipleFiles() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        // Stage three new files.
        let files = ["a.txt", "b.txt", "c.txt"]
        for f in files {
            try "content".write(
                to: testRepo.tempDirectory.appendingPathComponent(f),
                atomically: true, encoding: .utf8
            )
        }
        try LibGit2.addFiles(files, at: testRepo.repositoryPath)

        // Sanity
        let stagedBefore = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        for f in files {
            XCTAssertTrue(stagedBefore.contains(f))
        }

        // Act
        try LibGit2.unstageFiles(files, at: testRepo.repositoryPath, verbose: false)

        // Assert
        let stagedAfter = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        for f in files {
            XCTAssertFalse(stagedAfter.contains(f), "\(f) should no longer be staged")
        }
    }

    /// Unstage only some staged files; the rest remain staged.
    func testUnstagePartial() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        let keepStaged = "keep.txt"
        let unstageTarget = "remove.txt"

        for f in [keepStaged, unstageTarget] {
            try "x".write(
                to: testRepo.tempDirectory.appendingPathComponent(f),
                atomically: true, encoding: .utf8
            )
        }
        try LibGit2.addFiles([keepStaged, unstageTarget], at: testRepo.repositoryPath)

        // Act: only unstage one file
        try LibGit2.unstageFile(unstageTarget, at: testRepo.repositoryPath, verbose: false)

        // Assert
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(staged.contains(keepStaged), "keep.txt should still be staged")
        XCTAssertFalse(staged.contains(unstageTarget), "remove.txt should no longer be staged")
    }

    // MARK: - Tracked file deletion unstage

    /// A tracked file was deleted from the working tree and the deletion was staged.
    /// After unstage the index should be restored (file re-appears as staged for addition).
    func testUnstageTrackedDeletion() throws {
        let fileName = "deletable.txt"
        try testRepo.createFileAndCommit(
            fileName: fileName,
            content: "will be deleted",
            message: "Initial commit"
        )

        // Delete and stage deletion.
        let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
        try FileManager.default.removeItem(at: fileURL)
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)

        // Sanity: the deletion is staged
        XCTAssertTrue(try LibGit2.getStagedFiles(at: testRepo.repositoryPath).contains(fileName))

        // Act
        try LibGit2.unstageFile(fileName, at: testRepo.repositoryPath, verbose: false)

        // Assert: deletion no longer staged; index matches HEAD
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(staged.contains(fileName), "Deletion should no longer be staged")
    }

    // MARK: - Subdirectory

    /// Unstage a file inside a subdirectory.
    func testUnstageFileInSubdirectory() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        let subDir = testRepo.tempDirectory.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let fileName = "src/main.swift"
        try "print(\"hello\")".write(
            to: testRepo.tempDirectory.appendingPathComponent(fileName),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)

        // Sanity
        XCTAssertTrue(try LibGit2.getStagedFiles(at: testRepo.repositoryPath).contains(fileName))

        // Act
        try LibGit2.unstageFile(fileName, at: testRepo.repositoryPath, verbose: false)

        // Assert
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(staged.contains(fileName), "Subdirectory file should be unstaged")

        // Working tree unchanged
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: testRepo.tempDirectory.appendingPathComponent(fileName).path
        ))
    }

    // MARK: - Empty / no-op scenarios

    /// Passing an empty array is a no-op (no error).
    func testUnstageEmptyArray() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        // Act & Assert: no crash, no error
        XCTAssertNoThrow(try LibGit2.unstageFiles([], at: testRepo.repositoryPath, verbose: false))
    }

    /// Passing an array of only empty strings is a no-op.
    func testUnstageOnlyEmptyStrings() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        XCTAssertNoThrow(
            try LibGit2.unstageFiles(["", ""], at: testRepo.repositoryPath, verbose: false)
        )

        // No staged files should appear
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(staged.isEmpty)
    }

    /// Unstaging a file that is not staged is a no-op (no error).
    func testUnstageNotStagedFile() throws {
        try testRepo.createFileAndCommit(
            fileName: "file.txt",
            content: "committed",
            message: "Initial commit"
        )

        // file.txt is committed and clean — not staged.
        // Unstaging should succeed silently.
        XCTAssertNoThrow(
            try LibGit2.unstageFile("file.txt", at: testRepo.repositoryPath, verbose: false)
        )

        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(staged.isEmpty)
    }

    // MARK: - Empty repository

    /// Unstage in an empty repo (no commits, no HEAD) should remove the index entry
    /// without crashing.
    func testUnstageInEmptyRepository() throws {
        // Empty repo — testRepo.create() already initialized it but there are no commits.

        // Create and stage a file.
        try "content".write(
            to: testRepo.tempDirectory.appendingPathComponent("new.txt"),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles(["new.txt"], at: testRepo.repositoryPath)

        // Sanity
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(staged.contains("new.txt"))

        // Act
        try LibGit2.unstageFile("new.txt", at: testRepo.repositoryPath, verbose: false)

        // Assert: entry removed from index
        let stagedAfter = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(stagedAfter.contains("new.txt"))

        // Working tree file unchanged
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: testRepo.tempDirectory.appendingPathComponent("new.txt").path
        ))
    }

    // MARK: - Working tree preservation

    /// After unstaging a modified tracked file the working-tree content must be
    /// exactly what was written — not reverted to HEAD.
    func testWorkingTreePreservedAfterUnstage() throws {
        let fileName = "preserve.txt"
        try testRepo.createFileAndCommit(
            fileName: fileName,
            content: "version 1",
            message: "Initial commit"
        )

        let fileURL = testRepo.tempDirectory.appendingPathComponent(fileName)
        try "version 2 with changes".write(to: fileURL, atomically: true, encoding: .utf8)
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)

        // Act
        try LibGit2.unstageFile(fileName, at: testRepo.repositoryPath, verbose: false)

        // Assert: working tree still has "version 2 with changes"
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, "version 2 with changes")
    }

    // MARK: - Round-trip: unstage then restage

    /// Verify that after unstaging we can stage the same file again.
    func testUnstageThenRestage() throws {
        let fileName = "roundtrip.txt"
        try testRepo.createFileAndCommit(
            fileName: fileName,
            content: "original",
            message: "Initial commit"
        )

        try "modified".write(
            to: testRepo.tempDirectory.appendingPathComponent(fileName),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)

        // Unstage
        try LibGit2.unstageFile(fileName, at: testRepo.repositoryPath, verbose: false)
        XCTAssertFalse(
            try LibGit2.getStagedFiles(at: testRepo.repositoryPath).contains(fileName)
        )

        // Restage
        try LibGit2.addFiles([fileName], at: testRepo.repositoryPath)
        XCTAssertTrue(
            try LibGit2.getStagedFiles(at: testRepo.repositoryPath).contains(fileName)
        )
    }

    // MARK: - Mixed new and tracked files

    /// Unstage a mix of new files and tracked-modified files in a single call.
    func testUnstageMixedNewAndTracked() throws {
        let tracked = "tracked.txt"
        try testRepo.createFileAndCommit(
            fileName: tracked,
            content: "original",
            message: "Initial commit"
        )

        // Modify tracked file and stage.
        try "modified tracked".write(
            to: testRepo.tempDirectory.appendingPathComponent(tracked),
            atomically: true, encoding: .utf8
        )

        // Create a new file and stage.
        let newFile = "newfile.txt"
        try "new content".write(
            to: testRepo.tempDirectory.appendingPathComponent(newFile),
            atomically: true, encoding: .utf8
        )

        try LibGit2.addFiles([tracked, newFile], at: testRepo.repositoryPath)

        // Sanity: both staged
        let stagedBefore = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(stagedBefore.contains(tracked))
        XCTAssertTrue(stagedBefore.contains(newFile))

        // Act: unstage both
        try LibGit2.unstageFiles([tracked, newFile], at: testRepo.repositoryPath, verbose: false)

        // Assert: neither staged
        let stagedAfter = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(stagedAfter.contains(tracked))
        XCTAssertFalse(stagedAfter.contains(newFile))

        // Assert: working tree untouched
        XCTAssertEqual(
            try String(contentsOf: testRepo.tempDirectory.appendingPathComponent(tracked), encoding: .utf8),
            "modified tracked"
        )
        XCTAssertEqual(
            try String(contentsOf: testRepo.tempDirectory.appendingPathComponent(newFile), encoding: .utf8),
            "new content"
        )
    }

    // MARK: - Error handling

    /// Unstaging with an invalid repo path should throw.
    func testUnstageInvalidRepository() throws {
        XCTAssertThrowsError(
            try LibGit2.unstageFile("file.txt", at: "/nonexistent/path/repo", verbose: false)
        ) { error in
            XCTAssertTrue(error is LibGit2Error)
        }
    }

    // MARK: - Array with mixed empty and valid paths

    /// An array containing both empty strings and valid paths should process
    /// only the valid paths.
    func testUnstageMixedEmptyAndValidPaths() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        let newFile = "target.txt"
        try "content".write(
            to: testRepo.tempDirectory.appendingPathComponent(newFile),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles([newFile], at: testRepo.repositoryPath)

        // Act: pass empty strings mixed with valid path
        try LibGit2.unstageFiles(["", newFile, ""], at: testRepo.repositoryPath, verbose: false)

        // Assert
        let staged = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(staged.contains(newFile))
    }
}
