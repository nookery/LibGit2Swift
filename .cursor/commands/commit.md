# Commit Message Rules

按照以下步骤自动创建一个合适的 commit：

1. 暂存全部变更（`git add -A`），确认无遗漏的 untracked 文件
2. 查看 `git diff --staged`，理解本次变更的实质内容
3. 按 [Commit 规范](../../.lumi/rules/commit-convention.md) 生成提交信息
4. 提交并确认

## 注意事项

- 使用**英文**编写提交信息
- 格式：`<type>(<scope>): <description>`
- description 使用**小写开头**、**不加句号**、**祈使语气**（`add ...` 而非 `Added ...`）
- type：`feat` / `fix` / `refactor` / `style` / `perf` / `chore` / `docs` / `test`
- 破坏性变更：type 后加 `!`（如 `feat(git)!: ...`），或在正文写 `BREAKING CHANGE:`
- 一个提交只做一件事，不相关的变更拆分为多次提交
- 确保所有变动都提交

## 类型影响版本号

版本号由 CI 依据 commit 类型自动计算：

| commit 类型 | 版本递增 |
|-------------|----------|
| `type(scope)!:` / `BREAKING CHANGE` | major |
| `feat:` | minor |
| 其他 | patch |

示例：

```
feat(git): add unstageFiles() for path-level unstage
fix(ssh): honor ~/.ssh/config for non-default SSH ports
chore: update Package.resolved
```
