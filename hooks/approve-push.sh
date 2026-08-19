#!/usr/bin/env bash
# UserPromptSubmit — 사용자가 이 프롬프트에서 push/PR 생성을 명시적으로 지시했으면
# 그 프롬프트에만 유효한 승인 마커를 만든다. guard-push.sh 가 이 마커를 확인한다.
#
# prompt_id 로 마커를 묶으므로 다음 프롬프트에서는 자동으로 무효가 된다 —
# "push해라는 승인은 그 한 번에만 적용된다"(rules/git.md)를 그대로 구현한 것이다.
set -uo pipefail

input=$(cat)
prompt=$(printf '%s' "$input" | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); raise SystemExit
print(d.get("prompt") or "")' 2>/dev/null || printf '')
[ -z "$prompt" ] && exit 0

# 부정·유보 표현이 있으면 승인하지 않는다 ("push 하지 마", "푸시 없이", "PR은 나중에")
if printf '%s' "$prompt" | grep -Eiq '(push|푸시|PR)[^.!?]{0,12}(하지|안 |안하|말고|말아|없이|금지|보류|전에|빼고|제외|나중에|다음에|이따|할지|할까)'; then
  exit 0
fi

# 승인 표현: push/푸시/PR + 지시 동사
if printf '%s' "$prompt" | grep -Eiq '(push|푸시)([[:space:]]*(해|하자|하고|해라|해줘|해주|합니다|할래|하렴|힌|험))|force[[:space:]]*push|강제[[:space:]]*푸시|(PR|풀리퀘|pull[[:space:]]*request)[^.!?]{0,10}(생성|올려|올리|만들|작성)'; then
  dir="$HOME/.claude/cache/push-gate"
  mkdir -p "$dir"
  # 하루 넘은 마커는 정리한다
  find "$dir" -type f -mtime +1 -delete 2>/dev/null || true
  pid=$(printf '%s' "$input" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("prompt_id") or "no-prompt-id")
except Exception: print("no-prompt-id")' 2>/dev/null || printf 'no-prompt-id')
  : > "$dir/$pid"
fi
exit 0
