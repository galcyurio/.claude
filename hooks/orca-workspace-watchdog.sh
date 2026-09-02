#!/bin/sh
# 이 세션의 claude 프로세스를 지켜보다가, 그것이 사라지면 Orca 카드를 Done으로 넘긴다.
# 탭을 그대로 닫아 SessionEnd 훅이 오지 않는 경로를 받치는 것이 목적이다.
# SessionStart 훅에 async 로 등록해 실행한다.

set -u

status_script="$(dirname "$0")/orca-workspace-status.sh"

# Orca가 관리하는 세션이 아니면 지켜볼 이유가 없다.
[ -n "${ORCA_WORKTREE_ID:-}" ] || exit 0

# 조상 프로세스를 거슬러 올라가 이 세션의 claude 프로세스를 찾는다.
find_claude_pid() {
  pid=$$
  depth=0
  while [ "$depth" -lt 8 ]; do
    parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    case "$parent" in
      '' | 0 | 1) return 1 ;;
    esac
    case "$(ps -o comm= -p "$parent" 2>/dev/null)" in
      *claude*)
        printf '%s' "$parent"
        return 0
        ;;
    esac
    pid=$parent
    depth=$((depth + 1))
  done
  return 1
}

watched=$(find_claude_pid || printf '')
[ -n "$watched" ] || exit 0

# 같은 세션에 지킴이가 겹쳐 뜨지 않게 한다.
marker="${TMPDIR:-/tmp}/orca-workspace-watchdog.$watched"
[ -e "$marker" ] && exit 0
: > "$marker" 2>/dev/null || :

while kill -0 "$watched" 2>/dev/null; do
  sleep 5
done

rm -f "$marker" 2>/dev/null || :
sh "$status_script" completed < /dev/null > /dev/null 2>&1 || :
exit 0
