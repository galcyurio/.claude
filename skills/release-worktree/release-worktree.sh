#!/usr/bin/env bash
# release-worktree.sh
# 머지가 끝난 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 사본으로 되돌린 뒤,
# 이 worktree에 쌓인 세션 이력을 메인 저장소로 회수하고,
# Orca 워크스페이스 카드를 Done(completed)으로 넘기고 작업 탭을 닫아 세션을 마감한다.
#
# 사용법: release-worktree.sh [<branch>] [옵션]
#   <branch>          정리할 로컬 브랜치. 생략하면 현재 체크아웃된 브랜치.
#                     현재 브랜치가 base(develop·feature-base/*)면 삭제 없이 최신화만 한다.
#   --base <name>     PR을 못 찾았거나 접미사 매칭을 건너뛰고 싶을 때 되돌아갈 base 사본을 직접 지정
#   --force           PR이 없거나 머지되지 않았어도 해제한다. 머지 확인·미커밋 변경·
#                     서브모듈 되돌리기 실패·라이브러리 머지 확인을 모두 넘기고 브랜치를 -D 로 지운다.
#   --stash           working tree가 깨끗하지 않으면 stash하고 진행 (기본은 중단)
#   --force-delete    git branch -D 로 삭제 (기본은 -d)
#   --sweep           같은 base에 이미 머지된 다른 로컬 브랜치도 삭제
#   --no-close        카드는 Done으로 넘기되 탭은 닫지 않는다
#
# 종료 코드: 0 정상 / 1 사전 검증 실패·중단 (이 경우 카드와 탭은 건드리지 않는다)

set -euo pipefail

die() { echo "[오류] $*" >&2; exit 1; }
warn() { echo "[경고] $*" >&2; }
info() { echo "$*"; }

branch=""
explicit_branch=0
sync_only=0
opt_base=""
opt_force=0
opt_stash=0
opt_force_delete=0
opt_sweep=0
opt_no_close=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) shift; [ $# -gt 0 ] || die "--base 뒤에 브랜치 이름이 필요합니다."; opt_base="$1" ;;
    --force) opt_force=1 ;;
    --stash) opt_stash=1 ;;
    --force-delete) opt_force_delete=1 ;;
    --sweep) opt_sweep=1 ;;
    --no-close) opt_no_close=1 ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) [ -z "$branch" ] || die "브랜치는 하나만 지정할 수 있습니다: $branch, $1"; branch="$1"; explicit_branch=1 ;;
  esac
  shift
done

git rev-parse --git-dir > /dev/null 2>&1 || die "git 저장소 안에서 실행해야 합니다."

# 라이브러리 서브모듈 안에서 불렸으면 앱 저장소로 올라간다. 그대로 두면 라이브러리 저장소의
# 브랜치와 worktree를 기준으로 판정해 앱 자리를 반납하지 못한다.
superproject="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
if [ -n "$superproject" ]; then
  info "서브모듈 안에서 불렸으므로 앱 저장소 기준으로 진행합니다: $superproject"
  cd "$superproject"
fi

top="$(git rev-parse --show-toplevel)"

# 브랜치를 체크아웃 중인 worktree 경로를 출력한다 (없으면 빈 문자열).
branch_holder() {
  git worktree list --porcelain | awk -v b="branch refs/heads/$1" '
    /^worktree /{p=substr($0,10)}
    $0==b{print p}'
}

## 1. 대상 브랜치 확정

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [ -z "$branch" ]; then
  [ -n "$current_branch" ] || die "정리할 브랜치를 지정해 주세요 (현재 detached HEAD)."
  branch="$current_branch"
fi
[ "$branch" = "$current_branch" ] && is_current=1 || is_current=0

git rev-parse --verify --quiet "refs/heads/$branch" > /dev/null \
  || die "로컬에 없는 브랜치입니다: $branch"

case "$branch" in
  develop|develop-*|main|master|feature-base/*)
    [ "$explicit_branch" = 0 ] \
      || die "보호 대상 브랜치는 이 스크립트로 삭제하지 않습니다: $branch"
    sync_only=1 ;;
esac

common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir)"
case "$common_dir" in /*) ;; *) common_dir="$PWD/$common_dir" ;; esac

# worktree 디렉토리 이름에서 저장소 이름을 뗀 나머지.
# heydealer-android-AGP-10-migration-2 -> AGP-10-migration-2, heydealer-android-2 -> 2
worktree_rest() {
  local rest
  rest="$(basename "$top")"
  rest="${rest#"$(basename "$(dirname "$common_dir")")"}"
  printf '%s' "${rest#-}"
}

# 되돌아갈 base 사본에서 base_ref를 역으로 얻는다. 이름이 -<나머지>로 끝나고 upstream이
# 걸린 로컬 브랜치가 정확히 하나일 때만 성공한다. 여러 개면 어느 것이 이 자리의 사본인지
# 알 수 없으므로 실패로 둔다 — 나머지가 "2"면 develop-2 와 feature-base/...-2 가 함께 걸린다.
resolve_base_from_slot() {
  local rest="$1" found="" n=0 br up
  [ -n "$rest" ] || return 1
  while IFS=$'\t' read -r br up; do
    [ -n "$up" ] || continue
    case "$br" in *-"$rest") ;; *) continue ;; esac
    found="${up#origin/}"
    n=$((n + 1))
  done < <(git for-each-ref --format='%(refname:short)%09%(upstream:short)' refs/heads/)
  [ "$n" = 1 ] || return 1
  printf '%s' "$found"
}

## 2. 머지 확인과 base 판별

if [ "$sync_only" = 1 ]; then
  base_copy="$branch"
  base_ref="$branch"
  info "[1/6] base 브랜치에 있으므로 삭제 없이 최신화만 합니다: $branch"
elif [ -n "$opt_base" ]; then
  base_copy="$opt_base"
  base_ref="$opt_base"
  info "[1/6] base를 직접 지정했습니다: $base_copy (머지 확인 생략)"
else
  if [ "$opt_force" = 1 ]; then
    # 머지 여부를 묻지 않는다. PR이 있으면 머지 상태와 무관하게 그 base를 쓰고, PR이
    # 아예 없으면 이 자리가 물고 있던 base 사본에서 역으로 얻는다. 둘 다 실패하면
    # base를 추정하지 않고 --base 를 요구한다.
    base_ref=""
    if command -v gh > /dev/null; then
      base_ref="$(gh pr list --state all --head "$branch" --limit 1 \
        --json baseRefName --jq '.[0].baseRefName // empty' 2>/dev/null || true)"
    fi
    if [ -z "$base_ref" ]; then
      base_ref="$(resolve_base_from_slot "$(worktree_rest)")" || base_ref=""
    fi
    [ -n "$base_ref" ] \
      || die "--force 로도 base를 특정하지 못했습니다. --base <name>을 함께 지정하세요."
    info "[1/6] --force: 머지 확인을 건너뜁니다 (base: $base_ref)"
  else
    command -v gh > /dev/null || die "gh CLI가 필요합니다. --base <name>으로 직접 지정할 수도 있습니다."
    base_ref="$(gh pr list --state merged --head "$branch" --limit 1 \
      --json baseRefName --jq '.[0].baseRefName // empty' 2>/dev/null || true)"
    if [ -z "$base_ref" ]; then
      echo "[오류] $branch 로 머지된 PR을 찾지 못했습니다." >&2
      echo "  upstream이 gone인 것은 머지 근거가 아닙니다. 사람이 머지 여부를 확인하거나," >&2
      echo "  base를 알고 있다면 --base <name>으로 다시 실행하세요." >&2
      echo "  머지 여부와 무관하게 자리를 비우려면 --force 로 실행하세요." >&2
      exit 1
    fi
    info "[1/6] 머지 확인: $branch → $base_ref"
  fi

  # base 사본 결정 (worktree 디렉토리 접미사 매칭)
  # 디렉토리 이름 끝의 -<한두자리 숫자>만 브랜치 접미사로 읽는다.
  # heydealer-android-HDA-22644-2 -> "-2", heydealer-android-HDA-22644 -> "" (base 자리),
  # heydealer-android-2 -> "-2" (옛 규칙도 그대로 걸린다).
  # 이슈키의 숫자(22644)는 자릿수가 많아 걸리지 않는다.
  top_name="$(basename "$top")"
  suffix=""
  case "$top_name" in
    *-[0-9]|*-[0-9][0-9]) suffix="-${top_name##*-}" ;;
  esac

  # 이름 슬롯 자리(heydealer-android-AGP-10-migration[-N])는 끝의 숫자만 읽으면 develop
  # 이나 develop-2로 되돌아가려 해서 메인·다른 슬롯과 충돌한다. 디렉토리에서 저장소
  # 이름을 뗀 나머지를 계열 이름으로 보고 <base>-<나머지>를 첫 후보로 둔다.
  #
  # 계열 슬롯은 풀 base가 develop일 때만 있다(start-worktree는 원격 feature-base가 없을
  # 때만 --slot을 판정한다). 에픽 자리(-<에픽키>-N)의 나머지 "HDA-23292-3"은 계열 이름이
  # 아니므로 feature-base에서는 이 후보를 두지 않는다. 두면 사본이 없을 때 아래 생성
  # 분기가 <base>-HDA-23292-3 을 만들고, start-worktree는 그 접미사를 숫자 슬롯으로 받지
  # 않아 그 자리를 유휴 후보에서 뺀다(2026-10-13 revolt-android에서 실제로 생겼다).
  slot_candidate=""
  rest="$(worktree_rest)"
  case "$base_ref" in
    feature-base/*) ;;
    *)
      case "$rest" in
        ""|[0-9]|[0-9][0-9]) ;;
        *) slot_candidate="${base_ref}-${rest}" ;;
      esac
      ;;
  esac

  base_copy=""
  for candidate in "$slot_candidate" "${base_ref}${suffix}" "$base_ref"; do
    [ -n "$candidate" ] || continue
    git rev-parse --verify --quiet "refs/heads/$candidate" > /dev/null || continue
    holder="$(branch_holder "$candidate")"
    if [ -z "$holder" ] || [ "$holder" = "$top" ]; then base_copy="$candidate"; break; fi
  done
  if [ -z "$base_copy" ]; then
    # 계열 사본이 아직 없는 이름 슬롯 자리라면 develop이 아니라 그 계열 사본을 만든다.
    base_copy="${slot_candidate:-${base_ref}${suffix}}"
    if git rev-parse --verify --quiet "refs/heads/$base_copy" > /dev/null; then
      # 앞선 루프가 base_copy를 비운 채 나왔다면 후보가 전부 다른 worktree에 점유된 것이다.
      # 여기서 git branch를 부르면 already exists로 죽으므로, 기존 안내를 그대로 살린다.
      echo "[오류] 되돌아갈 base 사본이 전부 다른 worktree에 점유되어 있습니다 (base: $base_ref)." >&2
      echo "  후보:" >&2
      git branch --list "${base_ref}*" >&2
      echo "  --base <name>으로 비어 있는 사본을 지정하세요." >&2
      exit 1
    fi
    info "base 사본이 없어 새로 만듭니다: $base_copy (upstream: origin/$base_ref)"
    git rev-parse --verify --quiet "refs/remotes/origin/$base_ref" > /dev/null \
      || die "원격에 $base_ref 가 없어 사본을 만들 수 없습니다."
    git branch "$base_copy" "origin/$base_ref"
    git branch --set-upstream-to="origin/$base_ref" "$base_copy"
  fi
fi

git rev-parse --verify --quiet "refs/heads/$base_copy" > /dev/null \
  || die "base 사본이 로컬에 없습니다: $base_copy"
base_holder="$(branch_holder "$base_copy")"
if [ -n "$base_holder" ] && [ "$base_holder" != "$top" ]; then
  die "base 사본 $base_copy 는 $base_holder 가 점유 중입니다."
fi

## 2-1. 라이브러리 작업 브랜치 판정
# start-worktree --library 는 앱 자리의 라이브러리 서브모듈에 앱과 같은 이름의 작업 브랜치를
# 끊는다. 그 브랜치도 앱 브랜치와 함께 정리한다. 이름이 다른 브랜치는 이 반납과 무관한 작업일
# 수 있으므로 정리 대상이 아니며, 아래 서브모듈 되돌리기에서 경고만 남긴다.
# 판정은 앱을 건드리기 전에 끝낸다. 라이브러리에서 막히면 앱도 그대로 두고 멈춰야 한다.

lib_sub=""
lib_cleanup=0
if [ "$sync_only" = 0 ] && [ "$is_current" = 1 ] && [ -f "$top/.gitmodules" ]; then
  lib_sub="$(git config --file "$top/.gitmodules" --get submodule.prnd-library.path || true)"
fi
if [ -n "$lib_sub" ] \
  && [ "$(git -C "$top/$lib_sub" symbolic-ref --quiet --short HEAD 2>/dev/null || true)" = "$branch" ]; then
  lib="$top/$lib_sub"
  lib_changes="$(git -C "$lib" status --porcelain --untracked-files=no)"
  if [ -n "$lib_changes" ]; then
    echo "라이브러리 서브모듈에 변경된 파일:" >&2
    printf '%s\n' "$lib_changes" | head -10 >&2
    if [ "$opt_stash" = 1 ] || [ "$opt_force" = 1 ]; then
      lib_stash_tag="release-worktree-library: $branch @ $(date '+%Y%m%d-%H%M%S')"
      git -C "$lib" stash push -m "$lib_stash_tag" \
        || die "라이브러리 서브모듈 변경을 stash하지 못했습니다: $lib"
      warn "라이브러리 변경은 서브모듈 stash에 있습니다 — $lib_stash_tag"
    else
      die "라이브러리 서브모듈이 깨끗하지 않습니다. 커밋하거나 --stash·--force로 다시 실행하세요."
    fi
  fi

  git -C "$lib" fetch --prune origin \
    || warn "라이브러리 원격을 가져오지 못했습니다. 로컬 ref로 판정합니다."
  # 앱 PR의 base와 develop 어디에도 없는 커밋 수. 하나도 없으면 착수할 때 오탐으로 만든
  # 빈 브랜치이므로 머지 확인 없이 지운다.
  lib_bases=()
  for ref in "$base_ref" develop; do
    git -C "$lib" rev-parse --verify --quiet "refs/remotes/origin/$ref" > /dev/null \
      && lib_bases+=("origin/$ref")
  done
  # 비교할 base를 하나도 못 찾으면 빈 브랜치라고 단정할 수 없으므로 머지 확인으로 넘긴다.
  lib_ahead=1
  if [ "${#lib_bases[@]}" -gt 0 ]; then
    lib_ahead="$(git -C "$lib" rev-list --count "$branch" --not "${lib_bases[@]}" 2>/dev/null || echo 1)"
  fi
  if [ "$lib_ahead" = 0 ]; then
    lib_cleanup=1
    info "[1/6] 라이브러리 브랜치에 고유 커밋이 없어 함께 지웁니다: $branch"
  else
    lib_repo="$(git -C "$lib" remote get-url origin | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')"
    lib_merged=""
    if command -v gh > /dev/null; then
      lib_merged="$(gh pr list --repo "$lib_repo" --state merged --head "$branch" --limit 1 \
        --json number --jq '.[0].number // empty' 2>/dev/null || true)"
    fi
    if [ -n "$lib_merged" ]; then
      lib_cleanup=1
      info "[1/6] 라이브러리 PR 머지 확인: $lib_repo#$lib_merged"
    elif [ "$opt_force" = 1 ]; then
      lib_cleanup=1
      warn "--force: 라이브러리 브랜치 $branch 의 커밋 $lib_ahead 개가 머지되지 않았지만 지웁니다. 커밋은 reflog에만 남습니다."
    else
      lib_unpushed="$(git -C "$lib" rev-list --count "$branch" --not --remotes=origin 2>/dev/null || echo 0)"
      echo "[오류] 라이브러리 브랜치 $branch 에 머지되지 않은 커밋이 $lib_ahead 개 있습니다 (push 안 된 커밋 $lib_unpushed 개)." >&2
      echo "  $lib_repo 에서 $branch 로 머지된 PR을 찾지 못했습니다. 라이브러리 PR을 머지한 뒤 다시 실행하세요." >&2
      echo "  머지 여부와 무관하게 자리를 비우려면 --force 로 실행하세요." >&2
      exit 1
    fi
  fi
fi

## 3. 손실 위험 점검 (현재 브랜치를 정리할 때만)

tracked_changes() { git status --porcelain --untracked-files=no --ignore-submodules=all; }

if [ "$is_current" = 1 ] && [ -n "$(tracked_changes)" ]; then
  echo "변경된 파일:" >&2
  tracked_changes | head -10 >&2
  if [ "$opt_stash" = 1 ]; then
    info "[2/6] stash 후 진행합니다."
    git stash push -u -m "release-worktree: $branch"
  elif [ "$opt_force" = 1 ]; then
    # --force 는 미커밋 변경으로 멈추지 않는다. 다만 그냥 버리면 되찾을 수 없으므로
    # 태그를 붙여 stash로 치워 둔다. 자리를 비우는 목적은 그대로 달성되고, 필요하면
    # git stash list 에서 이 태그를 찾아 apply 할 수 있다.
    force_stash_tag="release-worktree-force: $branch @ $(date '+%Y%m%d-%H%M%S')"
    info "[2/6] --force: 미커밋 변경을 stash로 치우고 진행합니다."
    if git stash push -u -m "$force_stash_tag"; then
      warn "치워 둔 변경은 stash에 있습니다 — $force_stash_tag"
    else
      warn "stash에 실패했습니다. 변경을 그대로 둔 채 진행합니다."
    fi
  else
    die "working tree가 깨끗하지 않습니다. 커밋하거나 --stash·--force로 다시 실행하세요."
  fi
else
  info "[2/6] working tree 확인 완료"
fi

## 4. 대상 브랜치 점유 확인

holder="$(branch_holder "$branch")"
if [ -n "$holder" ] && [ "$holder" != "$top" ]; then
  die "$branch 는 $holder 가 체크아웃 중이라 삭제할 수 없습니다. 그 worktree에서 정리하세요."
fi

## 4-1. 세션 회수

session_project_dir() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's|[/.]|-|g')"
}

main_worktree="$(dirname "$common_dir")"
if [ "$main_worktree" != "$top" ]; then
  from_dir="$(session_project_dir "$top")"
  to_dir="$(session_project_dir "$main_worktree")"
  if [ -d "$from_dir" ]; then
    mkdir -p "$to_dir"
    n=0
    for f in "$from_dir"/*.jsonl; do
      [ -e "$f" ] || continue
      if cp -n "$f" "$to_dir/"; then n=$((n+1)); fi
    done
    info "세션 $n 건을 메인 저장소로 회수했습니다: $to_dir"
  fi
fi

## 5. git 정리

info "[3/6] 원격 상태 갱신: git fetch --prune"
git fetch --prune

if [ "$is_current" = 1 ]; then
  if [ "$base_copy" = "$current_branch" ]; then
    info "[4/6] 이미 $base_copy 에 있어 전환을 건너뜁니다"
  else
    info "[4/6] base 사본으로 전환: $base_copy"
    if ! git switch "$base_copy"; then
      # stash가 실패했는데도 --force 로 여기까지 온 경우다. 자리를 비우는 것이 목적이므로
      # 남은 변경을 버리고 전환한다.
      [ "$opt_force" = 1 ] || die "base 사본으로 전환하지 못했습니다: $base_copy"
      warn "--force: 전환이 막혀 남은 로컬 변경을 버리고 전환합니다."
      git switch --discard-changes "$base_copy"
    fi
  fi

  if git rev-parse --verify --quiet "@{upstream}" > /dev/null; then
    git pull --ff-only || die "base 사본이 원격과 갈라졌습니다. 강제로 맞추지 않고 중단합니다."
  else
    warn "$base_copy 에 upstream이 없어 pull을 건너뜁니다."
  fi

  if [ -f "$top/.gitmodules" ]; then
    while IFS= read -r sub; do
      [ -n "$sub" ] || continue
      head_before="$(git -C "$top/$sub" rev-parse --short HEAD 2>/dev/null || true)"
      branch_before="$(git -C "$top/$sub" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      [ -n "$branch_before" ] || continue
      # 앱과 함께 정리할 라이브러리 브랜치는 아래에서 지우므로 경고하지 않는다.
      if [ "$lib_cleanup" = 1 ] && [ "$sub" = "$lib_sub" ]; then continue; fi
      warn "서브모듈 $sub 이 $branch_before($head_before) 를 가리키고 있어 base 기준으로 되돌립니다."
    done < <(git config --file "$top/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
    if ! git submodule update; then
      if [ "$opt_force" = 1 ]; then
        # --force 는 서브모듈 때문에 멈추지 않는다. --force 로 다시 시도해 base가 기록한
        # 커밋으로 강제 체크아웃하며, 그래도 되돌리지 못하면 경고만 남기고 계속한다.
        warn "--force: 서브모듈을 되돌리지 못해 강제로 다시 시도합니다. 서브모듈의 로컬 변경은 버려집니다."
        git submodule update --force \
          || warn "--force: 서브모듈을 끝내 되돌리지 못했지만 자리 해제는 계속합니다."
      else
        echo "[오류] 서브모듈을 base 기준으로 되돌리지 못했습니다." >&2
        while IFS= read -r sub; do
          [ -n "$sub" ] || continue
          dirty="$(git -C "$top/$sub" status --short 2>/dev/null || true)"
          [ -n "$dirty" ] || continue
          echo "  $sub 에 정리되지 않은 변경이 있습니다:" >&2
          echo "$dirty" | head -10 >&2
        done < <(git config --file "$top/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
        echo "  서브모듈 안에서 커밋·push하거나 stash한 뒤 다시 실행하세요. 임의로 버리지 않습니다." >&2
        echo "  자리를 비우는 것이 목적이면 --force 로 실행하세요 (서브모듈 로컬 변경은 버려집니다)." >&2
        exit 1
      fi
    fi
  fi

  if [ "$lib_cleanup" = 1 ]; then
    lib="$top/$lib_sub"
    # 포인터가 라이브러리 브랜치 tip과 같으면 submodule update가 아무것도 하지 않아 브랜치를
    # 문 채로 남는다. 문 브랜치는 지울 수 없으므로 같은 커밋에서 떼어 낸다.
    if git -C "$lib" symbolic-ref --quiet HEAD > /dev/null 2>&1; then
      git -C "$lib" switch --detach --quiet
    fi
    info "라이브러리 브랜치 삭제: $lib_sub 의 $branch"
    git -C "$lib" branch -D "$branch" \
      || warn "라이브러리 브랜치를 지우지 못했습니다. 서브모듈에서 직접 지워 주세요: $lib"
  fi
else
  info "[4/6] 현재 브랜치가 아니므로 전환·최신화를 건너뜁니다 (현재: ${current_branch:-detached})"
fi

if [ "$sync_only" = 1 ]; then
  info "[5/6] 삭제할 작업 브랜치가 없습니다"
elif [ "$opt_force_delete" = 1 ] || [ "$opt_force" = 1 ]; then
  ahead="$(git rev-list --count "$base_copy..$branch" 2>/dev/null || echo 0)"
  [ "$ahead" = 0 ] \
    || warn "$branch 에 $base_copy 로 들어가지 않은 커밋이 $ahead 개 있습니다. 강제 삭제하면 이 커밋들은 reflog에만 남습니다."
  info "[5/6] 브랜치 강제 삭제: git branch -D $branch"
  git branch -D "$branch"
else
  info "[5/6] 브랜치 삭제: git branch -d $branch"
  git branch -d "$branch" || die "base에 포함되지 않은 커밋이 있습니다. 위 메시지를 확인하세요 (강제 삭제는 --force-delete 또는 --force)."
fi

## 6. 남은 머지 브랜치

candidates=()
while IFS= read -r b; do
  [ -n "$b" ] || continue
  case "$b" in
    "$base_copy"|"$base_ref"|"${base_ref}-"*|"$current_branch"|develop|develop-*|main|master) continue ;;
  esac
  h="$(branch_holder "$b")"
  if [ -n "$h" ] && [ "$h" != "$top" ]; then
    info "  - $b (점유: $h — 건너뜀)"
    continue
  fi
  candidates+=("$b")
done < <(git branch --merged "$base_copy" --format='%(refname:short)')

if [ "${#candidates[@]}" -eq 0 ]; then
  info "[6/6] 추가 정리 대상 없음"
elif [ "$opt_sweep" = 1 ]; then
  info "[6/6] 스윕 삭제:"
  for b in "${candidates[@]}"; do
    if git branch -d "$b" 2>/dev/null; then info "  - $b 삭제"; else warn "  - $b 삭제 거부 (건너뜀)"; fi
  done
else
  info "[6/6] 같은 base에 이미 머지된 브랜치가 있습니다 (--sweep으로 함께 삭제):"
  for b in "${candidates[@]}"; do info "  - $b"; done
fi

if [ "$sync_only" = 1 ]; then
  info "[완료] $base_copy 최신화"
else
  info "[완료] $branch 삭제, 현재 위치 $base_copy"
fi

## 7. Orca 카드 상태와 탭

if [ -z "${ORCA_WORKTREE_ID:-}" ]; then
  info "Orca가 관리하는 세션이 아니므로 카드 상태 전환과 탭 종료를 건너뜁니다."
  exit 0
fi

ORCA="${ORCA_CLI_COMMAND:-orca}"
if ! command -v "$ORCA" > /dev/null; then
  warn "$ORCA 를 찾을 수 없어 카드 상태 전환과 탭 종료를 건너뜁니다."
  exit 0
fi

if "$ORCA" worktree set --worktree active --workspace-status completed --json > /dev/null 2>&1; then
  info "Orca 카드 상태를 completed로 넘겼습니다."
else
  warn "Orca 카드 상태 전환에 실패했습니다. git 정리 결과는 그대로입니다."
fi

if [ "$opt_no_close" = 1 ]; then
  info "--no-close 이므로 탭을 닫지 않습니다."
  exit 0
fi

handle="${ORCA_TERMINAL_HANDLE:-}"
if [ -z "$handle" ] && [ -n "${ORCA_TAB_ID:-}" ]; then
  handle="$("$ORCA" terminal list --worktree active --json 2>/dev/null | python3 -c '
import json, os, sys
tab = os.environ.get("ORCA_TAB_ID", "")
leaf = os.environ.get("ORCA_PANE_KEY", "").split(":")[-1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in (data.get("result") or {}).get("terminals") or []:
    if t.get("tabId") == tab and (not leaf or t.get("leafId") == leaf):
        print(t.get("handle", ""))
        break
' || true)"
fi

if [ -z "$handle" ]; then
  warn "터미널 핸들을 찾지 못해 탭을 닫지 못했습니다. 탭은 직접 닫아 주세요."
  exit 0
fi

info "탭을 닫습니다: $handle"
exec "$ORCA" terminal close --terminal "$handle" --tab --json
