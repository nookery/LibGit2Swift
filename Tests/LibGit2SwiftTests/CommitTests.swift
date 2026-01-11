import Foundation
@testable import LibGit2Swift
import XCTest

/// Commit 相关功能的测试
final class CommitTests: LibGit2SwiftTestCase {
    // MARK: - Commit List Tests

    func testGetCommitListEmptyRepository() throws {
        // 空仓库应该没有提交
        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        XCTAssertTrue(commits.isEmpty, "Empty repository should have no commits")
    }

    func testGetCommitListSingleCommit() throws {
        // 创建单个提交
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Content 1",
            message: "First commit"
        )

        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)

        XCTAssertEqual(commits.count, 1, "Should have exactly one commit")
        XCTAssertEqual(commits.first?.message, "First commit", "Commit message should match")
    }

    func testGetCommitListMultipleCommits() throws {
        // 创建多个提交
        try testRepo.createFileAndCommit(
            fileName: "file1.txt",
            content: "Content 1",
            message: "Commit 1"
        )

        try testRepo.createFileAndCommit(
            fileName: "file2.txt",
            content: "Content 2",
            message: "Commit 2"
        )

        try testRepo.createFileAndCommit(
            fileName: "file3.txt",
            content: "Content 3",
            message: "Commit 3"
        )

        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)

        XCTAssertEqual(commits.count, 3, "Should have exactly three commits")

        // 验证提交顺序（最新的在前）
        XCTAssertEqual(commits[0].message, "Commit 3", "First commit should be the latest")
        XCTAssertEqual(commits[1].message, "Commit 2", "Second commit should be the middle")
        XCTAssertEqual(commits[2].message, "Commit 1", "Third commit should be the oldest")
    }

    // MARK: - Commit Pagination Tests

    func testGetCommitListWithPagination() throws {
        // 创建多个提交
        for i in 1...10 {
            try testRepo.createFileAndCommit(
                fileName: "file\(i).txt",
                content: "Content \(i)",
                message: "Commit \(i)"
            )
        }

        // 获取第一页
        let page1 = try LibGit2.getCommitListWithPagination(at: testRepo.repositoryPath, page: 0, size: 3)
        XCTAssertEqual(page1.count, 3, "First page should have 3 commits")

        // 获取第二页
        let page2 = try LibGit2.getCommitListWithPagination(at: testRepo.repositoryPath, page: 1, size: 3)
        XCTAssertEqual(page2.count, 3, "Second page should have 3 commits")

        // 验证不同页的提交不同
        let page1Hashes = Set(page1.map { $0.hash })
        let page2Hashes = Set(page2.map { $0.hash })
        let intersection = page1Hashes.intersection(page2Hashes)
        XCTAssertTrue(intersection.isEmpty, "Different pages should have different commits")
    }

    func testGetCommitListWithPaginationBeyondEnd() throws {
        // 创建几个提交
        for i in 1...3 {
            try testRepo.createFileAndCommit(
                fileName: "file\(i).txt",
                content: "Content \(i)",
                message: "Commit \(i)"
            )
        }

        // 请求超出范围的页
        let page = try LibGit2.getCommitListWithPagination(at: testRepo.repositoryPath, page: 10, size: 3)
        XCTAssertTrue(page.isEmpty, "Page beyond available commits should be empty")
    }

    // MARK: - Commit Detail Tests

    func testGetCommitDetail() throws {
        // 创建提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Test commit message",
            authorName: "Test Author",
            authorEmail: "test@author.com"
        )

        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        guard let commit = commits.first else {
            XCTFail("Should have at least one commit")
            return
        }

        // 获取详细信息
        let detail = try LibGit2.getCommitDetail(commitHash: commit.hash, at: testRepo.repositoryPath)

        XCTAssertNotNil(detail, "Commit detail should not be nil")
        XCTAssertEqual(detail?.message, "Test commit message", "Message should match")
        XCTAssertEqual(detail?.author, "Test Author", "Author should match")
        XCTAssertEqual(detail?.email, "test@author.com", "Email should match")
        XCTAssertNotNil(detail?.date, "Date should not be nil")
        XCTAssertNotNil(detail?.hash, "Hash should not be nil")
    }

    // MARK: - Commit Properties Tests

    func testCommitProperties() throws {
        // 创建提交
        let testMessage = "Test commit with properties"
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: testMessage
        )

        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        guard let commit = commits.first else {
            XCTFail("Should have at least one commit")
            return
        }

        // 验证必需属性
        XCTAssertFalse(commit.id.isEmpty, "Commit ID should not be empty")
        XCTAssertFalse(commit.hash.isEmpty, "Commit hash should not be empty")
        XCTAssertFalse(commit.author.isEmpty, "Author should not be empty")
        XCTAssertFalse(commit.email.isEmpty, "Email should not be empty")
        XCTAssertEqual(commit.message, testMessage, "Message should match")
        XCTAssertEqual(commit.body, testMessage, "Body should match message for simple commit")
        XCTAssertNotNil(commit.date, "Date should not be nil")

        // refs 和 tags 可以为空
        XCTAssertNotNil(commit.refs, "Refs should not be nil")
        XCTAssertNotNil(commit.tags, "Tags should not be nil")
    }

    // MARK: - Branch Commit Tests

    func testGetCommitsOnBranch() throws {
        // 创建主分支提交
        for i in 1...3 {
            try testRepo.createFileAndCommit(
                fileName: "main\(i).txt",
                content: "Main content \(i)",
                message: "Main commit \(i)"
            )
        }

        // 创建并切换到新分支
        let branchName = TestDataGenerator.randomBranchName()
        try LibGit2.createBranch(named: branchName, at: testRepo.repositoryPath)

        // 在新分支上创建提交
        for i in 1...2 {
            try testRepo.createFileAndCommit(
                fileName: "branch\(i).txt",
                content: "Branch content \(i)",
                message: "Branch commit \(i)"
            )
        }

        // 获取主分支的提交
        let mainCommits = try LibGit2.getCommitList(on: "master", at: testRepo.repositoryPath)
        XCTAssertGreaterThanOrEqual(mainCommits.count, 5, "Main branch should have at least 5 commits")

        // 获取新分支的提交
        let branchCommits = try LibGit2.getCommitList(on: branchName, at: testRepo.repositoryPath)
        XCTAssertGreaterThanOrEqual(branchCommits.count, 2, "New branch should have at least 2 commits")
    }

    // MARK: - Commit with Tags Tests

    func testGetCommitWithTags() throws {
        // 创建提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Tagged commit"
        )

        let commits = try LibGit2.getCommitList(at: testRepo.repositoryPath)
        guard let commit = commits.first else {
            XCTFail("Should have at least one commit")
            return
        }

        // 创建标签
        try testRepo.createTag(tagName: "v1.0.0", message: "Version 1.0.0")

        // 重新获取提交列表以包含标签信息
        let updatedCommits = try LibGit2.getCommitList(at: testRepo.repositoryPath)

        // 验证标签信息
        let hasTag = updatedCommits.contains { commit in
            commit.tags.contains("v1.0.0")
        }

        XCTAssertTrue(hasTag, "Commit should have tag information")
    }

    // MARK: - Error Handling Tests

    func testGetCommitDetailInvalidHash() throws {
        // 创建提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Test commit"
        )

        let invalidHash = "invalid_hash_12345"

        // 尝试获取不存在的提交详情
        XCTAssertThrowsError(
            try LibGit2.getCommitDetail(commitHash: invalidHash, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for invalid hash")
        }
    }

    func testGetCommitsOnNonExistentBranch() throws {
        // 创建初始提交
        try testRepo.createFileAndCommit(
            fileName: "test.txt",
            content: "Test content",
            message: "Initial commit"
        )

        let nonExistentBranch = "nonexistent_branch"

        // 尝试获取不存在分支的提交
        XCTAssertThrowsError(
            try LibGit2.getCommitList(on: nonExistentBranch, at: testRepo.repositoryPath)
        ) { error in
            XCTAssertTrue(error is LibGit2Error, "Should throw LibGit2Error for non-existent branch")
        }
    }

    // MARK: - Performance Tests

    func testCommitListPerformance() throws {
        // 创建多个提交
        for i in 1...50 {
            try testRepo.createFileAndCommit(
                fileName: "file\(i).txt",
                content: "Content \(i)",
                message: "Commit \(i)"
            )
        }

        // 测试获取提交列表的性能
        measure {
            _ = try? LibGit2.getCommitList(at: testRepo.repositoryPath)
        }
    }
}
