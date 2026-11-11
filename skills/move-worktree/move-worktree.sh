#!/usr/bin/env bash
# move-worktree.sh
# 진행 중인 작업 브랜치와 현재 claude 세션을 같은 저장소의 다른 유휴 worktree로 옮긴다.
# 원래 자리는 짝이 맞는 base 사본으로 되돌리고, 대상 자리에 새 탭을 띄운 뒤 이 탭을 닫는다.
#
# 사용법: move-worktree.sh <대상 자리 경로> [옵션]
#   --discard-target  대상 자리(앱·서브모듈)의 미커밋 변경을 버리고 진행한다
#   --dry-run         파괴적 동작 없이 확인 결과와 계획만 출력
#
# 종료 코드: 0 성공, 1 중단, 3 대상 자리에 미커밋 변경이 있어 중단
set -euo pipefail

die() { echo "[오류] $*" >&2; exit 1; }
warn() { echo "[경고] $*" >&2; }
info() { echo "$*"; }

source "$HOME/.claude/skills/start-worktree/session-move.sh"

LIB=prnd-library

target_arg=""
opt_discard=0
opt_dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --discard-target) opt_discard=1; shift ;;
    --dry-run) opt_dry_run=1; shift ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) target_arg="$1"; shift ;;
  esac
done
[ -n "$target_arg" ] || die "대상 자리 경로가 필요합니다. 사용법: move-worktree.sh <경로>"

# 서브모듈 안에서 불렸으면 앱 저장소로 올라간다.
superproject="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
[ -z "$superproject" ] || cd "$superproject"

# git worktree list 표기로 맞춘 자리 경로. 목록에 없으면 비어 있다.
worktree_entry() {
  local wt
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    if [ "$wt" -ef "$1" ]; then printf '%s' "$wt"; return 0; fi
  done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')
}

branch_holder() {
  git worktree list --porcelain | awk -v b="branch refs/heads/$1" '
    /^worktree /{p=substr($0,10)}
    $0==b{print p}'
}

current_branch_of() { git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true; }

# 앱과 서브모듈의 미커밋 변경. 서브모듈 포인터 차이(" m")는 서브모듈 쪽에서 따로 보므로 뺀다.
dirty_summary() {
  local wt="$1"
  git -C "$wt" status --short --ignore-submodules=all
  # 초기화되지 않은 서브모듈 디렉터리에서 git을 부르면 앱 저장소를 보게 되므로 .git으로 가린다.
  if [ -e "$wt/$LIB/.git" ]; then
    git -C "$wt/$LIB" status --short | sed "s|^|$LIB: |"
  fi
}

is_base_branch() {
  case "$1" in develop|develop-*|feature-base/*|release/*|main|master) return 0 ;; esac
  return 1
}

source_wt="$(worktree_entry "$(git rev-parse --path-format=absolute --show-toplevel)")"
[ -d "$target_arg" ] || die "대상 자리가 없습니다: $target_arg (자리를 새로 만들려면 start-worktree를 쓰세요)"
target_wt="$(worktree_entry "$target_arg")"
[ -n "$target_wt" ] || die "같은 저장소의 worktree가 아닙니다: $target_arg"
[ "$target_wt" != "$source_wt" ] || die "이미 그 자리에 있습니다: $target_wt"

# 1. 사전 확인
work_branch="$(current_branch_of "$source_wt")"
[ -n "$work_branch" ] || die "현재 자리가 detached HEAD라 옮길 브랜치가 없습니다."
is_base_branch "$work_branch" && die "현재 자리가 base 브랜치($work_branch)라 옮길 작업이 없습니다."

src_dirty="$(dirty_summary "$source_wt")"
if [ -n "$src_dirty" ]; then
  echo "$src_dirty" >&2
  die "현재 자리에 미커밋 변경이 있습니다. 커밋하거나 정리한 뒤 다시 실행하세요."
fi

target_copy="$(current_branch_of "$target_wt")"
[ -n "$target_copy" ] || die "대상 자리가 detached HEAD입니다: $target_wt"
upstream="$(git rev-parse --abbrev-ref "$target_copy@{upstream}" 2>/dev/null || true)"
pool="${upstream#origin/}"
if [ -z "$upstream" ] || [ "$pool" = "$upstream" ] || ! is_base_branch "$target_copy" \
  || { [ "$target_copy" != "$pool" ] && [ "${target_copy#"$pool"-}" = "$target_copy" ]; }; then
  die "대상 자리가 base 사본을 물고 있지 않습니다: $target_wt ($target_copy). 작업 중인 자리로는 옮기지 않습니다."
fi

tgt_dirty="$(dirty_summary "$target_wt")"
if [ -n "$tgt_dirty" ] && [ "$opt_discard" = 0 ]; then
  echo "[중단] 대상 자리에 미커밋 변경이 있습니다: $target_wt" >&2
  echo "$tgt_dirty" >&2
  exit 3
fi

# 원래 자리가 되돌아갈 base 사본. 자리 이름 끝 번호와 사본 접미사가 짝이어야
# release-worktree·start-worktree가 이 자리를 유휴 자리로 다시 찾는다.
# 원래 자리의 풀은 대상 자리의 풀과 다를 수 있다(feature-base 자리에서 develop 자리로 옮기는 경우).
# 그래서 원래 자리의 풀은 상위 자리(이름 끝 -N을 뗀 자리)가 문 base 브랜치로 정하고,
# 상위 자리를 찾지 못했을 때만 대상 자리의 풀을 쓴다.
source_copy=""
src_num=""
src_pool="$pool"
case "$(basename "$source_wt")" in *-[0-9]|*-[0-9][0-9]) src_num="${source_wt##*-}" ;; esac
if [ -n "$src_num" ]; then
  parent_entry="$(worktree_entry "${source_wt%-"$src_num"}" 2>/dev/null || true)"
  if [ -n "$parent_entry" ]; then
    parent_branch="$(current_branch_of "$parent_entry")"
    if [ -n "$parent_branch" ] && is_base_branch "$parent_branch"; then
      src_pool="$parent_branch"
    fi
  fi
fi
for candidate in ${src_num:+"$src_pool-$src_num"} "$src_pool"; do
  [ -z "$src_num" ] || [ "$candidate" != "$src_pool" ] || continue
  git rev-parse --verify --quiet "refs/heads/$candidate" > /dev/null || continue
  [ -z "$(branch_holder "$candidate")" ] || continue
  source_copy="$candidate"; break
done
expected_copy="$src_pool"
[ -z "$src_num" ] || expected_copy="$src_pool-$src_num"
[ -n "$source_copy" ] || die "현재 자리가 되돌아갈 base 사본을 찾지 못했습니다 (풀 base: $src_pool, 후보: $expected_copy)."

# 서브모듈이 작업 브랜치를 물고 있으면 대상 자리의 서브모듈에서도 같은 브랜치를 문다.
lib_branch=""
if [ -e "$source_wt/$LIB/.git" ] && [ "$(current_branch_of "$source_wt/$LIB")" = "$work_branch" ]; then
  lib_branch="$work_branch"
fi

info "[1/3] 확인 완료"
info "  작업 브랜치: $work_branch${lib_branch:+ (라이브러리 서브모듈 포함)}"
info "  원래 자리: $source_wt -> $source_copy"
info "  대상 자리: $target_wt ($target_copy) -> $work_branch"
[ -z "$tgt_dirty" ] || info "  대상 자리의 미커밋 변경을 버립니다 (--discard-target)"

title="$("$ORCA" terminal list --worktree active --json 2>/dev/null | python3 -c '
import json, os, sys
tab = os.environ.get("ORCA_TAB_ID", "")
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in (data.get("result") or {}).get("terminals") or []:
    if t.get("tabId") == tab:
        print(t.get("title", "")); break
' 2>/dev/null || true)"
title="${title:-$work_branch}"

first_prompt="세션을 $source_wt 에서 $target_wt 로 옮겼다(브랜치 $work_branch). 자리만 옮긴 것이므로 새 작업을 시작하지 않는다. git status와 현재 브랜치를 확인해 한두 줄로 보고하고 다음 지시를 기다린다."

if [ "$opt_dry_run" = 1 ]; then
  info "[dry-run] 탭 제목: $title"
  info "[dry-run] 첫 프롬프트: $first_prompt"
  move_session "$target_wt" "$title" "$first_prompt" 1 "[3/3]" ""
fi

# 2. 브랜치 이동
if [ -n "$tgt_dirty" ]; then
  git -C "$target_wt" restore --staged --worktree :/
  git -C "$target_wt" clean -fd
  if [ -e "$target_wt/$LIB/.git" ]; then
    git -C "$target_wt/$LIB" restore --staged --worktree :/
    git -C "$target_wt/$LIB" clean -fd
  fi
fi
git -C "$source_wt" switch "$source_copy" || die "원래 자리를 $source_copy 로 되돌리지 못했습니다."
git -C "$source_wt" submodule update \
  || warn "원래 자리의 서브모듈 포인터를 맞추지 못했습니다."
git -C "$target_wt" switch "$work_branch" \
  || die "대상 자리에서 $work_branch 로 전환하지 못했습니다. 원래 자리는 $source_copy 로 돌아가 있습니다."
git -C "$target_wt" submodule update --init \
  || warn "대상 자리의 서브모듈 포인터를 맞추지 못했습니다."
if [ -n "$lib_branch" ]; then
  git -C "$target_wt/$LIB" switch "$lib_branch" \
    || warn "대상 자리의 서브모듈을 $lib_branch 로 전환하지 못했습니다."
fi
info "[2/3] 브랜치 이동 완료: $target_wt ($work_branch)"

# 3. 세션 이사
move_session "$target_wt" "$title" "$first_prompt" 0 "[3/3]" "[3/3]"
