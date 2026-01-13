# LibGit2Swift

一个基于 [libgit2](https://libgit2.org/) 的类型安全 Swift 封装库，提供原生的 Swift 接口用于 Git 操作，无需依赖 shell 命令。

## 概述

LibGit2Swift 是一个 Swift 库，封装了 libgit2 C 库，提供了清晰、符合 Swift 习惯的 API 来程序化地操作 Git。该库专为需要直接与 Git 仓库交互的应用程序设计，如 IDE、版本控制客户端或开发者工具。

## 功能特性

### 仓库管理
- 创建新的 Git 仓库
- 检查路径是否为 Git 仓库
- 获取仓库根目录
- 获取 HEAD 引用和当前分支
- 检查 HEAD 是否处于分离状态
- 获取仓库状态和路径信息

### 配置管理
- 获取和设置 Git 配置值
- 管理用户配置（名称、邮箱）
- 处理仓库特定和全局配置

### 分支操作
- 列出本地和远程分支
- 创建、删除和重命名分支
- 获取当前分支信息
- 管理分支的上游关系

### 提交操作
- 获取提交历史（支持分页）
- 创建新提交
- 修改现有提交
- 添加文件并提交（一步完成）
- 获取详细的提交信息，包括引用和标签

### 文件操作
- 添加文件到暂存区（单个文件或所有更改）
- 检出文件、分支或特定提交
- 检查是否有未提交的更改
- 获取文件状态和差异信息

### 远程仓库管理
- 列出远程仓库
- 添加、删除和配置远程仓库
- 获取和设置远程 URL
- 重命名远程仓库

### 差异操作
- 获取工作树与索引的差异
- 获取索引与 HEAD 的差异
- 比较提交并显示更改
- 获取特定提交的文件内容

### 其他功能
- 标签操作（创建、列出、删除）
- 重置操作（软重置、混合重置、硬重置）
- 合并操作
- 贮存操作
- 网络操作（获取、拉取、推送）

## 系统要求

- macOS 14.0 或更高版本
- Xcode 15.0 或更高版本
- Swift 5.9 或更高版本

## 安装

### Swift Package Manager

在你的 `Package.swift` 中添加 LibGit2Swift 作为依赖：

```swift
dependencies: [
    .package(url: "https://github.com/nookery/LibGit2Swift.git", from: "1.0.0")
]
```

或者通过 Xcode 添加：
1. File → Add Package Dependencies
2. 输入仓库 URL：`https://github.com/nookery/LibGit2Swift.git`
3. 选择版本规则

## 构建

### 依赖版本

- **libgit2**: v1.9.2 (2025年12月)
- **OpenSSL**: 3.4.3
- **libssh2**: 1.11.1

### 首次构建步骤

在第一次使用或更新依赖版本后，需要手动构建 `Clibgit2.xcframework`：

```bash
cd Scripts
./build-libgit2-framework.sh
```

#### 构建过程说明

该脚本会自动完成以下操作：

1. 下载依赖源代码：
   - OpenSSL 3.4.3
   - libssh2 1.11.1
   - libgit2 v1.9.2

2. 为以下平台编译静态库：
   - iOS (arm64)
   - iOS Simulator (x86_64)
   - macOS (arm64)
   - macOS (x86_64)
   - Mac Catalyst (arm64 + x86_64)

3. 创建 `Sources/Clibgit2.xcframework` 并复制 module map

#### 构建时间

整个构建过程大约需要 **10-20 分钟**，具体时间取决于你的网络速度和 CPU 性能。

#### 系统要求

- macOS 14.0+
- Xcode 15.0+
- CMake (通常会随 Xcode 安装)
- wget (用于下载源代码)

如果没有安装 wget：
```bash
brew install wget
```

### 构建完成后

构建成功后，会生成 `Sources/Clibgit2.xcframework` 文件。

然后就可以正常使用 Swift Package Manager：

```bash
# 在 LibGit2Swift 目录下
swift build
```

或者在其他项目中：

```bash
cd /path/to/your/project
swift build
```

### 日常开发

一旦 `Clibgit2.xcframework` 构建完成并提交到仓库，后续开发无需再次构建，除非：

1. 需要更新依赖版本（修改 `Scripts/build-libgit2-framework.sh` 中的版本号）
2. 添加新的平台支持
3. 重新生成 xcframework

### 版本更新

如果需要更新依赖版本：

1. 编辑 `Scripts/build-libgit2-framework.sh`
2. 修改以下版本号：
   - `openssl-X.X.X`
   - `libssh2-X.X.X`
   - `vX.X.X` (libgit2)
3. 重新运行构建脚本

### 故障排除

#### 构建失败：找不到 wget

```bash
brew install wget
```

#### 构建失败：CMake 错误

确保安装了 Xcode 命令行工具：
```bash
xcode-select --install
```

#### Package.swift 错误：找不到 Clibgit2.xcframework

请先运行构建脚本生成 xcframework：
```bash
cd Scripts
./build-libgit2-framework.sh
```

### 主要改进

相比使用外部 `static-libgit2` 包的优势：

1. ✅ **使用最新 libgit2** (v1.9.2 vs v1.3.0)
2. ✅ **独立维护**，不再依赖外部包
3. ✅ **更好的 SSH 支持**，新版 libgit2 对 OpenSSH 密钥格式支持更好
4. ✅ **完全控制**，可以自定义构建选项
5. ✅ **更新及时**，可以随时更新到最新版本

### 技术细节

#### XCFramework 结构

生成的 xcframework 包含以下平台：
- `ios-arm64` (iOS 设备)
- `ios-x86_64-simulator` (iOS 模拟器)
- `macosx-arm64` (Apple Silicon Mac)
- `macosx-x86_64` (Intel Mac)
- `maccatalyst-arm64_x86_64` (Mac Catalyst universal)

#### 链接设置

Package.swift 中配置了必要的链接设置：
```swift
linkerSettings: [
    .linkedLibrary("z"),      // zlib (压缩库)
    .linkedLibrary("iconv")   // 字符编码转换库
]
```

这两个库是 macOS 系统自带的，无需额外安装。

## 使用方法

### 初始化仓库

```swift
import LibGit2Swift

// 创建新仓库
let repository = try LibGit2.createRepository(at: "/path/to/project")

// 打开现有仓库
let repository = try LibGit2.Repository(at: "/path/to/existing/repo")
```

### 获取仓库状态

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// 获取 HEAD
let head = try repository.getHead()
print("当前分支: \(head.branchName)")

// 检查是否有未提交的更改
let hasChanges = try repository.hasUncommittedChanges()
```

### 分支操作

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// 列出分支
let branches = try repository.getBranches()

// 创建新分支
try repository.createBranch(name: "feature-branch")

// 删除分支
try repository.deleteBranch(name: "old-branch")

// 重命名分支
try repository.renameBranch(oldName: "old-name", newName: "new-name")
```

### 提交操作

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// 获取提交历史
let commits = try repository.getCommits(maxCount: 10)

// 创建提交
try repository.commit(message: "添加新功能", authorName: "张三", authorEmail: "zhangsan@example.com")

// 添加文件并提交（一步完成）
try repository.addAndCommit(path: "file.swift", message: "添加 file.swift", authorName: "张三", authorEmail: "zhangsan@example.com")
```

### 文件操作

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// 暂存文件
try repository.add(path: "file.swift")

// 暂存所有更改
try repository.addAll()

// 获取文件状态
let status = try repository.getStatus()
```

### 远程仓库操作

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// 列出远程仓库
let remotes = try repository.getRemotes()

// 添加远程仓库
try repository.addRemote(name: "origin", url: "https://github.com/user/repo.git")

// 获取远程 URL
if let url = try repository.getRemoteURL(name: "origin") {
    print("远程 URL: \(url)")
}
```

### 差异操作

```swift
let repository = try LibGit2.Repository(at: "/path/to/repo")

// 获取工作树与索引的差异
let diff = try repository.getDiffWorkingTreeVsIndex()

// 获取索引与 HEAD 的差异
let diff = try repository.getDiffIndexVsHEAD()

// 获取提交之间的差异
let diff = try repository.getDiffCommit(commitOid: "abc123", parentCommitOid: "def456")
```

## 错误处理

LibGit2Swift 提供了全面的错误处理和有意义的错误消息：

```swift
do {
    let repository = try LibGit2.Repository(at: "/path/to/repo")
    // 执行操作...
} catch LibGit2.Error.repositoryNotFound(let path) {
    print("未找到仓库：\(path)")
} catch LibGit2.Error.invalidReference(let message) {
    print("无效引用：\(message)")
} catch {
    print("错误：\(error.localizedDescription)")
}
```

## 项目结构

```
Sources/LibGit2Swift/
├── LibGit2Swift.swift       # 公共 API 入口
├── LibGit2Wrapper.swift      # 核心封装和配置
├── LibGit2Models.swift       # 数据模型（GitBranch、GitCommit 等）
├── Repository.swift         # 仓库操作
├── Branch.swift             # 分支管理
├── Commit.swift              # 提交历史和详情
├── Commit+Write.swift        # 提交创建和修改
├── Add.swift                 # 文件暂存操作
├── Status.swift             # 状态检查
├── Checkout.swift           # 分支和文件检出
├── Remote.swift              # 远程仓库管理
├── Diff.swift                # 差异操作
├── Tag.swift                 # 标签操作
├── Reset.swift               # 重置操作
├── Merge.swift               # 合并操作
├── Stash.swift               # 贮存操作
└── Network.swift             # 网络操作
```

## 设计原则

1. **类型安全**：Swift 枚举和结构体提供编译时安全
2. **自动内存管理**：正确清理 C 库资源
3. **Swift 原生 API**：符合 Swift 习惯的设计模式和约定
4. **全面的错误处理**：有意义的错误消息和恢复建议
5. **模块化结构**：每个 Git 操作都有独立的 Swift 文件

## 贡献

欢迎贡献！请随时提交 Pull Request。

## 许可证

本项目采用 MIT 许可证。更多信息请参见 LICENSE 文件。

## 致谢

- 基于 [libgit2](https://libgit2.org/) 构建
- 灵感来源于对纯 Swift Git 库的需求，无需依赖 shell 命令
