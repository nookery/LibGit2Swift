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
