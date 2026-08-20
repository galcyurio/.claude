#!/usr/bin/env bash
# clean-merged-session.sh
# 머지가 끝난 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 사본으로 되돌린 뒤,
# Orca 워크스페이스 카드를 Todo로 되돌리고 작업 탭을 닫아 세션을 마감한다.
#
# 사용법: clean-merged-session.sh [<branch>] [옵션]
#   <branch>          정리할 로컬 브랜치. 생략하면 현재 체크아웃된 브랜치.
#                     현재 브랜치가 base(develop·feature-base/*)면 삭제 없이 최신화만 한다.
#   --base <name>     PR을 못 찾았거나 접미사 매칭을 건너뛰고 싶을 때 되돌아갈 base 사본을 직접 지정
#   --stash           working tree가 깨끗하지 않으면 stash하고 진행 (기본은 중단)
#   --force-delete    git branch -D 로 삭제 (기본은 -d)
#   --sweep           같은 base에 이미 머지된 다른 로컬 브랜치도 삭제
#   --no-close        카드는 Todo로 되돌리되 탭은 닫지 않는다
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
opt_stash=0
opt_force_delete=0
opt_sweep=0
opt_no_close=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) shift; [ $# -gt 0 ] || die "--base 뒤에 브랜치 이름이 필요합니다."; opt_base="$1" ;;
    --stash) opt_stash=1 ;;
    --force-delete) opt_force_delete=1 ;;
    --sweep) opt_sweep=1 ;;
    --no-close) opt_no_close=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) [ -z "$branch" ] || die "브랜치는 하나만 지정할 수 있습니다: $branch, $1"; branch="$1"; explicit_branch=1 ;;
  esac
  shift
done

git rev-parse --git-dir > /dev/null 2>&1 || die "git 저장소 안에서 실행해야 합니다."

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
  command -v gh > /dev/null || die "gh CLI가 필요합니다. --base <name>으로 직접 지정할 수도 있습니다."
  base_ref="$(gh pr list --state merged --head "$branch" --limit 1 \
    --json baseRefName --jq '.[0].baseRefName // empty' 2>/dev/null || true)"
  if [ -z "$base_ref" ]; then
    echo "[오류] $branch 로 머지된 PR을 찾지 못했습니다." >&2
    echo "  upstream이 gone인 것은 머지 근거가 아닙니다. 사람이 머지 여부를 확인하거나," >&2
    echo "  base를 알고 있다면 --base <name>으로 다시 실행하세요." >&2
    exit 1
  fi
  info "[1/6] 머지 확인: $branch → $base_ref"

  # base 사본 결정 (worktree 디렉토리 접미사 매칭)
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir)"
  case "$common_dir" in /*) ;; *) common_dir="$PWD/$common_dir" ;; esac
  main_name="$(basename "$(dirname "$common_dir")")"
  top_name="$(basename "$top")"
  suffix=""
  case "$top_name" in
    "$main_name") suffix="" ;;
    "$main_name"*) suffix="${top_name#"$main_name"}" ;;
  esac

  base_copy=""
  for candidate in "${base_ref}${suffix}" "$base_ref"; do
    [ -n "$candidate" ] || continue
    git rev-parse --verify --quiet "refs/heads/$candidate" > /dev/null || continue
    holder="$(branch_holder "$candidate")"
    if [ -z "$holder" ] || [ "$holder" = "$top" ]; then base_copy="$candidate"; break; fi
  done
  if [ -z "$base_copy" ]; then
    echo "[오류] 되돌아갈 base 사본을 찾지 못했습니다 (base: $base_ref, 접미사: '${suffix:-없음}')." >&2
    echo "  후보:" >&2
    git branch --list "${base_ref}*" >&2
    echo "  --base <name>으로 직접 지정하세요. 사본을 새로 만들지는 않습니다." >&2
    exit 1
  fi
fi

git rev-parse --verify --quiet "refs/heads/$base_copy" > /dev/null \
  || die "base 사본이 로컬에 없습니다: $base_copy"
base_holder="$(branch_holder "$base_copy")"
if [ -n "$base_holder" ] && [ "$base_holder" != "$top" ]; then
  die "base 사본 $base_copy 는 $base_holder 가 점유 중입니다."
fi

## 3. 손실 위험 점검 (현재 브랜치를 정리할 때만)

if [ "$is_current" = 1 ] && [ -n "$(git status --porcelain)" ]; then
  echo "변경된 파일:" >&2
  git status --porcelain | head -10 >&2
  if [ "$opt_stash" = 1 ]; then
    info "[2/6] stash 후 진행합니다."
    git stash push -u -m "clean-merged-session: $branch"
  else
    die "working tree가 깨끗하지 않습니다. 커밋하거나 --stash로 다시 실행하세요."
  fi
else
  info "[2/6] working tree 확인 완료"
fi

## 4. 대상 브랜치 점유 확인

holder="$(branch_holder "$branch")"
if [ -n "$holder" ] && [ "$holder" != "$top" ]; then
  die "$branch 는 $holder 가 체크아웃 중이라 삭제할 수 없습니다. 그 worktree에서 정리하세요."
fi

## 5. git 정리

info "[3/6] 원격 상태 갱신: git fetch --prune"
git fetch --prune

if [ "$is_current" = 1 ]; then
  if [ "$base_copy" = "$current_branch" ]; then
    info "[4/6] 이미 $base_copy 에 있어 전환을 건너뜁니다"
  else
    info "[4/6] base 사본으로 전환: $base_copy"
    git switch "$base_copy"
  fi

  if git rev-parse --verify --quiet "@{upstream}" > /dev/null; then
    git pull --ff-only || die "base 사본이 원격과 갈라졌습니다. 강제로 맞추지 않고 중단합니다."
  else
    warn "$base_copy 에 upstream이 없어 pull을 건너뜁니다."
  fi

  if [ -f "$top/.gitmodules" ]; then
    git submodule update
  fi
else
  info "[4/6] 현재 브랜치가 아니므로 전환·최신화를 건너뜁니다 (현재: ${current_branch:-detached})"
fi

if [ "$sync_only" = 1 ]; then
  info "[5/6] 삭제할 작업 브랜치가 없습니다"
elif [ "$opt_force_delete" = 1 ]; then
  info "[5/6] 브랜치 강제 삭제: git branch -D $branch"
  git branch -D "$branch"
else
  info "[5/6] 브랜치 삭제: git branch -d $branch"
  git branch -d "$branch" || die "base에 포함되지 않은 커밋이 있습니다. 위 메시지를 확인하세요 (강제 삭제는 --force-delete)."
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

if "$ORCA" worktree set --worktree active --workspace-status todo --json > /dev/null 2>&1; then
  info "Orca 카드 상태를 todo로 되돌렸습니다."
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
