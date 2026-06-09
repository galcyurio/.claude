#!/usr/bin/env bash
# update-git-submodule.sh
# 현재 프로젝트의 prnd-library 서브모듈을 지정 브랜치로 전환하고 원격 최신으로 업데이트한 뒤 커밋한다.
# 사용법: update-git-submodule.sh <branch>
#   branch 이름에는 release 또는 feature 가 포함되어야 한다.
# 참조: ~/.prnd-cli/git_submodule_update.mjs

set -euo pipefail

SUBMODULE="prnd-library"

branch="${1:-}"
if [ -z "$branch" ]; then
  echo "사용법: $0 <branch>" >&2
  echo "  branch 이름에는 release 또는 feature 가 포함되어야 합니다." >&2
  exit 1
fi

# 커밋 메시지 요약 결정 (release/feature 분기)
case "$branch" in
  *release*) summary="라이브러리를 최신화한다" ;;
  *feature*) summary="라이브러리를 feature 브랜치로 변경한다" ;;
  *)
    echo "[오류] 유효하지 않은 branch name: $branch (release 또는 feature 포함 필요)" >&2
    exit 1
    ;;
esac

# 서브모듈 존재 확인 (프로젝트 루트에서 실행해야 함)
if [ ! -d "$SUBMODULE" ]; then
  echo "[오류] 현재 디렉토리에 $SUBMODULE 서브모듈이 없습니다. 프로젝트 루트에서 실행하세요." >&2
  exit 1
fi

# 현재 브랜치에서 Jira 이슈 ID(HDA-숫자) 추출
current_branch="$(git rev-parse --abbrev-ref HEAD)"
jira_id="$(printf '%s' "$current_branch" | grep -oE 'HDA-[0-9]+' || true)"

if [ -n "$jira_id" ]; then
  commit_message="$jira_id feat: $summary"
else
  echo "[경고] 현재 브랜치($current_branch)에서 Jira 이슈 ID를 찾을 수 없습니다. ID 없이 커밋합니다." >&2
  commit_message="feat: $summary"
fi

echo "[1/3] 원격 브랜치 확인: origin/$branch"
git -C "$SUBMODULE" fetch --quiet
if ! git -C "$SUBMODULE" rev-parse --verify --quiet "refs/remotes/origin/$branch" > /dev/null; then
  echo "[오류] $SUBMODULE 원격에 브랜치가 없습니다: origin/$branch" >&2
  exit 1
fi

echo "[2/3] 서브모듈 브랜치 전환 + 원격 최신화: $branch"
git submodule set-branch --branch "$branch" "$SUBMODULE"
git submodule update --remote "$SUBMODULE"

echo "[3/3] 커밋: $commit_message"
git commit .gitmodules "$SUBMODULE" -m "$commit_message"

echo "[완료] $SUBMODULE → $branch"
