import Foundation
@testable import LibGit2Swift
import XCTest

/// Tests for `getIndexEntries()` — the Swift equivalent of `git ls-files`.
final class IndexTests: LibGit2SwiftTestCase {

    // MARK: - Empty repository

    /// An empty repository (no commits, nothing staged) has an empty index.
    func testIndexEntriesInEmptyRepository() throws {
        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Basic listing

    /// Committed files appear in the index.
    func testIndexEntriesContainsCommittedFiles() throws {
        try testRepo.createFileAndCommit(
            fileName: "committed.txt",
            content: "committed",
            message: "Initial commit"
        )

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertEqual(entries, ["committed.txt"])
    }

    /// Newly staged files appear in the index even though they are not in HEAD.
    func testIndexEntriesIncludesStagedNewFile() throws {
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "initial",
            message: "Initial commit"
        )

        try "new".write(
            to: testRepo.tempDirectory.appendingPathComponent("staged_new.txt"),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles(["staged_new.txt"], at: testRepo.repositoryPath)

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertTrue(entries.contains("staged_new.txt"))

        // The HEAD tree does not know about it yet.
        let tracked = try LibGit2.getTrackedFilePaths(at: testRepo.repositoryPath)
        XCTAssertFalse(tracked.contains("staged_new.txt"))
    }

    /// A staged deletion removes the path from the index (git records the
    /// deletion by dropping the entry), while HEAD still knows the file.
    func testIndexEntriesReflectsStagedDeletion() throws {
        try testRepo.createFileAndCommit(
            fileName: "doomed.txt",
            content: "doomed",
            message: "Initial commit"
        )

        try FileManager.default.removeItem(
            at: testRepo.tempDirectory.appendingPathComponent("doomed.txt")
        )
        try LibGit2.addFiles(["doomed.txt"], at: testRepo.repositoryPath)

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertFalse(entries.contains("doomed.txt"))

        // HEAD still tracks the file.
        let tracked = try LibGit2.getTrackedFilePaths(at: testRepo.repositoryPath)
        XCTAssertTrue(tracked.contains("doomed.txt"))
    }

    /// Untracked (never staged) files are not part of the index.
    func testIndexEntriesExcludesUntrackedFiles() throws {
        try testRepo.createFileAndCommit(
            fileName: "tracked.txt",
            content: "tracked",
            message: "Initial commit"
        )

        try "untracked".write(
            to: testRepo.tempDirectory.appendingPathComponent("untracked.txt"),
            atomically: true, encoding: .utf8
        )

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertTrue(entries.contains("tracked.txt"))
        XCTAssertFalse(entries.contains("untracked.txt"))
    }

    // MARK: - Nested paths

    /// Files in subdirectories are listed with forward-slash relative paths.
    func testIndexEntriesIncludesNestedPaths() throws {
        let nested = testRepo.tempDirectory.appendingPathComponent("dir/sub")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "nested".write(
            to: nested.appendingPathComponent("file.txt"),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles(["dir/sub/file.txt"], at: testRepo.repositoryPath)

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        XCTAssertTrue(entries.contains("dir/sub/file.txt"))
    }

    // MARK: - Conflicts

    /// A conflicted path is stored in the index as stage 1/2/3 entries.
    /// The result must be de-duplicated, matching `git ls-files`.
    func testIndexEntriesDeduplicatesConflictedPaths() throws {
        try testRepo.createFileAndCommit(
            fileName: "conflict.txt",
            content: "base",
            message: "Initial commit"
        )

        try LibGit2.createBranch(named: "feature", at: testRepo.repositoryPath)
        try LibGit2.checkout(branch: "feature", at: testRepo.repositoryPath)

        try "feature content".write(
            to: testRepo.tempDirectory.appendingPathComponent("conflict.txt"),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles(["conflict.txt"], at: testRepo.repositoryPath)
        _ = try LibGit2.createCommit(message: "feature change", at: testRepo.repositoryPath, verbose: false)

        try LibGit2.checkout(branch: "main", at: testRepo.repositoryPath)

        try "main content".write(
            to: testRepo.tempDirectory.appendingPathComponent("conflict.txt"),
            atomically: true, encoding: .utf8
        )
        try LibGit2.addFiles(["conflict.txt"], at: testRepo.repositoryPath)
        _ = try LibGit2.createCommit(message: "main change", at: testRepo.repositoryPath, verbose: false)

        // Merge feature into main → conflict.
        _ = try? LibGit2.merge(branchName: "feature", at: testRepo.repositoryPath, verbose: false)

        let conflicted = try LibGit2.getConflictedPaths(at: testRepo.repositoryPath)
        XCTAssertTrue(conflicted.contains("conflict.txt"), "Expected a conflict to be produced")

        let entries = try LibGit2.getIndexEntries(at: testRepo.repositoryPath)
        let occurrences = entries.filter { $0 == "conflict.txt" }
        XCTAssertEqual(occurrences.count, 1, "Conflicted path must be listed only once")
    }

    // MARK: - Cancellation

    /// A pre-cancelled token aborts the operation.
    func testIndexEntriesRespectsCancellation() throws {
        try testRepo.createFileAndCommit(
            fileName: "committed.txt",
            content: "committed",
            message: "Initial commit"
        )

        let token = GitCancellationToken()
        token.cancel()

        XCTAssertThrowsError(
            try LibGit2.getIndexEntries(at: testRepo.repositoryPath, cancellation: token)
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Errors

    /// An invalid repository path throws.
    func testIndexEntriesInvalidRepository() throws {
        XCTAssertThrowsError(
            try LibGit2.getIndexEntries(at: "/nonexistent/path/repo")
        ) { error in
            XCTAssertTrue(error is LibGit2Error)
        }
    }
}
