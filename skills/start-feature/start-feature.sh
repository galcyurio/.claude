#!/usr/bin/env bash
# start-feature.sh
# 에픽의 feature-base 브랜치를 만들어 원격에 올리고, 그 브랜치를 물 base worktree와
# 하위 작업용 worktree를 준비한다. 에픽 자체는 ~/.prnd-cli/create_jira_epic.mjs가 만든다.
#
# 사용법: start-feature.sh <base-branch> [옵션]
#   <base-branch>   feature-base/HDA-xxxx-slug 형태의 전체 이름
#   --children <n>  하위 worktree 개수 (기본 2)
#   --display-name <제목>  base worktree의 orca 표시 이름 (Jira 에픽 제목)
#   --dry-run       파괴적 동작 없이 계획만 출력
set -euo pipefail

die() { echo "[오류] $*" >&2; exit 1; }
info() { echo "$*"; }
ORCA="${ORCA_CLI_COMMAND:-orca}"

# 메인 worktree 옆에 <repo>-<이슈키>[-N] 형식으로 비어 있는 자리를 정한다.
# 이름만 보고 어떤 피처의 자리인지 알 수 있게 이슈키를 넣는다.
# release-worktree는 이름 끝의 -<한두자리 숫자>만 브랜치 접미사로 읽으므로,
# 이슈키의 숫자 부분(HDA-22644의 22644)과 섞이지 않는다.
next_worktree_path() {
  local key="$1" main_wt parent repo stem n
  main_wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  parent="$(dirname "$main_wt")"
  repo="$(basename "$main_wt")"
  stem="$parent/$repo-$key"
  if [ ! -e "$stem" ]; then printf '%s' "$stem"; return; fi
  n=2
  while [ -e "$stem-$n" ]; do n=$((n+1)); done
  printf '%s-%s' "$stem" "$n"
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
opt_display_name=""
opt_dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --children) children="${2:-2}"; shift 2 ;;
    --display-name) opt_display_name="${2:-}"; shift 2 ;;
    --dry-run) opt_dry_run=1; shift ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) base_branch="$1"; shift ;;
  esac
done
[ -n "$base_branch" ] || die "base 브랜치 이름이 필요합니다 (예: feature-base/HDA-12345-car-list)."
case "$base_branch" in feature-base/*) ;; *) die "base 브랜치는 feature-base/ 로 시작해야 합니다." ;; esac

# worktree 디렉토리 이름에 쓸 에픽 키를 뽑는다 (feature-base/HDA-22644-slug -> HDA-22644).
epic_key="$(printf '%s' "$base_branch" | sed -E 's|^feature-base/([A-Za-z]+-[0-9]+).*|\1|')"
[ "$epic_key" != "$base_branch" ] || die "base 브랜치에서 이슈 키를 찾지 못했습니다: $base_branch"
git rev-parse --verify --quiet "refs/heads/$base_branch" > /dev/null \
  && die "이미 있는 브랜치입니다: $base_branch"

info "[1/3] develop 최신화 후 base 브랜치 생성: $base_branch"
if [ "$opt_dry_run" = 0 ]; then
  git fetch origin develop
  git switch develop
  git pull --ff-only
  git checkout -b "$base_branch"
fi

# base 브랜치를 원격에 올린다. 하위 worktree가 origin/<base>를 upstream으로 따라가야
# 하므로 이 단계 없이는 뒤가 전부 실패한다. 이 스킬을 부르는 것이 곧 이 업로드에 대한
# 지시이며, SKILL.md가 실행 전에 브랜치 이름을 보여 확인받는 것으로 게이트를 대신한다.
info "  원격에 올립니다: origin/$base_branch"
if [ "$opt_dry_run" = 0 ]; then
  git push -u origin "$base_branch" \
    || die "원격에 올리지 못했습니다. 하위 worktree의 upstream을 걸 수 없으므로 중단합니다."
  git switch -
fi

info "[2/3] base worktree 생성"
base_wt_id=""
base_path="$(next_worktree_path "$epic_key")"
info "  $base_path  ($base_branch)"
if [ "$opt_dry_run" = 0 ]; then
  git worktree add "$base_path" "$base_branch" \
    || die "base worktree를 만들지 못했습니다: $base_path"
  bash "$HOME/.claude/skills/start-worktree/init.sh" "$base_path"
  base_wt_id="$(wait_orca_worktree "$base_path")" \
    || die "orca가 base worktree를 인식하지 못했습니다: $base_path"

  # 카드 이름을 브랜치명 대신 에픽 제목으로 둔다. 보드에서 무슨 피처인지 바로 읽힌다.
  if [ -n "$opt_display_name" ]; then
    "$ORCA" worktree set --worktree "id:$base_wt_id" \
      --display-name "$opt_display_name" --json > /dev/null \
      || info "  표시 이름을 바꾸지 못했습니다: $opt_display_name"
  fi
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
  child_path="$(next_worktree_path "$epic_key")"
  suffix="$(basename "$child_path")"
  case "$suffix" in
    *-[0-9]|*-[0-9][0-9]) suffix="${suffix##*-}" ;;
    *) suffix="" ;;
  esac
  child_branch="${base_branch}${suffix:+-$suffix}"
  info "  $child_path  ($child_branch, 부모: $base_branch)"

  git worktree add -b "$child_branch" "$child_path" "$base_branch" \
    || die "하위 worktree를 만들지 못했습니다: $child_path"
  git -C "$child_path" branch --set-upstream-to="origin/$base_branch" "$child_branch" \
    || die "upstream을 걸지 못했습니다. base 브랜치가 원격에 올라가 있어야 합니다."
  bash "$HOME/.claude/skills/start-worktree/init.sh" "$child_path"

  # 부모 selector는 path:<경로>를 쓴다. worktree set 은 worktree:<id> 형식을 받지 않아
  # selector_not_found로 실패한다(worktree create 의 selector 목록과 다르다).
  if child_id="$(wait_orca_worktree "$child_path")"; then
    "$ORCA" worktree set --worktree "id:$child_id" \
      --parent-worktree "path:$base_path" --json > /dev/null \
      || info "    orca 부모 연결에 실패했습니다. 앱에서 직접 연결해 주세요."
  else
    info "    orca가 아직 인식하지 못해 부모 연결을 건너뜁니다."
  fi
done
