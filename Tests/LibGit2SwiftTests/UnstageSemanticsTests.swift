import Foundation
@testable import LibGit2Swift
import XCTest

/// Regression tests that pin `unstageFiles()` to the exact semantics of
/// `git reset -- <paths>`.
final class UnstageSemanticsTests: LibGit2SwiftTestCase {

    /// Unstaging a staged deletion restores the path into the index (HEAD
    /// version) and leaves the file deleted in the working tree.
    func testUnstageStagedDeletionRestoresIndexEntry() throws {
        try testRepo.createFileAndCommit(
            fileName: "doomed.txt",
            content: "doomed",
            message: "Initial commit"
        )

        try FileManager.default.removeItem(
            at: testRepo.tempDirectory.appendingPathComponent("doomed.txt")
        )
        try LibGit2.addFiles(["doomed.txt"], at: testRepo.repositoryPath)

        // Sanity: the deletion is staged.
        let stagedBefore = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(stagedBefore.contains("doomed.txt"))

        // Act
        try LibGit2.unstageFile("doomed.txt", at: testRepo.repositoryPath, verbose: false)

        // Assert: the index entry is back, matching `git reset HEAD -- <path>`.
        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertTrue(entries.contains("doomed.txt"))
    }

    /// Unstaging a file that was never staged must not add an index entry.
    func testUnstageUntrackedFileDoesNotAddIndexEntry() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        try "untracked".write(
            to: testRepo.tempDirectory.appendingPathComponent("untracked.txt"),
            atomically: true, encoding: .utf8
        )

        try LibGit2.unstageFile("untracked.txt", at: testRepo.repositoryPath, verbose: false)

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertFalse(entries.contains("untracked.txt"))
    }

    /// Unstaging a path that does not exist at all is a silent no-op.
    func testUnstageUnknownPathIsNoOp() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        XCTAssertNoThrow(
            try LibGit2.unstageFile("does/not/exist.txt", at: testRepo.repositoryPath, verbose: false)
        )

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertEqual(entries, ["initial.txt"])
    }

    /// Unstaging restores the index entry to the HEAD blob id, so the staged
    /// diff for that path disappears entirely.
    func testUnstageRemovesStagedDiffForPath() throws {
        try testRepo.createFileAndCommit(
            fileName: "tracked.txt",
            content: "original",
            message: "Initial commit"
        )

        try "modified".write(
            to: testRepo.tempDirectory.appendingPathComponent("tracked.txt"),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles(["tracked.txt"], at: testRepo.repositoryPath)

        let stagedBefore = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(stagedBefore.contains("tracked.txt"))

        try LibGit2.unstageFile("tracked.txt", at: testRepo.repositoryPath, verbose: false)

        let stagedAfter = try LibGit2.getStagedFiles(at: testRepo.repositoryPath)
        XCTAssertFalse(stagedAfter.contains("tracked.txt"))

        // The change is still present, now as an unstaged modification.
        let unstaged = try LibGit2.getUnstagedFiles(at: testRepo.repositoryPath)
        XCTAssertTrue(unstaged.contains("tracked.txt"))
    }
}
