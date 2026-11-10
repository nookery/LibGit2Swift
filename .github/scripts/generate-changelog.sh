#!/bin/bash
#
# generate-changelog.sh - 生成 GitHub Release 说明（Markdown）
#
# 列出上一个 tag 之后的 commit，按类型分组：
#   - 破坏性变更 (breaking)
#   - 新功能 (feat)
#   - 修复 (fix)
#   - 其他 (perf / chore / docs / test ...)
#
# Usage: generate-changelog.sh <TAG> [PREVIOUS_TAG]
# Output: Markdown 正文 (stdout)
#

set -euo pipefail

TAG="${1:-}"
PREVIOUS_TAG="${2:-}"

if [ -z "${TAG}" ]; then
  echo "Usage: $0 <tag> [previous_tag]" >&2
  exit 1
fi

cd "$( git rev-parse --show-toplevel )"

# 区间终点：优先用传入的 tag。若 tag 尚未创建（打 tag 之前生成 changelog 的场景），
# 回退到 HEAD，避免 ref 解析失败导致产出空 changelog。
END_REF="${TAG}"
if ! git rev-parse --verify --quiet "${TAG}^{commit}" >/dev/null 2>&1; then
  END_REF="HEAD"
fi

if [ -n "${PREVIOUS_TAG}" ]; then
  RANGE="${PREVIOUS_TAG}..${END_REF}"
else
  RANGE="${END_REF}"
fi

BREAKING=""
FEATURES=""
FIXES=""
OTHERS=""
COUNT=0

# 逐个 commit 处理：先取 SHA 列表，再分别取 subject 与 body，
# 避免用分隔符切分多行 message 时引入的解析歧义。
while IFS= read -r sha; do
  [ -z "${sha}" ] && continue

  subject="$(git show -s --pretty=format:'%s' "${sha}")"
  body="$(git show -s --pretty=format:'%b' "${sha}")"

  # 跳过空记录与合并提交噪音
  [ -z "${subject}" ] && continue
  if printf '%s' "${subject}" | grep -qE '^(Merge (branch|pull request)|Merge remote-tracking)'; then
    continue
  fi

  COUNT=$((COUNT + 1))

  if printf '%s' "${subject}" | grep -qE '^[a-zA-Z]+(\([^)]+\))?!:' \
     || printf '%s' "${body}" | grep -q 'BREAKING CHANGE'; then
    BREAKING="${BREAKING}- ${subject}"$'\n'
  elif printf '%s' "${subject}" | grep -qE '^feat(\([^)]+\))?:|^(Add|Implement|Introduce|Expose)\b'; then
    FEATURES="${FEATURES}- ${subject}"$'\n'
  elif printf '%s' "${subject}" | grep -qE '^fix(\([^)]+\))?:|^[Ff]ix\b'; then
    FIXES="${FIXES}- ${subject}"$'\n'
  else
    OTHERS="${OTHERS}- ${subject}"$'\n'
  fi
done < <(git log "${RANGE}" --no-merges --pretty=format:'%H%x00' 2>/dev/null | tr '\0' '\n' || true)

emit_section() {
  local title="$1"
  local items="$2"
  [ -z "${items}" ] && return 0
  echo ""
  echo "### ${title}"
  echo ""
  printf '%s' "${items}"
}

echo "## LibGit2Swift ${TAG}"
echo ""
echo "类型安全的 Swift libgit2 封装库，无需依赖 shell 命令即可完成 Git 操作。"

emit_section "破坏性变更" "${BREAKING}"
emit_section "新功能" "${FEATURES}"
emit_section "修复" "${FIXES}"
emit_section "其他变更" "${OTHERS}"

echo ""
echo "---"
echo ""
echo "共 ${COUNT} 项变更。"
