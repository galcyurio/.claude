#!/usr/bin/env bash
# PreToolUse(Bash) — git commit 메시지 형식을 커밋 실행 전에 검사한다.
#
# 이 훅은 모든 Bash 호출마다 실행되므로, 'git commit' 문자열이 아예 없으면
# python3 을 띄우지 않고 즉시 통과한다. 실제 파싱과 판정은 lint_commit_message.py 가 한다.
set -uo pipefail

input=$(cat)

case "$input" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

printf '%s' "$input" | python3 "$(dirname "$0")/lint_commit_message.py"
