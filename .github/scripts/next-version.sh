#!/bin/bash
#
# next-version.sh - 计算下一个语义化版本号
#
# 递增规则（基于 Conventional Commits，与 Lumi 的 bump-version.sh 对齐）：
#   - breaking change（`type(scope)!:` 或正文 `BREAKING CHANGE`） → major
#   - 新功能（`feat:` / `Add ...` / `Implement ...` 等）             → minor
#   - 其余（fix / perf / chore / docs / test ...）                  → patch
#
# 手动覆盖：仓库根目录的 VERSION 文件
#   - 内容高于最新 tag 时，直接采用该版本（视为人工指定的发布版本）
#   - 内容等于或低于最新 tag 时，按自动规则继续递增
#
# Usage: .github/scripts/next-version.sh
# Output: 1.2.3  (stdout)
#

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "${SCRIPT_DIR}/../.." && pwd )"

cd "${REPO_ROOT}"

# 拉取远端 tag，确保读到上一次 workflow 推上去的 tag
git fetch --tags --force --quiet 2>/dev/null || true

# 最新的语义化 tag（同时兼容 `1.0.0` 与 `v1.0.0` 两种写法）
ORIG_LAST_TAG="$(git tag -l | grep -E '^[v]?[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1 || true)"
LAST_VERSION="${ORIG_LAST_TAG#v}"
BASE_VERSION="${LAST_VERSION:-0.0.0}"

echo "Latest tag: ${ORIG_LAST_TAG:-<none>}" >&2

# 取两个版本中较大的一个（sort -V 具备版本号语义，1.10 > 1.9）
highest() {
  printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1
}

# ---------------------------------------------------------------------------
# 手动覆盖：VERSION 文件
# ---------------------------------------------------------------------------
VERSION_FILE="${REPO_ROOT}/VERSION"
if [ -f "${VERSION_FILE}" ]; then
  MANUAL_VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
  if [[ "${MANUAL_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
     && [ "${MANUAL_VERSION}" != "${BASE_VERSION}" ] \
     && [ "$(highest "${BASE_VERSION}" "${MANUAL_VERSION}")" = "${MANUAL_VERSION}" ]; then
    echo "Using manual version from VERSION file: ${MANUAL_VERSION}" >&2
    echo "${MANUAL_VERSION}"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 统计自上个 tag 以来的 commit
# ---------------------------------------------------------------------------
RANGE="${ORIG_LAST_TAG:+${ORIG_LAST_TAG}..}HEAD"
COMMITS="$(git log "${RANGE}" --no-merges --pretty=format:'%s%n%b' 2>/dev/null || true)"

if [ -z "$(echo "${COMMITS}" | tr -d '[:space:]')" ]; then
  echo "No commits since ${ORIG_LAST_TAG:-start}; defaulting to patch." >&2
  INC="patch"
elif echo "${COMMITS}" | grep -qE 'BREAKING CHANGE|^[a-zA-Z]+(\([^)]+\))?!:'; then
  INC="major"
elif echo "${COMMITS}" | grep -qE '^feat(\([^)]+\))?:|^(Add|Implement|Introduce|Expose)\b'; then
  INC="minor"
else
  INC="patch"
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "${BASE_VERSION}"
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

case "${INC}" in
  major) NEXT="${MAJOR}.0.0" ;;
  minor) NEXT="${MAJOR}.$((MINOR + 1)).0" ;;
  patch) NEXT="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
  *) echo "Error: unknown increment type '${INC}'" >&2; exit 1 ;;
esac

echo "Base:       ${BASE_VERSION}" >&2
echo "Increment:  ${INC}" >&2
echo "Commits:" >&2
echo "${COMMITS}" | grep -E '^[a-zA-Z]' | sed 's/^/  - /' | head -20 >&2 || true

echo "${NEXT}"
