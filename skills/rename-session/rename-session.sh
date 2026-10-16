#!/usr/bin/env bash
# Jira 제목에 맞춰 Orca 이름을 바꾸고 Claude 세션 /rename 명령 2줄을 출력한다.
#
# 사용법:
#   rename-session.sh <이슈키> --summary <Jira 원본 제목> [--epic]
#
#   이슈  : 현재 터미널 탭 제목을 "<키> <핵심 제목>"으로 바꾼다 (start-worktree와 같은 형식).
#   --epic: 현재 worktree 카드의 표시 이름을 Jira 원본 제목으로 바꾼다 (start-feature와 같은 형식).
set -uo pipefail

ORCA="${ORCA_CLI_COMMAND:-orca}"

die() { echo "[오류] $*" >&2; exit 1; }

key="${1:-}"
[ -n "$key" ] && [ "${key#-}" = "$key" ] || die "첫 인자로 이슈 키를 넘기세요. 예: HDA-12345"
shift
summary=""
epic=0
while [ $# -gt 0 ]; do
  case "$1" in
    --summary) summary="${2:-}"; shift 2 ;;
    --epic) epic=1; shift ;;
    *) die "알 수 없는 인자: $1" ;;
  esac
done
[ -n "$summary" ] || die "--summary 에 Jira 원본 제목을 넘기세요."

# 앞머리 대괄호 그룹([고객], [마켓 추천 매물 강화] 등)을 모두 뗀 핵심 제목
short="$(printf '%s' "$summary" | sed -E 's/^([[:space:]]*\[[^]]*\])+[[:space:]]*//')"
[ -n "$short" ] || short="$summary"

# 현재 orca 터미널 핸들. start-worktree.sh 의 같은 함수와 동일한 방식으로 찾는다.
orca_terminal_handle() {
  if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then printf '%s' "$ORCA_TERMINAL_HANDLE"; return; fi
  [ -n "${ORCA_TAB_ID:-}" ] || return 0
  "$ORCA" terminal list --worktree active --json 2>/dev/null | python3 -c '
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
' || true
}

if ! command -v "$ORCA" > /dev/null 2>&1; then
  echo "[건너뜀] orca 명령을 찾지 못해 Orca 이름은 바꾸지 않았습니다." >&2
elif [ "$epic" = 1 ]; then
  [ -n "${ORCA_WORKTREE_ID:-}" ] || die "ORCA_WORKTREE_ID 가 없어 카드를 특정하지 못했습니다."
  "$ORCA" worktree set --worktree "id:$ORCA_WORKTREE_ID" --display-name "$summary" --json > /dev/null \
    || die "카드 표시 이름을 바꾸지 못했습니다: $summary"
  echo "[완료] 카드 표시 이름: $summary" >&2
else
  handle="$(orca_terminal_handle)"
  [ -n "$handle" ] || die "현재 터미널 핸들을 찾지 못했습니다."
  "$ORCA" terminal rename --terminal "$handle" --title "$key $short" --json > /dev/null \
    || die "탭 제목을 바꾸지 못했습니다: $key $short"
  echo "[완료] 탭 제목: $key $short" >&2
fi

printf '/rename %s %s\n/rename %s %s\n' "$key" "$summary" "$key" "$short"
