#!/usr/bin/env bash
# Orca 내장 브라우저의 분할 창 하나에 URL 여러 개를 탭으로 연다.
# 사용법: bash open-in-split.sh [--direction right|left|down|up] <url> [<url> ...]
set -euo pipefail

direction=right
if [[ "${1:-}" == "--direction" ]]; then
  direction=$2
  shift 2
fi
if [[ $# -eq 0 ]]; then
  echo "열 URL이 없습니다." >&2
  exit 1
fi

# 같은 URL의 탭이 이미 있으면 닫는다. 분할 없이 열린 탭이 남으면 왼쪽 그룹에 중복으로 쌓인다.
open_tabs=$(orca tab list --json)
for url in "$@"; do
  for page in $(URL="$url" python3 -c '
import json, os, sys
for t in json.load(sys.stdin)["result"]["tabs"]:
    if t["url"] == os.environ["URL"]:
        print(t["browserPageId"])
' <<<"$open_tabs"); do
    orca tab close --page "$page" --json >/dev/null
  done
done

# URL마다 --split을 붙인다. 분할 창이 이미 있으면 Orca는 새 창을 만들지 않고 그 창에 탭을 추가한다.
# 첫 URL에만 붙이면 나머지는 분할 창이 아닌 원래 그룹에 열린다.
for url in "$@"; do
  orca tab create --url "$url" --split "$direction" --json \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(("열림 " if d.get("ok") else "실패 ") + sys.argv[1])' "$url"
done
