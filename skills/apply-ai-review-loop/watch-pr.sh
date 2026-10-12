#!/bin/bash
# PR 하나의 CI 종료 상태와 새로 생긴 미해결 리뷰 스레드를 주기적으로 확인해 한 줄씩 출력한다.
# Monitor 의 command 로 띄운다. 출력 한 줄이 알림 하나다.
#
#   watch-pr.sh <owner/repo> <PR 번호> [--interval 60]
#
# 기준값: ~/.claude/state/apply-ai-review-loop/<owner>_<repo>_<n>/seen (줄마다 스레드 URL)
#   파일이 없으면 지금 보이는 미해결 스레드를 전부 기준값으로 저장하고 출력하지 않는다.
#   파일이 있으면(감시 재시작) 그대로 쓴다. 한 번 출력한 스레드는 seen 에 추가해 다시 내보내지 않는다.
#
# 출력 형식:
#   CI <head sha 7자리> pass|fail     현재 head 의 체크가 모두 끝났을 때, head·결과 조합마다 한 번
#   THREAD <작성자> <path>:<line> <첫 코멘트 URL>
#   ERROR <내용>                       조회가 3회 연속 실패했을 때
set -uo pipefail

REPO=${1:?owner/repo}
NUMBER=${2:?PR 번호}
shift 2
INTERVAL=60
while [ $# -gt 0 ]; do
  case $1 in
    --interval) INTERVAL=$2; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

OWNER=${REPO%%/*}
NAME=${REPO##*/}
STATE=~/.claude/state/apply-ai-review-loop/${OWNER}_${NAME}_${NUMBER}
SEEN=$STATE/seen
mkdir -p "$STATE"

QUERY='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved path line originalLine comments(first:1){nodes{url author{login}}}}}}}}'

# 줄마다 "url<TAB>작성자<TAB>path:line"
unresolved_threads() {
  gh api graphql -f query="$QUERY" -F owner="$OWNER" -F name="$NAME" -F number="$NUMBER" \
    --jq '.data.repository.pullRequest.reviewThreads.nodes[]
      | select(.isResolved | not)
      | [.comments.nodes[0].url, .comments.nodes[0].author.login, "\(.path):\(.line // .originalLine)"] | @tsv'
}

if [ ! -f "$SEEN" ]; then
  threads=$(unresolved_threads) || { echo "ERROR 기준값 조회 실패"; exit 1; }
  cut -f1 <<<"$threads" | sed '/^$/d' > "$SEEN"
fi

last_ci=""
failures=0
while true; do
  ok=1

  if threads=$(unresolved_threads); then
    while IFS=$'\t' read -r url author location; do
      [ -n "$url" ] || continue
      grep -qxF "$url" "$SEEN" && continue
      echo "$url" >> "$SEEN"
      echo "THREAD $author $location $url"
    done <<<"$threads"
  else
    ok=0
  fi

  # pending 이 남아 있으면 gh 가 0 이 아닌 코드로 끝나므로 종료 코드 대신 JSON 을 본다
  checks=$(gh pr checks "$NUMBER" -R "$REPO" --json bucket 2>/dev/null)
  head=$(gh pr view "$NUMBER" -R "$REPO" --json headRefOid --jq '.headRefOid[0:7]' 2>/dev/null)
  if [ -n "$checks" ] && [ -n "$head" ]; then
    result=$(jq -r 'if length == 0 or any(.bucket == "pending") then ""
      elif any(.bucket == "fail" or .bucket == "cancel") then "fail" else "pass" end' <<<"$checks")
    if [ -n "$result" ] && [ "$head $result" != "$last_ci" ]; then
      last_ci="$head $result"
      echo "CI $last_ci"
    fi
  else
    ok=0
  fi

  if [ $ok -eq 1 ]; then
    failures=0
  else
    failures=$((failures + 1))
    [ $failures -eq 3 ] && echo "ERROR gh 조회 3회 연속 실패"
  fi
  sleep "$INTERVAL"
done
