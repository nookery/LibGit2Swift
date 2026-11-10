# 项目开发通用规则

> 本规范定义了 LibGit2Swift 项目的通用开发规则和指导方针。

---

## 项目信息

- **类型**: SPM 库（Swift Package），非 App
- **平台**: macOS 14.0+ / iOS（xcframework 含模拟器与 Catalyst 切片）
- **技术栈**: Swift 5.9+, libgit2（通过 `Clibgit2.xcframework` 二进制依赖）
- **仓库**: https://github.com/nookery/LibGit2Swift

---

## 通用规则

### 1. 文档管理

在完成代码修改、重构或功能开发后，**禁止**创建或更新 README 文件。

> 例外：新增公开 API 且改变了使用方式时，可在 PR 描述中说明，但不主动改 README。

### 2. 构建要求

改动源码后必须跑通 `swift build`；改动测试或核心逻辑后必须跑通 `swift test`。

> 本项目没有 Xcode 工程，`swift build` / `swift test` 就是完整的验证手段。

### 3. 错误处理

对外 API 抛出的错误必须可诊断：

- 统一使用 `GitError` 枚举，不要散落 `NSError`
- 保留底层 libgit2 错误码，便于定位
- 错误描述要说清**什么条件下**抛出，而非仅重复错误名

### 4. libgit2 内存与线程安全

libgit2 的两个硬性约束，**每次新增封装都必须遵守**：

| 约束 | 规则 |
|------|------|
| **内存所有权** | C 指针必须由明确的持有者管理并 `free`；不得泄漏、不得二次释放 |
| **线程安全** | libgit2 实例非线程安全；公开 API 走 `LibGit2.serialized` 串行化，或用 `actor` 隔离 |

> 这两条出错不会编译报错，只会在运行时崩溃或产生难以复现的偶发问题。
> 详见 [Swift 代码组织规范](./swift-code-organization.md)。

### 5. 依赖升级

改动依赖时，`Package.swift` 与 `Package.resolved` 必须**同时提交**，并在提交前跑通测试。
详见 [SPM 依赖锁文件同步规范](./spm-package-lock-sync.md)。

### 6. 条件编译

只在 `#if DEBUG` 内定义的类型，其引用点（含函数体）必须同等包裹；
改动 `#if DEBUG` 代码后需用 `swift build -c release` 验证。
本地 Debug 通过不代表 Release 可编译。

### 7. 项目配置目录

项目级配置（规则、技能、命令）统一放在项目的 `.lumi/` 目录下：

```
.lumi/
├── rules/       # 规则文档
├── commands/    # 命令文档
└── skills/      # 技能
```

---

## 相关规范

- [Commit 规范](./commit-convention.md)
- [Swift 代码组织规范](./swift-code-organization.md)
- [Swift 注释规范](./swift-comment.md)
- [最少功能原则](./minimal-functionality.md)
- [第一性原理思考规范](./first-principles-thinking.md)
- [单元测试规范](./unit-test-rules.md)
- [SPM 依赖锁文件同步](./spm-package-lock-sync.md)
