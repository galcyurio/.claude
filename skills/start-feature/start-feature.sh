#!/usr/bin/env bash
# start-feature.sh
# 에픽의 feature-base 브랜치를 만들어 원격에 올리고, 그 브랜치를 물 base worktree와
# 하위 작업용 worktree를 준비한다. 에픽은 같은 디렉토리의 create-epic.mjs가 만든다(SKILL.md 참고).
#
# 사용법: start-feature.sh <base-branch> [옵션]
#   <base-branch>   feature-base/HDA-xxxx-slug 형태의 전체 이름
#   --repo <repo>   대화를 이끌 앱 저장소(오케스트레이터, 필수). base worktree를 이 저장소에 만든다.
#   --children <n>  저장소마다 만들 하위 worktree 개수 (기본 2)
#   --display-name <제목>  base worktree의 orca 표시 이름 (Jira 에픽 제목)
#   --with <repo>   함께 진행할 다른 앱 저장소 (반복 가능).
#                   그 저장소에도 같은 base 브랜치를 원격에 올리되 base worktree는 만들지
#                   않고, 하위 worktree(-2, -3 ...)만 만들어 --repo 저장소의 base worktree를
#                   orca 부모로 연결한다. 대화는 --repo 저장소의 base worktree 하나가 이끈다.
#   --dry-run       파괴적 동작 없이 계획만 출력
#
# <repo>는 앱 이름(고객, 딜러 ...), ~/dev 아래 저장소 이름, 절대 경로 중 하나로 준다.
# 저장소를 인자로 받으므로 어느 디렉토리에서 실행해도 결과가 같다.
set -euo pipefail

die() { echo "[오류] $*" >&2; exit 1; }
info() { echo "$*"; }
ORCA="${ORCA_CLI_COMMAND:-orca}"

# 하위 카드 이름에 쓸 앱 이름. 목록에 없는 저장소는 저장소 이름을 그대로 쓴다.
app_label() {
  case "$1" in
    heydealer-android) echo "고객" ;;
    heydealer-for-dealer-android) echo "딜러" ;;
    heydealer-call-android) echo "딜러-콜" ;;
    heydealer-inspector-android) echo "평가사" ;;
    heydealer-inspector-call-android) echo "평가사-콜" ;;
    revolt-android) echo "리볼트" ;;
    techbay-reconditioning-android) echo "테크베이-공업사" ;;
    techbay-admin-android) echo "테크베이-어드민" ;;
    techbay-call-android) echo "테크베이-콜" ;;
    *) echo "$1" ;;
  esac
}

# app_label의 역방향. 앱 이름을 저장소 이름으로 바꾸고, 앱 이름이 아니면 그대로 둔다.
repo_of_app() {
  case "$1" in
    고객) echo "heydealer-android" ;;
    딜러) echo "heydealer-for-dealer-android" ;;
    딜러-콜) echo "heydealer-call-android" ;;
    평가사) echo "heydealer-inspector-android" ;;
    평가사-콜) echo "heydealer-inspector-call-android" ;;
    리볼트) echo "revolt-android" ;;
    테크베이-공업사) echo "techbay-reconditioning-android" ;;
    테크베이-어드민) echo "techbay-admin-android" ;;
    테크베이-콜) echo "techbay-call-android" ;;
    *) echo "$1" ;;
  esac
}

# 앱 이름·저장소 이름·절대 경로를 받아 그 저장소의 메인 worktree 경로를 낸다.
resolve_repo() {
  local r="$1" opt="$2"
  [ -n "$r" ] || die "$opt 에 저장소가 필요합니다."
  case "$r" in /*) ;; *) r="$HOME/dev/$(repo_of_app "$r")" ;; esac
  git -C "$r" rev-parse --git-dir > /dev/null 2>&1 || die "git 저장소가 아닙니다: $r"
  main_worktree_of "$r"
}

# 저장소의 메인 worktree 경로
main_worktree_of() {
  dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
}

# 메인 worktree 옆에 <repo>-<이슈키>[-N] 형식으로 비어 있는 자리를 정한다.
# 이름만 보고 어떤 피처의 자리인지 알 수 있게 이슈키를 넣는다.
# release-worktree는 이름 끝의 -<한두자리 숫자>만 브랜치 접미사로 읽으므로,
# 이슈키의 숫자 부분(HDA-22644의 22644)과 섞이지 않는다.
# 세 번째 인자가 1이면 접미사 없는 자리를 건너뛰고 -2부터 찾는다(하위 전용 자리).
next_worktree_path() {
  local repo_dir="$1" key="$2" numbered_only="${3:-0}" main_wt parent repo stem n
  main_wt="$(main_worktree_of "$repo_dir")"
  parent="$(dirname "$main_wt")"
  repo="$(basename "$main_wt")"
  stem="$parent/$repo-$key"
  if [ "$numbered_only" = 0 ] && [ ! -e "$stem" ]; then printf '%s' "$stem"; return; fi
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

# develop을 최신화하고 base 브랜치를 끊어 원격에 올린다.
# 하위 worktree가 origin/<base>를 upstream으로 따라가야 하므로 이 단계 없이는 뒤가
# 전부 실패한다. 이 스킬을 부르는 것이 곧 이 업로드에 대한 지시이며, SKILL.md가 실행
# 전에 브랜치 이름을 보여 확인받는 것으로 게이트를 대신한다.
create_base_branch() {
  local repo_dir="$1"
  git -C "$repo_dir" rev-parse --verify --quiet "refs/heads/$base_branch" > /dev/null \
    && die "이미 있는 브랜치입니다: $repo_dir ($base_branch)"
  info "  $repo_dir: develop 최신화 후 $base_branch 생성, 원격에 올립니다"
  [ "$opt_dry_run" = 0 ] || return 0
  git -C "$repo_dir" fetch origin develop
  git -C "$repo_dir" switch develop
  git -C "$repo_dir" pull --ff-only
  git -C "$repo_dir" checkout -b "$base_branch"
  git -C "$repo_dir" push -u origin "$base_branch" \
    || die "원격에 올리지 못했습니다. 하위 worktree의 upstream을 걸 수 없으므로 중단합니다."
  git -C "$repo_dir" switch -
}

# repo_dir에 하위 worktree를 children개 만들고 parent_path를 orca 부모로 연결한다.
create_children() {
  local repo_dir="$1" parent_path="$2" numbered_only="$3" label i=0
  local child_path suffix child_branch child_id
  label="$(app_label "$(basename "$(main_worktree_of "$repo_dir")")")"
  while [ "$i" -lt "$children" ]; do
    i=$((i+1))
    if [ "$opt_dry_run" = 1 ]; then
      info "  (dry-run) $repo_dir 의 하위 자리 $i 번째 (부모: $parent_path)"
      continue
    fi

    # 경로를 먼저 정하고 그 디렉토리 접미사로 브랜치 이름을 짓는다.
    # release-worktree가 이 대응으로 되돌아갈 base 사본을 찾으므로 둘이 어긋나면 안 된다.
    child_path="$(next_worktree_path "$repo_dir" "$epic_key" "$numbered_only")"
    suffix="$(basename "$child_path")"
    case "$suffix" in
      *-[0-9]|*-[0-9][0-9]) suffix="${suffix##*-}" ;;
      *) suffix="" ;;
    esac
    child_branch="${base_branch}${suffix:+-$suffix}"
    info "  $child_path  ($child_branch, 부모: $parent_path)"

    git -C "$repo_dir" worktree add -b "$child_branch" "$child_path" "$base_branch" \
      || die "하위 worktree를 만들지 못했습니다: $child_path"
    git -C "$child_path" branch --set-upstream-to="origin/$base_branch" "$child_branch" \
      || die "upstream을 걸지 못했습니다. base 브랜치가 원격에 올라가 있어야 합니다."
    bash "$HOME/.claude/skills/start-worktree/init.sh" "$child_path"

    # 부모 selector는 path:<경로>를 쓴다. worktree set 은 worktree:<id> 형식을 받지 않아
    # selector_not_found로 실패한다(worktree create 의 selector 목록과 다르다).
    if child_id="$(wait_orca_worktree "$child_path")"; then
      "$ORCA" worktree set --worktree "id:$child_id" \
        --parent-worktree "path:$parent_path" \
        --display-name "$label${suffix:+ $suffix}" --json > /dev/null \
        || info "    orca 부모 연결에 실패했습니다. 앱에서 직접 연결해 주세요."
    else
      info "    orca가 아직 인식하지 못해 부모 연결을 건너뜁니다."
    fi
  done
}


base_branch=""
children=2
opt_display_name=""
opt_dry_run=0
main_repo=""
with_repos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --children) children="${2:-2}"; shift 2 ;;
    --display-name) opt_display_name="${2:-}"; shift 2 ;;
    --repo) main_repo="$(resolve_repo "${2:-}" --repo)"; shift 2 ;;
    --with) with_repos+=("$(resolve_repo "${2:-}" --with)"); shift 2 ;;
    --dry-run) opt_dry_run=1; shift ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) base_branch="$1"; shift ;;
  esac
done
[ -n "$main_repo" ] || die "--repo 로 대화를 이끌 앱 저장소를 지정해야 합니다 (예: --repo 고객)."
[ -n "$base_branch" ] || die "base 브랜치 이름이 필요합니다 (예: feature-base/HDA-12345-car-list)."
case "$base_branch" in feature-base/*) ;; *) die "base 브랜치는 feature-base/ 로 시작해야 합니다." ;; esac

# worktree 디렉토리 이름에 쓸 에픽 키를 뽑는다 (feature-base/HDA-22644-slug -> HDA-22644).
# HDA-DRYRUN은 create-epic.mjs --dry-run이 실제 키 대신 돌려주는 자리표시자다.
epic_key="$(printf '%s' "$base_branch" | sed -E 's|^feature-base/([A-Za-z]+-([0-9]+\|DRYRUN)).*|\1|')"
[ "$epic_key" != "$base_branch" ] || die "base 브랜치에서 이슈 키를 찾지 못했습니다: $base_branch"


info "[1/3] develop 최신화 후 base 브랜치 생성: $base_branch"
create_base_branch "$main_repo"
for r in ${with_repos[@]+"${with_repos[@]}"}; do create_base_branch "$r"; done

info "[2/3] base worktree 생성"
base_path="$(next_worktree_path "$main_repo" "$epic_key")"
info "  $base_path  ($base_branch)"
if [ "$opt_dry_run" = 0 ]; then
  git -C "$main_repo" worktree add "$base_path" "$base_branch" \
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

  # 카드에 에픽 Jira 이슈를 붙인다. git worktree add로 만든 자리는 orca가 이슈를 모르므로
  # 따로 붙여야 한다. 전체 URL이 아니라 키를 넘겨야 Jira에서 조회해 카드에 표시된다.
  info "  Jira 연결: $epic_key"
  "$ORCA" reference add "$epic_key" --worktree "id:$base_wt_id" > /dev/null \
    || info "  orca에 Jira 링크를 붙이지 못했습니다. 직접 실행해 주세요: orca reference add $epic_key --worktree path:$base_path"
fi

info "[3/3] 하위 worktree 생성 (저장소마다 ${children}개, 부모: $base_path)"
create_children "$main_repo" "$base_path" 0
# 다른 앱 저장소에는 base worktree가 없으므로 접미사 없는 자리를 비워 두고 -2부터 쓴다.
for r in ${with_repos[@]+"${with_repos[@]}"}; do create_children "$r" "$base_path" 1; done
