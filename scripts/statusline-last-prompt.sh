#!/usr/bin/env bash
# statusline: 화면 하단에 "지금 답하는 마지막 프롬프트"를 고정 표시.
# Claude Code가 stdin으로 세션 JSON(transcript_path 포함)을 넘겨준다.
# transcript(JSONL)에서 마지막 실제 user 프롬프트를 뽑아 출력한다.
# 슬래시/로컬커맨드 래퍼·tool_result(array content)는 제외하고,
# 하니스가 주입하는 블록(task-notification·bash 출력·system-reminder)은
# 사람이 읽는 라벨로 바꿔 표시한다. 태그는 startsWith로 판정하고(닫는 태그가 없거나
# 스트리밍 중이라도 잡힘), 시스템 라벨은 ⚙️ emoji로, 실제 프롬프트는 ❓로 구분한다.

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
  # user 메시지에서 표시 후보를 뽑는다.
  #  - content가 string → 일반 프롬프트(슬래시/로컬커맨드 래퍼 제외)
  #  - content가 array  → AskUserQuestion 답변(tool_result)의 안내 문구
  # 문서 순서를 유지하므로 last가 "가장 최근 user 입력"이 된다.
  q=$(tail -n 400 "$tp" | jq -R 'fromjson? // empty' | jq -rs '
    # 표시할 실제 텍스트에서 주입 블록·stray 태그·양끝 공백을 제거한다.
    def clean_text:
      gsub("<bash-stdout>[\\s\\S]*?</bash-stdout>";"")
      | gsub("<bash-stderr>[\\s\\S]*?</bash-stderr>";"")
      | gsub("<system-reminder>[\\s\\S]*?</system-reminder>";"")
      | gsub("<task-notification>[\\s\\S]*?</task-notification>";"")
      | gsub("</?(bash-stdout|bash-stderr|bash-input|system-reminder|task-notification)>";"")
      | gsub("^\\s+|\\s+$";"");
    # string user content → 표시 문자열.
    # 태그 판정은 startsWith(앵커)로 한다: 닫는 태그가 없거나 스트리밍 중이라도 잡힌다.
    # 시스템 주입 라벨은 SOH(U+0001) 마커로 시작한다. statusline이 ❓ 대신 ⚙️ 를 붙인다.
    def display($s):
      ($s | sub("^\\s+";"")) as $t
      | if   ($t|test("^<command-(name|message|args)>")) or ($t|startswith("<local-command")) then empty
        elif ($t|startswith("<task-notification")) then "백그라운드 작업 완료"
        elif ($t|startswith("<system-reminder"))   then "시스템 리마인더"
        elif ($t|test("^<bash-(stdout|stderr|input)")) then
            ($t|clean_text) as $rest
            | if ($rest|length) > 0 then $rest else "bash 실행" end
        else ($t|clean_text)
        end;
    [ .[]
      | select(.type=="user")
      | .message.content as $c
      | if ($c|type)=="string" then display($c)
        elif ($c|type)=="array" then
          ( $c[]
            | select(.type=="tool_result")
            | (.content // empty)
            | (if type=="array" then (map(.text? // "")|join(" ")) else . end)
            | select(type=="string")
            | select(test("^Your questions have been answered"))
          )
        else empty end
    ] | last // ""')
fi

# AskUserQuestion 답변이면 보기 좋게 정리: 안내 문구 제거 + "프롬프트"="답변" → 프롬프트 → 답변
q=$(printf '%s' "$q" \
  | sed -E 's/^Your questions have been answered: //; s/\. You can now continue with these answers in mind\.$//' \
  | sed -E 's/"([^"]*)"="([^"]*)"/\1 → \2/g')

# 개행 제거 + 공백 정리
q=$(printf '%s' "$q" | tr '\n' ' ' | sed 's/  */ /g; s/^ *//; s/ *$//')

if [ -z "$q" ]; then
  printf '❓ (프롬프트 없음)'
else
  # 시스템 주입 라벨(SOH 마커로 시작)은 ⚙️ 를, 실제 프롬프트는 ❓ 를 붙인다.
  prefix='❓ '
  case "$q" in $'\001'*) q="${q#$'\001'}"; prefix='⚙️ ' ;; esac
  if [ "${#q}" -gt "$MAX_CHARS" ]; then
    # 문자 단위 슬라이스 → 멀티바이트 중간을 끊지 않음(깨짐 방지)
    printf '%s%s…' "$prefix" "${q:0:$MAX_CHARS}"
  else
    printf '%s%s' "$prefix" "$q"
  fi
fi
