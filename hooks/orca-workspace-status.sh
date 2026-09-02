#!/bin/sh
# Orca 워크스페이스 카드 상태를 전이시킨다. 규칙 본문은 ~/.claude/rules/orca.md 를 따른다.
# usage: orca-workspace-status.sh <in-progress|in-review|completed> [--dry-run]

set -u

target="${1:-}"
dry_run="${2:-}"

case "$target" in
  in-progress | in-review | completed) ;;
  *) exit 0 ;;
esac

# 훅 페이로드를 비우지 않으면 호출한 쪽이 파이프에서 막힐 수 있다.
payload=$(cat 2>/dev/null || printf '')

# 어떤 이벤트가 이 스크립트를 깨웠는지 추적한다.
printf '%s target=%s payload=%s\n' "$(date +%T)" "$target" \
  "$(printf '%s' "$payload" | tr -d '\n' | cut -c1-200)" \
  >> "${TMPDIR:-/tmp}/orca-workspace-status.log" 2>/dev/null || :

# PR을 만드는 명령이 실제로 실행된 경우에만 리뷰 대기로 넘긴다.
if [ "$target" = "in-review" ]; then
  printf '%s' "$payload" | grep -q 'gh pr create' || exit 0
fi

# Orca가 관리하는 세션이 아니면 아무것도 하지 않는다.
[ -n "${ORCA_WORKTREE_ID:-}" ] || exit 0

ORCA="${ORCA_CLI_COMMAND:-orca}"
command -v "$ORCA" > /dev/null 2>&1 || exit 0

current=$("$ORCA" worktree current --json 2>/dev/null \
  | sed -n 's/.*"workspaceStatus"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -1)

# 이미 목표 상태면 호출하지 않는다.
[ "$current" = "$target" ] && exit 0

# PR이 리뷰를 기다리는 동안에는 다른 상태로 되돌리지 않는다.
if [ "$current" = "in-review" ] && [ "$target" != "in-review" ]; then
  exit 0
fi

if [ "$dry_run" = "--dry-run" ]; then
  printf 'dry-run: %s -> %s\n' "${current:-unknown}" "$target"
  exit 0
fi

"$ORCA" worktree set --worktree active --workspace-status "$target" --json > /dev/null 2>&1 || exit 0
