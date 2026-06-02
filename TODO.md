# LibGit2Swift TODO

功能补全清单，目标：支撑 GitOK 成为完整的 Git 客户端。

## 第一阶段：核心增强

- [x] **Blame** — 文件逐行溯源（git blame），返回每行的 commit、作者、时间
- [x] **Reflog** — 引用日志查询（git reflog），支持操作历史追踪和误操作恢复
- [ ] **Line Patch** — 按 hunk/行 粒度暂存和取消暂存（git add -p / git reset -p）

## 第二阶段：高级功能

- [x] **Rebase** — 变基操作（git rebase），支持 start/continue/abort
- [x] **Describe** — 提交描述（git describe），生成可读版本号
- [ ] **Stash 增强** — stash list 返回变更文件数量和 diff 预览
- [x] **Config 增强** — 读取全局配置（非仓库级别），支持列出所有 key-value

## 第三阶段：专业功能

- [x] **Bisect** — 二分查找定位 bug 引入的提交
- [ ] **Worktree** — 多工作树管理（git worktree add/list/remove）
- [ ] **Archive** — 导出仓库为压缩包（git archive）
- [ ] **Mailmap** — 邮件映射（git mailmap），统一作者身份
