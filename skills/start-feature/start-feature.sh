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

# 메인 worktree 옆에 <repo>-<N> 형식으로 비어 있는 다음 경로를 정한다.
# orca worktree create는 경로를 받지 않고 ~/orca/workspaces/ 아래에 만드는데,
# 그러면 디렉토리 접미사가 사라져 release-worktree가 base 사본을 찾지 못한다.
next_worktree_path() {
  local main_wt parent repo n
  main_wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  parent="$(dirname "$main_wt")"
  repo="$(basename "$main_wt")"
  n=2
  while [ -e "$parent/$repo-$n" ]; do n=$((n+1)); done
  printf '%s/%s-%s' "$parent" "$repo" "$n"
}

# git worktree add로 만든 자리를 orca가 인식할 때까지 기다렸다가 id를 낸다.
# repo 설정의 externalWorktreeVisibility가 show라 외부 생성분도 잡히지만 즉시는 아니다.
wait_orca_worktree() {
  local path="$1" i=0 id=""
  while [ "$i" -lt 20 ]; do
    id="$("$ORCA" worktree list --json 2>/dev/null | python3 -c '
import json, sys
p = sys.argv[1]
for w in (json.load(sys.stdin).get("result") or {}).get("worktrees") or []:
    if w.get("path") == p:
        print(w.get("id", "")); break
' "$path" 2>/dev/null || true)"
    if [ -n "$id" ]; then printf '%s' "$id"; return 0; fi
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}


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
base_path="$(next_worktree_path)"
info "  $base_path  ($base_branch)"
if [ "$opt_dry_run" = 0 ]; then
  git worktree add "$base_path" "$base_branch" \
    || die "base worktree를 만들지 못했습니다: $base_path"
  bash "$HOME/.claude/skills/start-worktree/init.sh" "$base_path"
  base_wt_id="$(wait_orca_worktree "$base_path")" \
    || die "orca가 base worktree를 인식하지 못했습니다: $base_path"
fi

info "[3/3] 하위 worktree ${children}개 생성"
i=0
while [ "$i" -lt "$children" ]; do
  i=$((i+1))
  if [ "$opt_dry_run" = 1 ]; then
    info "  (dry-run) $base_path 다음 번호가 하위 자리가 됩니다 ($i 번째)"
    continue
  fi

  # 경로를 먼저 정하고 그 디렉토리 접미사로 브랜치 이름을 짓는다.
  # release-worktree가 이 대응으로 되돌아갈 base 사본을 찾으므로 둘이 어긋나면 안 된다.
  child_path="$(next_worktree_path)"
  suffix="$(basename "$child_path")"
  suffix="${suffix##*-}"
  child_branch="${base_branch}-${suffix}"
  info "  $child_path  ($child_branch, 부모: $base_branch)"

  git worktree add -b "$child_branch" "$child_path" "$base_branch" \
    || die "하위 worktree를 만들지 못했습니다: $child_path"
  git -C "$child_path" branch --set-upstream-to="origin/$base_branch" "$child_branch" \
    || die "upstream을 걸지 못했습니다. base 브랜치가 원격에 올라가 있어야 합니다."
  bash "$HOME/.claude/skills/start-worktree/init.sh" "$child_path"

  if child_id="$(wait_orca_worktree "$child_path")"; then
    "$ORCA" worktree set --worktree "id:$child_id" \
      --parent-worktree "worktree:$base_wt_id" --json > /dev/null \
      || info "    orca 부모 연결에 실패했습니다. 앱에서 직접 연결해 주세요."
  else
    info "    orca가 아직 인식하지 못해 부모 연결을 건너뜁니다."
  fi
done
