#!/usr/bin/env bash
# start-feature.sh
# 에픽의 feature-base 브랜치를 만들어 원격에 올리고, 그 브랜치를 물 base worktree와
# 하위 작업용 worktree를 준비한다. 에픽 자체는 ~/.prnd-cli/create_jira_epic.mjs가 만든다.
#
# 사용법: start-feature.sh <base-branch> [옵션]
#   <base-branch>   feature-base/HDA-xxxx-slug 형태의 전체 이름
#   --children <n>  하위 worktree 개수 (기본 2)
#   --dry-run       파괴적 동작 없이 계획만 출력
set -euo pipefail

die() { echo "[오류] $*" >&2; exit 1; }
info() { echo "$*"; }
ORCA="${ORCA_CLI_COMMAND:-orca}"

base_branch=""
children=2
opt_dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --children) children="${2:-2}"; shift 2 ;;
    --dry-run) opt_dry_run=1; shift ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) base_branch="$1"; shift ;;
  esac
done
[ -n "$base_branch" ] || die "base 브랜치 이름이 필요합니다 (예: feature-base/HDA-12345-car-list)."
case "$base_branch" in feature-base/*) ;; *) die "base 브랜치는 feature-base/ 로 시작해야 합니다." ;; esac
git rev-parse --verify --quiet "refs/heads/$base_branch" > /dev/null \
  && die "이미 있는 브랜치입니다: $base_branch"

info "[1/3] develop 최신화 후 base 브랜치 생성: $base_branch"
if [ "$opt_dry_run" = 0 ]; then
  git fetch origin develop
  git switch develop
  git pull --ff-only
  git checkout -b "$base_branch"
fi

# TODO: base 브랜치를 upstream과 함께 원격에 올린다 (예: git push -u origin "$base_branch").
# rules/git.md의 push 게이트에 따라 사용자의 명시적 승인 없이는 채우지 않는다.
# 하위 worktree가 origin/<base>를 따라가야 하므로 이 줄이 채워져야 다음 단계가 의미를 갖는다.
if [ "$opt_dry_run" = 0 ]; then
  git switch -
fi

info "[2/3] base worktree 생성"
base_wt_id=""
if [ "$opt_dry_run" = 0 ]; then
  repo_root="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  base_path="$("$ORCA" worktree create --repo "path:$repo_root" \
    --name "$base_branch" --base-branch "$base_branch" --json \
    | python3 -c 'import json,sys; print((json.load(sys.stdin).get("result") or {}).get("worktree",{}).get("path",""))')"
  [ -n "$base_path" ] || die "base worktree 생성에 실패했습니다."
  bash "$HOME/.claude/skills/start-worktree/init.sh" "$base_path"
  base_wt_id="$("$ORCA" worktree list --json | python3 -c '
import json,sys
p = sys.argv[1]
for w in (json.load(sys.stdin).get("result") or {}).get("worktrees") or []:
    if w.get("path") == p:
        print(w.get("id","")); break
' "$base_path")"
  [ -n "$base_wt_id" ] || die "base worktree의 orca id를 찾지 못했습니다."
fi

info "[3/3] 하위 worktree ${children}개 생성"
i=0
while [ "$i" -lt "$children" ]; do
  i=$((i+1))
  child_branch="${base_branch}-$((i+1))"
  info "  $child_branch (부모: $base_branch)"
  if [ "$opt_dry_run" = 1 ]; then continue; fi
  child_path="$("$ORCA" worktree create --repo "path:$repo_root" \
    --name "$child_branch" --base-branch "$base_branch" \
    --parent-worktree "worktree:$base_wt_id" --json \
    | python3 -c 'import json,sys; print((json.load(sys.stdin).get("result") or {}).get("worktree",{}).get("path",""))')"
  [ -n "$child_path" ] || die "하위 worktree 생성에 실패했습니다: $child_branch"
  git -C "$child_path" branch --set-upstream-to="origin/$base_branch" "$child_branch"
  bash "$HOME/.claude/skills/start-worktree/init.sh" "$child_path"

  # 디렉토리 접미사와 브랜치 접미사를 맞춘다. release-worktree가 이 대응으로 사본을 찾는다.
  dir_suffix="$(basename "$child_path")"
  dir_suffix="${dir_suffix##*-}"
  if [ "$dir_suffix" != "$((i+1))" ]; then
    info "    디렉토리 접미사가 $dir_suffix 이므로 브랜치 이름을 맞춥니다"
    git -C "$child_path" branch -m "${base_branch}-${dir_suffix}"
  fi
done
