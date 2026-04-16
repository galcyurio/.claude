#!/usr/bin/env bash
# git-cleanup.sh
# 현재 디렉토리의 git 저장소에서 fetch --prune 후 upstream gone 브랜치를 정리한다

set -euo pipefail

REPO_DIR="${1:-.}"

if [ ! -d "$REPO_DIR/.git" ] && [ ! -f "$REPO_DIR/.git" ]; then
  echo "[오류] git 저장소가 아닙니다: $REPO_DIR"
  exit 1
fi

REPO_NAME=$(basename "$(cd "$REPO_DIR" && pwd)")

echo "=========================================="
echo "저장소: $REPO_NAME"
echo "=========================================="

# 1. git fetch --prune
echo "[1/4] git fetch --prune"
if ! git -C "$REPO_DIR" fetch --prune; then
  echo "[오류] git fetch --prune 실패"
  exit 1
fi

# 2. 현재 브랜치의 upstream gone 확인 → develop으로 전환
CURRENT_BRANCH=$(git -C "$REPO_DIR" branch --show-current)
TRACKING=$(git -C "$REPO_DIR" for-each-ref --format='%(upstream:track)' "refs/heads/$CURRENT_BRANCH" 2>/dev/null || echo "")

if [[ "$TRACKING" == *"gone"* ]]; then
  echo "[2/4] 현재 브랜치 '$CURRENT_BRANCH'의 upstream이 삭제됨 → develop으로 전환"
  if ! git -C "$REPO_DIR" checkout develop; then
    echo "[오류] develop 체크아웃 실패"
    exit 1
  fi
else
  echo "[2/4] 현재 브랜치 '$CURRENT_BRANCH' - upstream 정상"
fi

# 3. upstream gone 브랜치 모두 삭제
echo "[3/4] upstream gone 브랜치 정리"
GONE_BRANCHES=$(git -C "$REPO_DIR" for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2 == "[gone]" {print $1}')

if [ -z "$GONE_BRANCHES" ]; then
  echo "  정리할 브랜치 없음"
else
  while IFS= read -r branch; do
    echo "  삭제: $branch"
    git -C "$REPO_DIR" branch -D "$branch"
  done <<< "$GONE_BRANCHES"
fi

# 4. git pull --recurse-submodules
echo "[4/4] git pull --recurse-submodules"
if ! git -C "$REPO_DIR" pull --recurse-submodules; then
  echo "[오류] git pull 실패"
  exit 1
fi

echo "[완료] $REPO_NAME"
