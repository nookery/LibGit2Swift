# SPM 依赖锁文件同步规范

> 本规范定义了 LibGit2Swift 项目中 SPM 依赖锁文件（`Package.resolved`）的同步与校验要求。

---

## 核心原则

**依赖必须锁定到确定的版本，锁文件必须随依赖变更一起提交。**

---

## 项目的依赖现状

| 依赖 | 声明方式 | 说明 |
|------|----------|------|
| `MagicLog` | `branch: "main"` | ⚠️ **浮动依赖**，见下方规则二 |
| `Clibgit2` | 本地 binaryTarget | `Sources/Clibgit2.xcframework`，随仓库分发，不走 SPM 解析 |

`Package.resolved` 当前只有 1 个 pin（`magiclog`）。

---

## 规则一：依赖变更必须同步 lock 文件

**任何改动 `Package.swift` 中依赖声明的操作，都必须同时更新 `Package.resolved`，且两者一起提交。**

```bash
# 正确流程
swift package update MagicLog    # 解析并写入 Package.resolved
git add Package.swift Package.resolved
git commit -m "chore: update MagicLog dependency"
```

常见错误：

- ❌ 只改了 `Package.swift` 的版本约束，忘了更新 lock
- ❌ 手工编辑 `Package.resolved` 的 `revision` 而不重新解析
- ❌ 在本地改了依赖但没提交 lock，导致 CI 与本地解析出不同版本

### 为什么要紧

`Package.resolved` 是**可复现构建**的唯一依据。lock 与 manifest 不一致时：
- 本地能编译，CI 拉到的却是另一个版本 → CI 挂在一个本地从未验证过的代码上；
- 反之亦然。两种情况都让「绿色」失去意义。

---

## 规则二：`branch:` 依赖必须谨慎

本项目当前对 `MagicLog` 使用 `branch: "main"`：

```swift
.package(url: "https://github.com/nookery/MagicLog.git", branch: "main")
```

**浮动依赖的风险**：`branch` 声明意味着 `swift package update` 会拉到 `main` 的最新提交。
上游一旦推送破坏性变更，本项目会在**没有代码改动**的情况下突然编译失败。

### 约定

| 场景 | 做法 |
|------|------|
| 日常开发 | 保持 `branch` 不变；**不要**随手 `swift package update` |
| 需要升 MagicLog 版本 | 显式执行 `swift package update MagicLog`，并**在同一个 commit 里**提交 lock |
| 升级后 | 必须跑通 `swift build` 与 `swift test` 再推送 |
| 发现 CI 突然失败 | 先看 `Package.resolved` 的 revision 是否变了——多半是上游 `main` 推进了 |

> **长期建议**：当 `MagicLog` 发布稳定版本后，改为 `from: "x.y.z"` 固定版本区间，
> 彻底消除浮动依赖带来的不可复现性。

### 依赖 `main` 分支的库时

若必须依赖 `main`，务必在提交信息中说明依赖变更，例如：

```
chore: update MagicLog to f368013 (adds retry helper)
```

便于出问题时快速回溯。

---

## 规则三：只同步 lock pin，不擅自放宽约束

修复依赖问题时，**只允许修改 `Package.resolved` 中的 `revision` / `version`**，
不得为了「让构建通过」而随意放宽 `Package.swift` 的版本约束。

- ✅ 正确：确认目标版本满足约束后，用 `swift package update` 正规同步 lock
- ❌ 错误：把 `from: "1.8.0"` 改成 `from: "1.0.0"`，或把 `from:` 改成 `branch:` 绕过问题

---

## 规则四：`Clibgit2.xcframework` 的版本管理

`Sources/Clibgit2.xcframework` 是**随仓库分发的二进制**，不走 SPM 解析。
它由 `Scripts/build-libgit2-framework.sh` 构建。

### 约定

- **重建 xcframework 必须单独提交**，不要与功能改动混在一起
- 重建时同步更新 `Package.swift` 中对 `Clibgit2` 的引用（如有版本号字段）
- 提交信息建议：`chore(libgit2): rebuild xcframework with libgit2 1.9.x`
- 重建后必须跑通 `swift test`——二进制 ABI 变化会直接影响全部测试

> `git ls-files Sources/Clibgit2.xcframework` 显示约 389 个文件被跟踪，
> 其中含各平台的 `.a` 静态库与头文件。**不要**误把这些文件加进 `.gitignore`。

---

## 规则五：CI 行为说明

- `Release` workflow 仅在 **push 到 `main`** 时触发（见 `.github/workflows/release.yml`）。
- 该 workflow **不执行构建**，只计算版本号并发布 Release，因此依赖解析失败不会阻断发版。
- 但这意味着**依赖问题要到使用方 `swift build` 时才暴露** —— 本地务必跑通 `swift test` 再推送。

---

## 检查清单

改动依赖时，确认：

- [ ] `Package.swift` 与 `Package.resolved` 在同一个 commit 中更新
- [ ] 未擅自放宽版本约束
- [ ] 升级依赖后已跑通 `swift build` 与 `swift test`
- [ ] 提交信息说明了依赖变更内容
- [ ] 重建 `Clibgit2.xcframework` 时单独提交

---

## 相关规范

- [Commit 规范](./commit-convention.md)
- [单元测试规范](./unit-test-rules.md)
- [项目开发通用规则](./project-general-rules.md)
