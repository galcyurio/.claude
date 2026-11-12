#!/usr/bin/env bash
# PR 리뷰 세션의 Orca 탭 제목을 PR 제목으로 바꾼다.
#
# 사용법:
#   rename-review-tab.sh <targetDesc> <PR 제목> [<targetDesc> <PR 제목> ...]
#
#   제목에 Jira 키가 있으면 "🔍 리뷰 · <키> <핵심 제목>", 없으면 "🔍 리뷰 · <targetDesc> <제목>"으로 바꾼다.
#   핵심 제목은 앞머리의 Jira 키와 대괄호 그룹([고객] 등)을 모두 뗀 제목이다(rename-session과 같은 형식).
#   PR이 여러 개면 첫 PR로 제목을 짓고 "외 N개"를 붙인다.
#   Orca 밖이거나 rename이 실패해도 리뷰를 막지 않도록 항상 0으로 끝낸다.
set -uo pipefail

ORCA="${ORCA_CLI_COMMAND:-orca}"
[ $# -ge 2 ] || exit 0
[ -n "${ORCA_TERMINAL_HANDLE:-}" ] && command -v "$ORCA" >/dev/null 2>&1 || exit 0

desc=$1 title=$2
rest=$(( $# / 2 - 1 ))

key=$(printf '%s' "$title" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
short=$(printf '%s' "$title" | sed -E 's/^[[:space:]]*[A-Z][A-Z0-9]+-[0-9]+[[:space:]]*//; s/^([[:space:]]*\[[^]]*\])+[[:space:]]*//')
[ -n "$short" ] || short=$title

if [ -n "$key" ]; then label="$key $short"; else label="$desc $short"; fi
[ "$rest" -gt 0 ] && label="$label 외 ${rest}개"

"$ORCA" terminal rename --terminal "$ORCA_TERMINAL_HANDLE" --title "🔍 리뷰 · $label" --json >/dev/null 2>&1 \
  && echo "[완료] 탭 제목: 🔍 리뷰 · $label" >&2
exit 0
