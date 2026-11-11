import Clibgit2
import Foundation
import XCTest
@testable import LibGit2Swift

/// 锁定 1.0.7 / 1.1.0 分叉期间被回退的能力。
///
/// 背景：1.0.7 与 1.1.0 曾从共同祖先分叉，各自只保留了一半的能力 ——
/// 1.0.7 带回短哈希解析、上游分支查询与 `git_repository_open_ext`，
/// 1.1.0 带回 `getIndexEntries()`。合并后 `main` 同时拥有两者。
///
/// 这些用例把合并结果钉死，避免将来任何一条线单独演进时再次丢失对方的能力。
final class ForkRegressionTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        try await super.setUp()
        LibGit2.initialize()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibGit2SwiftForkRegressionTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
        LibGit2.shutdown()
        try await super.tearDown()
    }

    // MARK: - 短哈希解析（来自 1.0.7，1.1.0 丢失）

    func testGetCommitDetailResolvesAbbreviatedHash() throws {
        let repo = try makeRepository(named: "abbreviated-detail")
        let fullHash = try commit(in: repo, file: "a.txt", content: "a", message: "first")

        // 7 位短哈希必须能查到详情，否则 git log 展示的短哈希点不开。
        let shortHash = String(fullHash.prefix(7))
        let detail = try LibGit2.getCommitDetail(commitHash: shortHash, at: repo.path)

        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.hash, fullHash)
    }

    func testGetCommitDiffFilesResolvesAbbreviatedHash() throws {
        let repo = try makeRepository(named: "abbreviated-diff")
        let fullHash = try commit(in: repo, file: "a.txt", content: "a", message: "first")
        try commit(in: repo, file: "b.txt", content: "b", message: "second")

        let shortHash = String(fullHash.prefix(7))
        let files = try LibGit2.getCommitDiffFiles(atCommit: shortHash, at: repo.path)

        XCTAssertEqual(files.map(\.file), ["a.txt"])
    }

    func testAbbreviatedHashThatIsAmbiguousOrInvalidThrows() throws {
        let repo = try makeRepository(named: "invalid-abbreviated")
        try commit(in: repo, file: "a.txt", content: "a", message: "first")

        // 非法哈希必须抛错，而不是静默返回空结果。
        XCTAssertThrowsError(
            try LibGit2.getCommitDetail(commitHash: "zzzzzzz", at: repo.path)
        )
    }

    // MARK: - 上游分支查询（来自 1.0.7，1.1.0 丢失）

    func testGetUpstreamBranchNameReturnsConfiguredUpstream() throws {
        let remote = try makeBareRemote(named: "upstream-remote")
        let local = try makeRepository(named: "upstream-local")
        try commit(in: local, file: "README.md", content: "v1", message: "Initial commit")
        try runGit(["remote", "add", "origin", remote.path], in: local)
        try runGit(["push", "-u", "origin", "main"], in: local)

        XCTAssertEqual(try LibGit2.getUpstreamBranchName(at: local.path), "origin/main")
    }

    func testGetUpstreamBranchNameReturnsNilWithoutUpstream() throws {
        let repo = try makeRepository(named: "upstream-missing")
        try commit(in: repo, file: "a.txt", content: "a", message: "first")

        XCTAssertNil(try LibGit2.getUpstreamBranchName(at: repo.path))
    }

    // MARK: - 子目录打开仓库（来自 1.0.7，1.1.0 丢失）

    func testOpenRepositoryResolvesFromSubdirectory() throws {
        let repo = try makeRepository(named: "subdirectory")
        try commit(in: repo, file: "a.txt", content: "a", message: "first")

        let nested = repo.appendingPathComponent("nested/deeper")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        // 传入工作树内的子目录，必须解析到所属仓库，而不是报 repositoryNotFound。
        let opened = try LibGit2.openRepository(at: nested.path)
        defer { git_repository_free(opened) }

        let workdir = git_repository_workdir(opened).map { String(cString: $0) }
        XCTAssertNotNil(workdir)

        // 仓库根可能经 /var -> /private/var 符号链接，比较时统一解析真实路径。
        let expected = URL(fileURLWithPath: repo.path).resolvingSymlinksInPath().path
        let actual = workdir.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        XCTAssertEqual(actual, expected)
    }

    // MARK: - 索引条目读取（来自 1.1.0，1.0.7 缺失）

    func testGetIndexEntriesListsStagedFiles() throws {
        let repo = try makeRepository(named: "index-entries")
        try commit(in: repo, file: "a.txt", content: "a", message: "first")

        try "staged".write(
            to: repo.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "staged.txt"], in: repo)

        let entries = try LibGit2.getIndexEntries(at: repo.path)
        let paths = entries

        XCTAssertTrue(paths.contains("a.txt"))
        XCTAssertTrue(paths.contains("staged.txt"))
    }

    // MARK: - 测试脚手架

    private func makeRepository(named name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "--initial-branch=main", url.path], in: root)
        try runGit(["config", "user.name", "Test User"], in: url)
        try runGit(["config", "user.email", "test@example.com"], in: url)
        return url
    }

    private func makeBareRemote(named name: String) throws -> URL {
        let url = root.appendingPathComponent("\(name).git")
        try runGit(["init", "--bare", url.path], in: root)
        return url
    }

    @discardableResult
    private func commit(in repo: URL, file: String, content: String, message: String) throws -> String {
        try content.write(
            to: repo.appendingPathComponent(file),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", file], in: repo)
        try runGit(["commit", "-m", message], in: repo)
        return try runGit(["rev-parse", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ForkRegressionTests.git",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "git failed",
                ]
            )
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }
}
