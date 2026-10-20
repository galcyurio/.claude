#!/bin/sh
# Orca 워크스페이스 카드 상태를 전이시킨다. 규칙 본문은 ~/.claude/rules/orca.md 를 따른다.
# usage: orca-workspace-status.sh <in-progress|my-turn|resume|in-review|completed> [--dry-run]
#   my-turn  사용자가 볼 차례(턴 종료, 권한 승인·질문 대기)로 넘긴다
#   resume   My turn 카드만 In progress로 되돌린다. 도구 호출마다 불리므로 Orca를 조회하기 전에 캐시로 거른다
#   In review와 Standby 카드는 옮기지 않는다. Standby 카드에 볼 차례가 오면 읽지 않음 표시만 붙인다

set -u

# Orca 보드에서 열을 추가할 때 만들어진 id. 열 이름을 바꿔도 id는 그대로다.
MY_TURN_STATUS="status-4"
STANDBY_STATUS="status-5"

target="${1:-}"
dry_run="${2:-}"

case "$target" in
  in-progress | in-review | completed) status="$target" ;;
  my-turn) status="$MY_TURN_STATUS" ;;
  resume) status="in-progress" ;;
  *) exit 0 ;;
esac

# 훅 페이로드를 비우지 않으면 호출한 쪽이 파이프에서 막힐 수 있다.
payload=$(cat 2>/dev/null || printf '')

# Orca가 관리하는 세션이 아니면 아무것도 하지 않는다.
[ -n "${ORCA_WORKTREE_ID:-}" ] || exit 0

# 이 스크립트가 마지막으로 넣은 상태를 워크트리별로 기억한다.
cache_dir="${TMPDIR:-/tmp}/orca-workspace-status"
cache_file="$cache_dir/$(printf '%s' "$ORCA_WORKTREE_ID" | cksum | cut -d' ' -f1)"

if [ "$target" = "resume" ]; then
  [ "$(cat "$cache_file" 2>/dev/null)" = "$MY_TURN_STATUS" ] || exit 0
fi

# 어떤 이벤트가 이 스크립트를 깨웠는지 추적한다.
printf '%s target=%s payload=%s\n' "$(date +%T)" "$target" \
  "$(printf '%s' "$payload" | tr -d '\n' | cut -c1-200)" \
  >> "${TMPDIR:-/tmp}/orca-workspace-status.log" 2>/dev/null || :

# PR을 만드는 명령이 실제로 실행된 경우에만 리뷰 대기로 넘긴다.
if [ "$target" = "in-review" ]; then
  printf '%s' "$payload" | grep -q 'gh pr create' || exit 0
fi

ORCA="${ORCA_CLI_COMMAND:-orca}"
command -v "$ORCA" > /dev/null 2>&1 || exit 0

# 세션이 사라진 뒤에는 cwd로 워크트리를 찾지 못하므로 id 셀렉터를 쓴다.
selector="id:$ORCA_WORKTREE_ID"

current=$("$ORCA" worktree show --worktree "$selector" --json 2>/dev/null \
  | sed -n 's/.*"workspaceStatus"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -1)

remember() {
  mkdir -p "$cache_dir" 2>/dev/null && printf '%s' "$1" > "$cache_file" 2>/dev/null || :
}

# 이미 목표 상태면 호출하지 않는다.
if [ "$current" = "$status" ]; then
  remember "$status"
  exit 0
fi

# 사용자가 카드를 직접 옮겼으면 resume은 건드리지 않는다.
if [ "$target" = "resume" ] && [ "$current" != "$MY_TURN_STATUS" ]; then
  remember "$current"
  exit 0
fi

# PR이 리뷰를 기다리는 카드와 사용자가 세워 둔 Standby 카드는 다른 상태로 옮기지 않는다.
# Standby 카드에 볼 차례가 오면 열은 그대로 두고 사이드바에 읽지 않음 표시만 붙인다.
if [ "$current" = "in-review" ] || [ "$current" = "$STANDBY_STATUS" ]; then
  if [ "$current" = "$STANDBY_STATUS" ] && [ "$target" = "my-turn" ] && [ "$dry_run" != "--dry-run" ]; then
    "$ORCA" worktree set --worktree "$selector" --unread --json > /dev/null 2>&1 || :
  fi
  remember "$current"
  exit 0
fi

if [ "$dry_run" = "--dry-run" ]; then
  printf 'dry-run: %s -> %s\n' "${current:-unknown}" "$status"
  exit 0
fi

"$ORCA" worktree set --worktree "$selector" --workspace-status "$status" --json > /dev/null 2>&1 || exit 0
remember "$status"
