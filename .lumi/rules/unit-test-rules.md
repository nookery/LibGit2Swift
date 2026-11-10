# 单元测试规范

> 本规范定义了 LibGit2Swift 项目中单元测试的代码组织、目录结构与**环境隔离**要求。

---

## 核心原则

**测试必须在完全隔离的环境里运行：只读写自己造的数据，绝不触碰本机真实数据。**

这条原则有两个方向，缺一不可：

- **不污染本机** —— 测试不得读写开发者本机的真实 Git 仓库、真实 `~/.gitconfig`、真实 SSH 配置。
- **不受本机影响** —— 测试结果不得依赖本机残留的历史数据，否则断言会随机失败。

> 隔离的**目的**不是「每次跑都是空库」，而是「测试只依赖自己造的数据」。

---

## 目录结构

单元测试放在包内 `Tests/<PackageName>Tests/` 目录中。

```text
LibGit2Swift/
├── Package.swift              <-- 声明 testTarget
├── Sources/LibGit2Swift/      <-- 生产代码
└── Tests/LibGit2SwiftTests/
    ├── TestHelpers.swift      <-- 测试辅助工具
    ├── RepositoryTests.swift
    └── ...
```

| 类型 | 命名规范 | 示例 |
|------|---------|------|
| 测试目录 | `<PackageName>Tests` | `LibGit2SwiftTests` |
| 测试文件 | `<SourceFileName>Tests.swift` | `RepositoryTests` |
| 测试类型 | `@Suite` / `XCTestCase` | `RepositoryTests` |

- 新代码优先使用 **Swift Testing**（`import Testing`）；遗留 **XCTest** 可保留，不强制迁移。
- 测试文件名与被测源文件一一对应。

---

## 规则一：测试仓库必须建在临时目录

**所有涉及仓库创建的测试，必须在临时目录中初始化，不得在项目目录或用户目录里建仓库。**

项目已提供 `TestGitRepository` 辅助类，直接复用：

```swift
import XCTest
@testable import LibGit2Swift

final class StatusTests: XCTestCase {
    func testStatusReturnsCleanAfterCommit() throws {
        let testRepo = TestGitRepository(testName: "status-clean")
        try testRepo.create()
        defer { testRepo.cleanup() }

        // ... 使用 testRepo.repositoryPath
    }
}
```

新建测试辅助能力时，**集中加到 `TestHelpers.swift`**，不要在每个测试文件里各造一份。

### 隔离要求

| 资源 | 要求 |
|------|------|
| 仓库目录 | 建在 `FileManager.default.temporaryDirectory` 下，用例结束清理 |
| Git 配置 | 写入仓库级配置（`repo.config()`），不写全局 `~/.gitconfig` |
| 用户身份 | 测试内显式设置 author / committer，不依赖本机 `git config --global` |
| SSH 配置 | 用测试自造的 `~/.ssh/config` 副本，绝不读开发者真实配置 |
| 远程仓库 | 本地裸仓库或 `file://` 路径，不用真实网络地址 |

---

## 规则二：libgit2 全局状态要有 reset 契约

libgit2 的 `git_libgit2_init()` / `git_libgit2_shutdown()` 是**进程级全局状态**。

本项目的 `LibGit2.initialize()` / `LibGit2.shutdown()` 已实现为**幂等且线程安全**
（见 `InitializeIdempotencyTests.swift`），因此：

- 测试**不需要**在每个用例前后手动 shutdown —— 幂等设计已覆盖；
- 但**不得**在测试中假设某个特定的初始化计数或生命周期顺序；
- 若未来引入依赖全局状态的行为，必须先补 `reset` 契约与对应用例。

### 进程级单例

若将来引入 `static let shared` 形态的单例，其状态会跨用例残留。
凡测试会触碰的单例，都必须提供清理入口（如 `resetForTests()` / `removeAllObservers()`），
并在用例前后各清理一次。

---

## 规则三：测试只依赖自己造的数据

**每个用例自己造数据、自己断言。** 不依赖执行顺序，不依赖其它用例的残留。

- 用例间**不要**通过共享状态隐式传数据。
- 共享状态的场景，标注 `.serialized` 并在用例内清理。
- 断言只针对**自造**的数据；不要对「本机当前状态」做断言。

---

## 规则四：测试分层

不是所有测试都该用替身。全部换成替身会丢掉真实行为——
对象生命周期、内存释放、路径拼接、并发冲突，这些恰恰是 Bug 高发区。

| 层次 | 目标 | 做法 |
|------|------|------|
| **纯逻辑层** | 状态解析、差异计算、模型转换 | 直接调用纯函数 |
| **仓库层** | 真实 Git 语义 | 临时目录里建**真实**仓库，走真实 libgit2 |
| **网络层** | 远程交互 | 本地裸仓库模拟 remote，验证 fetch/push 语义 |

判断标准：**这个测试如果跑在替身上，还能发现真实缺陷吗？**
不能，就说明该用真实仓库（配临时目录）。

> libgit2 封装的测试**默认**走真实仓库——这个库的价值就在于贴近真实 Git 语义，
> 用替身测它等于什么都没测。

---

## 测试框架

新代码优先使用 **Swift Testing**：

```swift
import Testing
@testable import LibGit2Swift

@Suite("仓库状态")
struct RepositoryStateTests {

    @Test("空仓库状态为 clean")
    func emptyRepositoryIsClean() throws {
        let testRepo = TestGitRepository(testName: "state-empty")
        try testRepo.create()
        defer { testRepo.cleanup() }

        let repository = try LibGit2.open(at: testRepo.repositoryPath)
        #expect(repository.status().isEmpty)
    }
}
```

遗留 **XCTest** 可保留，不强制迁移。

---

## 运行测试

```bash
# 全量
swift test

# 单个测试
swift test --filter StatusTests
```

---

## 检查清单

新增或改造测试时，确认：

- [ ] 测试目录在 `Tests/LibGit2SwiftTests/`
- [ ] 仓库建在临时目录，用例结束已清理
- [ ] 未写入全局 `~/.gitconfig`，用户身份在仓库级显式设置
- [ ] 未读取开发者真实 SSH 配置
- [ ] 断言只依赖自造数据，不依赖执行顺序
- [ ] 仓库语义走真实 libgit2，而非替身
- [ ] 覆盖了公开 API 的错误路径（而非只测 happy path）

---

## 相关规范

- [Swift 代码组织规范](./swift-code-organization.md)
- [最少功能原则](./minimal-functionality.md)
- [Commit 规范](./commit-convention.md)
