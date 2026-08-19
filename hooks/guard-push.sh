#!/usr/bin/env bash
# PreToolUse(Bash) — git push 와 PR 생성은 사용자가 그 프롬프트에서 명시적으로
# 지시했을 때만 통과시킨다. 승인 마커는 approve-push.sh 가 prompt_id 단위로 만든다.
#
# 이 훅은 모든 Bash 호출마다 실행되므로 관련 키워드가 없으면 즉시 통과한다.
set -uo pipefail

input=$(cat)

case "$input" in
  *push*|*"pr create"*|*"pull-request"*) ;;
  *) exit 0 ;;
esac

cmd=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("tool_input",{}).get("command") or "")
except Exception: print("")' 2>/dev/null || printf '')
[ -z "$cmd" ] && exit 0

# 실제로 원격으로 나가는 명령인지 판별한다
is_outbound=0
# git 전역 옵션(-C <path>, -c <cfg>, --git-dir=…)이 앞에 붙어도 잡는다.
printf '%s' "$cmd" | grep -Eq '(^|[|;&[:space:]])git([[:space:]]+((-C|-c)[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--work-tree=[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+push([[:space:]]|$)' && is_outbound=1
printf '%s' "$cmd" | grep -Eq '(^|[|;&[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)' && is_outbound=1
[ "$is_outbound" -eq 0 ] && exit 0

pid=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("prompt_id") or "no-prompt-id")
except Exception: print("no-prompt-id")' 2>/dev/null || printf 'no-prompt-id')
marker="$HOME/.claude/cache/push-gate/$pid"

if [ -f "$marker" ]; then
  exit 0
fi

python3 - <<'PY'
import json, sys
reason = ("원격으로 나가는 액션은 사용자가 직접 통제한다. 이 프롬프트에 push·PR 생성 지시가 "
          "없어 차단했다. 로컬 커밋까지만 하고 브랜치명과 커밋 목록을 보고한 뒤 멈춘다. "
          "사용자가 \"push해\" 또는 \"PR 생성해\"라고 지시하면 그때 다시 시도한다. "
          "자세한 규칙은 ~/.claude/rules/git.md 의 push / PR 규칙에 있다.")
json.dump({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": reason,
}}, sys.stdout, ensure_ascii=False)
PY
exit 0
