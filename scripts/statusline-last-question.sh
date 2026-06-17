#!/usr/bin/env bash
# statusline: 화면 하단에 "지금 답하는 마지막 질문"을 고정 표시.
# Claude Code가 stdin으로 세션 JSON(transcript_path 포함)을 넘겨준다.
# transcript(JSONL)에서 마지막 실제 user 프롬프트를 뽑아 출력한다.
# 슬래시커맨드/로컬커맨드 래퍼와 tool_result(array content)는 제외한다.

# 한글 등 멀티바이트를 문자 단위로 다루기 위해 UTF-8 로케일 강제.
# (이게 없으면 ${#q}/${q:0:N}이 바이트 기준이 되어 한글이 깨진다)
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# 표시 최대 문자 수 (바이트 아님). 터미널 폭에 맞춰 조정 가능.
MAX_CHARS=120

input=$(cat)
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

q=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  q=$(tail -n 400 "$tp" | jq -R 'fromjson? // empty' | jq -rs '
    [ .[]
      | select(.type=="user")
      | .message.content
      | select(type=="string")
      | select(test("<command-(name|message|args)>|<local-command")|not)
    ] | last // ""')
fi

# 개행 제거 + 공백 정리
q=$(printf '%s' "$q" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')

if [ -z "$q" ]; then
  printf '❓ (질문 없음)'
elif [ "${#q}" -gt "$MAX_CHARS" ]; then
  # 문자 단위 슬라이스 → 멀티바이트 중간을 끊지 않음(깨짐 방지)
  printf '❓ %s…' "${q:0:$MAX_CHARS}"
else
  printf '❓ %s' "$q"
fi
