import Foundation
@testable import LibGit2Swift
import XCTest

/// Diff 相关功能的测试
final class DiffTests: LibGit2SwiftTestCase {
    // MARK: - Commit Diff Files Tests

    func testGetCommitDiffFilesInitialCommit() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        guard let firstCommit = commits.first else {
            XCTFail("Should have at least one commit")
            return
        }

        // 获取初始提交的文件差异
        let diffFiles = try LibGit2.getCommitDiffFiles(atCommit: firstCommit.hash, at: testRepo.repositoryPath)

        // 验证文件列表
        XCTAssertEqual(diffFiles.count, 1, "Initial commit should have one file")
        XCTAssertEqual(diffFiles.first?.file, "initial.txt", "File name should match")
        XCTAssertEqual(diffFiles.first?.changeType, "A", "Change type should be 'A' (added)")
    }

    func testGetCommitDiffFilesWithModifications() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Content 1",
            message: "Initial commit"
        )

        // 创建第二次提交（修改文件）
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Modified content",
            message: "Modify file1"
        )

        // 创建第三次提交（添加新文件）
        try testRepo.createFileAndCommit(
            fileName: "file2.txt",
            content: "New file",
            message: "Add file2"
        )

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        XCTAssertEqual(commits.count, 3, "Should have 3 commits")

        // 由于提交按时间倒序排列：
        // commits[0]：最新的提交（添加file2.txt）
        // commits[1]：中间提交（修改file1.txt）
        // commits[2]：最旧的提交（初始添加file1.txt）

        // 验证最新的提交（添加file2.txt）
        let latestCommitFiles = try LibGit2.getCommitDiffFiles(atCommit: commits[0].hash, at: testRepo.repositoryPath)
        XCTAssertEqual(latestCommitFiles.count, 1, "Latest commit should have one added file")
        XCTAssertEqual(latestCommitFiles.first?.file, "file2.txt", "File should be file2.txt")
        XCTAssertEqual(latestCommitFiles.first?.changeType, "A", "Change type should be 'A' (added)")

        // 验证中间提交（修改file1.txt）
        let middleCommitFiles = try LibGit2.getCommitDiffFiles(atCommit: commits[1].hash, at: testRepo.repositoryPath)
        XCTAssertEqual(middleCommitFiles.count, 1, "Middle commit should have one modified file")
        XCTAssertEqual(middleCommitFiles.first?.file, "file1.txt", "File should be file1.txt")
        XCTAssertEqual(middleCommitFiles.first?.changeType, "M", "Change type should be 'M' (modified)")

        // 验证最旧的提交（初始添加file1.txt）
        let oldestCommitFiles = try LibGit2.getCommitDiffFiles(atCommit: commits[2].hash, at: testRepo.repositoryPath)
        XCTAssertEqual(oldestCommitFiles.count, 1, "Oldest commit should have one added file")
        XCTAssertEqual(oldestCommitFiles.first?.file, "file1.txt", "File should be file1.txt")
        XCTAssertEqual(oldestCommitFiles.first?.changeType, "A", "Change type should be 'A' (added)")
    }

    func testGetCommitDiffFilesWithDeletions() throws {
        // 创建初始提交（两个文件）
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Content 1",
            message: "Add file1"
        )

        try testRepo.createFileAndCommit(
            fileName: "file2.txt",
            content: "Content 2",
            message: "Add file2"
        )

        // 删除一个文件
        let fileURL = testRepo.tempDirectory.appendingPathComponent("file1.txt")
        try FileManager.default.removeItem(at: fileURL)

        try LibGit2.addFiles(["file1.txt"], at: testRepo.repositoryPath)
        _ = try LibGit2.createCommit(message: "Delete file1", at: testRepo.repositoryPath)

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)

        // 验证删除提交
        let lastCommitFiles = try LibGit2.getCommitDiffFiles(atCommit: commits.first!.hash, at: testRepo.repositoryPath)
        XCTAssertTrue(lastCommitFiles.contains { $0.file == "file1.txt" }, "Should have deleted file1.txt")
        XCTAssertTrue(lastCommitFiles.contains { $0.changeType == "D" }, "Should have deleted file")
    }

    func testGetCommitDiffFilesMultipleChanges() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Content 1",
            message: "Initial commit"
        )

        // 在第二次提交中修改多个文件
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Modified file1",
            message: "Modify file1"
        )

        try testRepo.createFileAndCommit(
            fileName: "file2.txt",
            content: "New file2",
            message: "Add file2"
        )

        try testRepo.createFileAndCommit(
            fileName: "file3.txt",
            content: "New file3",
            message: "Add file3"
        )

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)

        // 验证每个提交
        for (index, commit) in commits.enumerated() {
            let diffFiles = try LibGit2.getCommitDiffFiles(atCommit: commit.hash, at: testRepo.repositoryPath)
            XCTAssertTrue(diffFiles.count > 0, "Commit \(index) should have at least one changed file")
        }
    }

    func testGetCommitDiffFilesIncludesDiffContent() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Original content",
            message: "Initial commit"
        )

        // 修改文件
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Modified content with changes",
            message: "Modify test file"
        )

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)

        // 获取第二次提交的差异
        let diffFiles = try LibGit2.getCommitDiffFiles(atCommit: commits[1].hash, at: testRepo.repositoryPath)

        guard let diffFile = diffFiles.first else {
            XCTFail("Should have at least one diff file")
            return
        }

        // 验证差异内容不为空
        XCTAssertFalse(diffFile.diff.isEmpty, "Diff content should not be empty")
        XCTAssertTrue(diffFile.diff.contains("test.txt"), "Diff should contain file name")
    }

    func testGetCommitDiffFilesEmptyRepository() throws {
        // 空仓库不应该有提交
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        XCTAssertTrue(commits.isEmpty, "Empty repository should have no commits")
    }

    func testGetCommitDiffFilesInvalidCommitHash() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Content",
            message: "Initial commit"
        )

        // 尝试使用无效的commit hash
        XCTAssertThrowsError(
            try LibGit2.getCommitDiffFiles(atCommit: "invalid_hash_12345", at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for invalid commit hash")
        }
    }

    // MARK: - Diff File List Tests (Workdir/Index)

    func testGetDiffFileListUnstaged() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Original content",
            message: "Initial commit"
        )

        // 修改文件（不添加到暂存区）
        let fileURL = testRepo.tempDirectory.appendingPathComponent("test.txt")
        try "Modified content".write(to: fileURL, atomically: true, encoding: .utf8)

        // 获取未暂存的差异
        let diffFiles = try LibGit2.getDiffFileList(at: testRepo.repositoryPath, staged: false)

        XCTAssertTrue(diffFiles.count > 0, "Should have unstaged changes")
        XCTAssertTrue(diffFiles.contains { $0.file == "test.txt" }, "Should have test.txt in diff")
    }

    func testGetDiffFileListStaged() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Original content",
            message: "Initial commit"
        )

        // 修改文件并添加到暂存区
        let fileURL = testRepo.tempDirectory.appendingPathComponent("test.txt")
        try "Modified content".write(to: fileURL, atomically: true, encoding: .utf8)

        try LibGit2.addFiles(["test.txt"], at: testRepo.repositoryPath)

        // 获取已暂存的差异
        let diffFiles = try LibGit2.getDiffFileList(at: testRepo.repositoryPath, staged: true)

        XCTAssertTrue(diffFiles.count > 0, "Should have staged changes")
        XCTAssertTrue(diffFiles.contains { $0.file == "test.txt" }, "Should have test.txt in staged diff")
    }

    func testGetDiffFileListCleanRepository() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Content",
            message: "Initial commit"
        )

        // 干净的仓库不应该有差异
        let unstagedDiff = try LibGit2.getDiffFileList(at: testRepo.repositoryPath, staged: false)
        let stagedDiff = try LibGit2.getDiffFileList(at: testRepo.repositoryPath, staged: true)

        XCTAssertEqual(unstagedDiff.count, 0, "Should have no unstaged changes")
        XCTAssertEqual(stagedDiff.count, 0, "Should have no staged changes")
    }
}
