# Git 提交向导

帮助用户生成符合 Conventional Commits 规范的提交信息。
完整规范见 `.lumi/rules/commit-convention.md`。

## 工作流程

### 1. 暂存变更

```bash
git add -A                    # 暂存所有变更（含新增、修改、删除）
git status                    # 确认无遗漏的 untracked 文件
```

### 2. 查看变更

```bash
git diff --staged             # 暂存区的完整变更内容
git diff --staged --stat      # 变更文件概览
```

### 3. 拆分变更

**一个提交只做一件事。** 若暂存区包含多类不相关变更，先拆开：

- 功能新增与重构分开
- 源码改动与依赖更新分开
- 重建 `Clibgit2.xcframework` 单独提交

### 4. 分析变更类型

| type | 用途 |
|------|------|
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `refactor` | 重构（不改变行为） |
| `style` | 样式/格式调整（不改变行为） |
| `perf` | 性能优化 |
| `chore` | 杂务、依赖更新、构建脚本 |
| `docs` | 文档变更 |
| `test` | 测试相关 |

**破坏性变更**：type 后加 `!`，或在正文写 `BREAKING CHANGE: <说明>`。

### 5. 确定 scope

scope 用**功能域名或类型名**，与代码中的命名保持一致：

```
feat(git) / fix(ssh) / perf(status) / refactor(repository) / ci(release)
```

跨多个模块的变更可省略 scope。

### 6. 生成提交信息

格式：

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

规则：

- **使用英文**撰写 type 与 description
- description **小写开头**、**不加句号**、**祈使语气**（`add ...` 而非 `Added ...`）
- 标题行不超过 72 字符

### 7. 提交

```bash
git commit -m "<生成的提交信息>"
```

### 8. 提交后确认

```bash
git log --oneline -3
git status
```

---

## 与版本发布的关联

本项目版本号由 CI 依据 commit 类型自动计算（`.github/scripts/next-version.sh`）：

| commit 类型 | 版本递增 | 示例 |
|-------------|----------|------|
| `type(scope)!:` 或 `BREAKING CHANGE` | major | `1.2.3` → `2.0.0` |
| `feat:` / `feat(scope):` | minor | `1.2.3` → `1.3.0` |
| 其他 | patch | `1.2.3` → `1.2.4` |

> **commit 类型写错 = 发布版本号错。** 新功能务必 `feat`，破坏性变更务必带 `!`。

---

## 示例

```
feat(git): add unstageFiles() for path-level unstage

fix(ssh): honor ~/.ssh/config for non-default SSH ports

perf(status): make rename detection optional for status

chore: update Package.resolved
```
