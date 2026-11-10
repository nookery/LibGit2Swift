# Commit 规范

> 本规范定义了 LibGit2Swift 项目的 Git 提交信息编写约定。

---

## 格式

```
<type>(<scope>): <description>
```

- **type** 和 **description** 必填，使用英文
- **scope** 可选，但推荐填写
- description 使用小写开头，不加句号，使用祈使语气（如 `add ...`、`fix ...`）

---

## Type

| type | 用途 | 示例 |
|------|------|------|
| `feat` | 新功能 | `feat(git): add unstageFiles() for path-level unstage` |
| `fix` | 修复 bug | `fix(ssh): honor ~/.ssh/config for non-default SSH ports` |
| `refactor` | 重构（不改变行为） | `refactor(repository): extract status parsing into helper` |
| `style` | 样式/格式调整（不改变行为） | `style(tests): normalize whitespace in fixtures` |
| `perf` | 性能优化 | `perf(status): make rename detection optional` |
| `chore` | 杂务、依赖更新、构建脚本 | `chore: update Package.resolved` |
| `docs` | 文档变更 | `docs: clarify thread-safety requirements` |
| `test` | 测试相关 | `test(repository): add worktree status cancellation cases` |

---

## Scope

scope 为**模块名或组件名**，使用 PascalCase 或 kebab-case，与代码中的类型命名保持一致。

### 常见 scope 示例

| 范围 | scope 示例 |
|------|-----------|
| 核心仓库操作 | `repository`、`clone`、`commit`、`branch` |
| 状态与差异 | `status`、`diff`、`worktree` |
| 网络与远程 | `remote`、`fetch`、`pull`、`push`、`ssh` |
| 底层封装 | `libgit2`、`repository-state`、`blame`、`stash` |
| 工程配置 | `ci`、`build`、`scripts` |

### 规则

- 涉及某个功能域的变更使用该域名作为 scope（如 `fix(ssh): ...`）
- 跨多个模块的变更可省略 scope（如 `chore: update dependencies`）
- 单个 scope 无法覆盖时，选择最核心的模块，或将变更拆分为多次提交

---

## Description 规范

- 使用**祈使语气**：`add ...`、`fix ...`、`remove ...`、`update ...`
- **小写开头**，结尾**不加句号**
- 简明扼要，一句话概括变更内容
- 如需更多细节，在空行后添加正文（body），但通常一句话即可

### ✅ 好的 description

```
feat(git): add unstageFiles() for path-level unstage
fix(ssh): honor ~/.ssh/config for non-default SSH ports
perf(status): make rename detection optional
ci(release): auto-tag and publish GitHub Release on main push
```

### ❌ 避免的 description

```
feat(git): Added unstageFiles().    ← 不要过去式，不要句号
fix: 修复了一个 bug                   ← 不要中文，不要过于模糊
chore                                 ← 缺少 description
```

---

## 完整示例

```
feat(repository): add binary file detection and getFileData API

fix(ssh): honor ~/.ssh/config for non-default SSH ports

perf(status): make rename detection optional for status

chore: update Package.resolved
```

---

## 拆分提交

- 一个提交只做**一件事**
- 不相关的变更拆分为多次提交
- 重构和功能新增分开提交

---

## 与版本发布的关联

本项目的版本号由 CI 依据 Conventional Commits 自动计算
（见 `.github/scripts/next-version.sh`）：

| 提交类型 | 版本递增 |
|----------|----------|
| `type(scope)!:` 或正文含 `BREAKING CHANGE` | major（`1.2.3` → `2.0.0`） |
| `feat:` / `feat(scope):` | minor（`1.2.3` → `1.3.0`） |
| 其他（`fix:` / `perf:` / `chore:` / `docs:` 等） | patch（`1.2.3` → `1.2.4`） |

> **因此 commit 类型写得对不对，直接决定发布出来的版本号。**
> 新功能务必用 `feat`，破坏性变更务必带 `!` 或在正文写 `BREAKING CHANGE`。
