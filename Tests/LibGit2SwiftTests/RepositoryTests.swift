import Foundation
@testable import LibGit2Swift
import XCTest

/// Repository 相关功能的测试
final class RepositoryTests: LibGit2SwiftTestCase {
    // MARK: - Repository Detection Tests

    func testIsGitRepositoryValid() throws {
        // 创建的测试仓库应该被识别为 Git 仓库
        let isValid = try LibGit2.isGitRepository(at: testRepo.repositoryPath)
        XCTAssertTrue(isValid, "Created repository should be a valid Git repository")
    }

    func testIsGitRepositoryInvalid() throws {
        // 创建一个非 Git 目录
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibGit2SwiftTests")
            .appendingPathComponent("invalid_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let isValid = try LibGit2.isGitRepository(at: tempDir.path)
        XCTAssertFalse(isValid, "Non-Git directory should not be recognized as a Git repository")
    }

    func testGetRepositoryRoot() throws {
        // 创建子目录
        let subDir = testRepo.tempDirectory.appendingPathComponent("subdirectory")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        // 从子目录获取仓库根目录
        let rootPath = LibGit2.repositoryRoot(at: subDir.path)

        XCTAssertNotNil(rootPath, "Repository root should not be nil")
        XCTAssertEqual(rootPath, testRepo.repositoryPath,
                      "Repository root should be the test repository path")
    }

    func testIsRepositoryEmpty() throws {
        // 新创建的仓库应该是空的
        let isEmpty = try LibGit2.isEmptyRepository(at: testRepo.repositoryPath)
        XCTAssertTrue(isEmpty, "Newly created repository should be empty")

        // 创建一个提交后，仓库应该不再是空的
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Initial commit"
        )

        let isNotEmpty = try LibGit2.isEmptyRepository(at: testRepo.repositoryPath)
        XCTAssertFalse(isNotEmpty, "Repository with commits should not be empty")
    }

    func testGetGitDirectory() throws {
        let gitDir = try LibGit2.gitDirectory(at: testRepo.repositoryPath)

        let expectedGitDir = testRepo.tempDirectory.appendingPathComponent(".git").path
        XCTAssertEqual(gitDir, expectedGitDir, "Git directory path should be correct")
    }

    // MARK: - HEAD Reference Tests

    func testGetHEADReference() throws {
        // 在空仓库中，HEAD 应该指向 master (或 main)
        let headRef = try LibGit2.getHEAD(at: testRepo.repositoryPath)

        XCTAssertTrue(headRef == "master" || headRef == "main",
                      "HEAD should reference master or main branch in new repository")
    }

    func testGetHEADReferenceWithCommit() throws {
        // 创建提交后检查 HEAD
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Initial commit"
        )

        let headRef = try LibGit2.getHEAD(at: testRepo.repositoryPath)

        XCTAssertFalse(headRef.isEmpty, "HEAD reference should not be empty")
    }

    func testIsHEADDetached() throws {
        // 新仓库的 HEAD 不应该处于分离状态
        let isDetached = try LibGit2.isHEADDetached(at: testRepo.repositoryPath)
        XCTAssertFalse(isDetached, "HEAD should not be detached in new repository")
    }

    // MARK: - Current Branch Tests

    func testGetCurrentBranch() throws {
        // 在新仓库中获取当前分支
        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)

        XCTAssertTrue(currentBranch == "master" || currentBranch == "main",
                      "Current branch should be master or main in new repository")
    }

    func testGetCurrentBranchWithCommit() throws {
        // 创建提交后获取当前分支
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Initial commit"
        )

        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)

        XCTAssertFalse(currentBranch.isEmpty, "Current branch name should not be empty")
    }

    // MARK: - Branch Detection Tests

    func testGetCurrentBranchInfo() throws {
        // 创建提交以初始化分支
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Initial commit"
        )

        let branchInfo = try LibGit2.getCurrentBranchInfo(at: testRepo.repositoryPath)

        XCTAssertNotNil(branchInfo, "Branch info should not be nil")
        XCTAssertFalse(branchInfo?.name.isEmpty ?? true, "Branch name should not be empty")
        XCTAssertTrue(branchInfo?.isCurrent ?? false, "Branch should be marked as current")
    }

    // MARK: - Error Handling Tests

    func testInvalidPathError() throws {
        // 测试无效路径的错误处理 - isGitRepository 不会抛出错误，而是返回 false
        let isValid = LibGit2.isGitRepository(at: "/nonexistent/path/that/does/not/exist")
        XCTAssertFalse(isValid, "Non-existent path should not be a Git repository")
    }

    func testGetRepositoryRootOutsideGit() throws {
        // 在 Git 仓库外的目录获取根目录应该返回 nil
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibGit2SwiftTests")
            .appendingPathComponent("nongit_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let rootPath = LibGit2.repositoryRoot(at: tempDir.path)
        XCTAssertNil(rootPath, "Repository root should be nil when outside Git repo")
    }
}
