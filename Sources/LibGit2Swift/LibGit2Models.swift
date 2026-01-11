import Foundation

/// Git 分支模型
public struct GitBranch: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let isCurrent: Bool
    public let upstream: String?
    public let latestCommitHash: String
    public let latestCommitMessage: String

    public init(id: String, name: String, isCurrent: Bool, upstream: String?, latestCommitHash: String, latestCommitMessage: String) {
        self.id = id
        self.name = name
        self.isCurrent = isCurrent
        self.upstream = upstream
        self.latestCommitHash = latestCommitHash
        self.latestCommitMessage = latestCommitMessage
    }
}

/// Git 提交模型
public struct GitCommit: Identifiable, Codable, Hashable {
    public let id: String
    public let hash: String
    public let author: String
    public let email: String
    public let date: Date
    public let message: String
    public let body: String
    public let refs: [String]
    public let tags: [String]

    public init(id: String, hash: String, author: String, email: String, date: Date, message: String, body: String, refs: [String], tags: [String]) {
        self.id = id
        self.hash = hash
        self.author = author
        self.email = email
        self.date = date
        self.message = message
        self.body = body
        self.refs = refs
        self.tags = tags
    }
}

/// Git 差异文件模型
public struct GitDiffFile: Identifiable, Codable, Hashable {
    public let id: String
    public let file: String
    public let changeType: String
    public let diff: String

    public init(id: String, file: String, changeType: String, diff: String) {
        self.id = id
        self.file = file
        self.changeType = changeType
        self.diff = diff
    }
}

/// Git 远程仓库模型
public struct GitRemote: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let url: String
    public let fetchURL: String?
    public let pushURL: String?
    public let isDefault: Bool

    public init(id: String, name: String, url: String, fetchURL: String?, pushURL: String?, isDefault: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.fetchURL = fetchURL
        self.pushURL = pushURL
        self.isDefault = isDefault
    }
}

/// Git 标签模型 (如果需要 struct)
public struct GitTag: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public let commitHash: String

    public init(id: String, name: String, commitHash: String) {
        self.id = id
        self.name = name
        self.commitHash = commitHash
    }
}

// MARK: - GitCommit 扩展

/// GitCommit 的 Co-Authored-By 支持扩展
public extension GitCommit {
    /// 从提交消息中解析的共同作者列表
    var coAuthors: [String] {
        parseCoAuthors(from: body.isEmpty ? message : body)
    }

    /// 所有作者的格式化字符串（主要作者 + 共同作者）
    var allAuthors: String {
        let all = [author] + coAuthors
        return all.joined(separator: " + ")
    }

    /// 解析 Co-Authored-By 信息的私有方法
    /// - Parameter text: 要解析的文本
    /// - Returns: 共同作者名称数组
    private func parseCoAuthors(from text: String) -> [String] {
        let lines = text.split(separator: "\n")
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().starts(with: "co-authored-by:") {
                // 解析 "Co-Authored-By: Name <email>" 格式
                let authorPart = trimmed.dropFirst("Co-Authored-By:".count).trimmingCharacters(in: .whitespaces)
                // 提取姓名部分（去掉邮箱）
                if let angleBracketIndex = authorPart.firstIndex(of: "<") {
                    let name = authorPart[..<angleBracketIndex].trimmingCharacters(in: .whitespaces)
                    return name.isEmpty ? nil : name
                }
                return authorPart
            }
            return nil
        }
    }
}
