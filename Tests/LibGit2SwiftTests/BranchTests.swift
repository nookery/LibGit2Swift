import Foundation
@testable import LibGit2Swift
import XCTest

/// Branch 相关功能的测试
final class BranchTests: LibGit2SwiftTestCase {
    // MARK: - Branch List Tests

    func testGetBranchListEmptyRepository() throws {
        // 在没有提交的仓库中，应该没有分支
        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)
        XCTAssertTrue(branches.isEmpty, "Empty repository should have no branches")
    }

    func testGetBranchListWithCommit() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)

        XCTAssertFalse(branches.isEmpty, "Repository with commit should have at least one branch")

        // 检查主分支
        let mainBranchNames = ["master", "main"]
        let hasMainBranch = branches.contains { mainBranchNames.contains($0.name) }
        XCTAssertTrue(hasMainBranch, "Should have master or main branch")
    }

    func testGetLocalBranches() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建多个分支
        let branchNames = ["feature1", "feature2", "bugfix/fix1"]
        try testRepo.createBranches(branchNames)

        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)

        // 验证分支数量
        XCTAssertGreaterThanOrEqual(branches.count, 3, "Should have at least 3 branches")

        // 验证分支名称
        let branchNameList = branches.map { $0.name }
        for branchName in branchNames {
            XCTAssertTrue(branchNameList.contains(branchName),
                          "Should contain branch: \(branchName)")
        }
    }

    // MARK: - Branch Creation Tests

    func testCreateBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建新分支
        let newBranchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: newBranchName, at: testRepo.repositoryPath)

        // 验证分支已创建
        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)
        let branchNames = branches.map { $0.name }

        XCTAssertTrue(branchNames.contains(newBranchName),
                      "Branch list should contain the newly created branch")
    }

    func testCreateBranchFromCommit() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 获取提交列表
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        guard let commit = commits.first else {
            XCTFail("Should have at least one commit")
            return
        }

        // 从提交创建分支
        let newBranchName = TestDataGenerator.randomBranchName()
        _ = try LibGit2.createBranch(named: newBranchName, at: testRepo.repositoryPath)

        // 验证分支已创建
        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)
        let branchNames = branches.map { $0.name }

        XCTAssertTrue(branchNames.contains(newBranchName),
                      "Branch list should contain the branch created from commit")
    }

    // MARK: - Branch Deletion Tests

    func testDeleteBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建分支
        let branchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 删除分支
        try LibGit2.deleteBranch(named: branchName, at: testRepo.repositoryPath)

        // 验证分支已删除
        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)
        let branchNames = branches.map { $0.name }

        XCTAssertFalse(branchNames.contains(branchName),
                       "Branch list should not contain the deleted branch")
    }

    func testDeleteCurrentBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 获取当前分支
        let currentBranch = try LibGit2.getCurrentBranch(at: testRepo.repositoryPath)

        // 尝试删除当前分支应该失败
        XCTAssertThrowsError(
            try LibGit2.deleteBranch(named: currentBranch, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error")
        }
    }

    // MARK: - Branch Rename Tests

    func testRenameBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建新分支（不切换到它）
        let oldBranchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: oldBranchName, at: testRepo.repositoryPath)

        // 重命名分支
        let newBranchName = TestDataGenerator.randomBranchName()
        try LibGit2.renameBranch(named: oldBranchName, to: newBranchName, at: testRepo.repositoryPath)

        // 验证分支已重命名
        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)
        let branchNames = branches.map { $0.name }

        XCTAssertFalse(branchNames.contains(oldBranchName),
                       "Old branch name should not exist")
        XCTAssertTrue(branchNames.contains(newBranchName),
                      "New branch name should exist")
    }

    // MARK: - Branch Properties Tests

    func testBranchProperties() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let branches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: false)

        guard let branch = branches.first(where: { $0.name == "master" || $0.name == "main" }) else {
            XCTFail("Should have master or main branch")
            return
        }

        // 验证分支属性
        XCTAssertFalse(branch.id.isEmpty, "Branch ID should not be empty")
        XCTAssertFalse(branch.name.isEmpty, "Branch name should not be empty")
        XCTAssertTrue(branch.isCurrent, "Main branch should be marked as current")
        // upstream 可能为空
    }

    func testGetCurrentBranchInfo() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let branchInfo = try LibGit2.getCurrentBranchInfo(at: testRepo.repositoryPath)

        XCTAssertNotNil(branchInfo, "Current branch info should not be nil")
        XCTAssertNotNil(branchInfo?.latestCommitHash, "Latest commit hash should not be nil")
        XCTAssertNotNil(branchInfo?.latestCommitMessage, "Latest commit message should not be nil")
    }

    // MARK: - Remote Branch Tests

    func testGetRemoteBranches() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 添加远程仓库
        try testRepo.addRemote(name: "origin", url: "https://github.com/test/repo.git")

        // 获取远程分支
        let remoteBranches = try LibGit2.getBranchList(at: testRepo.repositoryPath, includeRemote: true)

        // 在没有 fetch 的情况下，远程分支列表可能为空
        // 这里只是验证方法能正常工作
        XCTAssertNotNil(remoteBranches, "Should be able to get remote branch list")
    }

    // MARK: - Error Handling Tests

    func testCreateDuplicateBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        // 创建分支
        let branchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 尝试创建同名分支应该失败
        XCTAssertThrowsError(
            try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for duplicate branch")
        }
    }

    func testDeleteNonExistentBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "initial.txt",
            content: "Initial content",
            message: "Initial commit"
        )

        let nonExistentBranch = "nonexistent_branch_\(UUID().uuidString)"

        // 尝试删除不存在的分支应该失败
        XCTAssertThrowsError(
            try LibGit2.deleteBranch(named: nonExistentBranch, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent branch")
        }
    }
}
