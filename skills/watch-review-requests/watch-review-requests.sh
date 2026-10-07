#!/bin/bash
# 나에게 온 리뷰 요청을 주기적으로 확인해, PR 마다 Orca 리뷰 세션을 열어 /review-by-agents 를 보낸다.
# 이 터미널을 점유한다. Enter 를 누르면 바로 확인하고, 끄려면 Ctrl+C 또는 탭을 닫는다.
#
#   watch-review-requests                  10분 간격으로 모니터링
#   watch-review-requests --interval 300   간격(초) 지정
set -uo pipefail

INTERVAL=600
while [ $# -gt 0 ]; do
  case $1 in
    --interval) INTERVAL=$2; shift 2 ;;
    -h|--help) sed -n 2,6p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done

ORG=PRNDcompany
WORKSPACE=~/dev
STATE=~/.claude/state/watch-review-requests
DISPATCHED=$STATE/dispatched   # 세션에 보낸 PR. 줄마다 "repo#n"
SESSIONS=$STATE/sessions       # PR → 리뷰 세션. 줄마다 "repo#n handle"
LOG=$STATE/watch.log
DEFERRED=$STATE/deferred       # 이번 확인에서 못 보낸 PR 과 사유. 줄마다 "repo#n<TAB>사유"
TAB_TITLE="📡 리뷰 모니터"
# 이 시간 안에 출력이 있던 세션은 응답 중이거나 내가 입력 중일 수 있어 다음 확인으로 미룬다
BUSY_MS=30000

mkdir -p "$STATE"
touch "$DISPATCHED" "$SESSIONS" "$DEFERRED"

LOCK=$STATE/lock
if ! mkdir "$LOCK" 2>/dev/null; then
  pid=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "이미 실행 중 (pid $pid)" >&2; exit 1
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo $$ > "$LOCK/pid"
rename_tab() {
  [ -n "${ORCA_TERMINAL_HANDLE:-}" ] || return 0
  orca terminal rename --terminal "$ORCA_TERMINAL_HANDLE" ${1:+--title "$1"} --json >/dev/null 2>&1 || true
}
trap 'rm -rf "$LOCK"; echo; log "종료"; exit 0' INT TERM
trap 'rm -rf "$LOCK"; rename_tab; [ -t 1 ] && printf '"'"'\e[?25h'"'"'' EXIT

# 화면은 확인마다 다시 그려지므로 기록은 파일에만 남긴다
log() { echo "$(date '+%m-%d %H:%M') $*" >> "$LOG"; }

for cmd in gh jq orca; do
  command -v $cmd >/dev/null || { echo "$cmd 없음" >&2; exit 1; }
done

ME=$(gh api user --jq .login) || { echo "gh 로그인 확인 실패" >&2; exit 1; }

# 리뷰 세션을 띄울 Orca 작업 공간. 이 탭이 떠 있는 곳을 그대로 쓴다
WORKTREE_SELECTOR=${WATCH_REVIEW_REQUESTS_WORKTREE:-}
if [ -z "$WORKTREE_SELECTOR" ] && [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then
  wid=$(orca terminal show --terminal "$ORCA_TERMINAL_HANDLE" --json 2>/dev/null | jq -r '.. | .worktreeId? // empty' | head -1)
  [ -n "$wid" ] && WORKTREE_SELECTOR="id:$wid"
fi
[ -n "$WORKTREE_SELECTOR" ] || { echo "Orca 터미널 안에서 실행하거나 WATCH_REVIEW_REQUESTS_WORKTREE 를 지정" >&2; exit 1; }

# 개인으로 지정된 요청만. 팀 단위 요청은 user-review-requested 에 걸리지 않는다
fetch_requests() {
  gh api -X GET search/issues \
    -f q="org:$ORG is:pr is:open draft:false archived:false user-review-requested:@me" \
    -f per_page=100 \
    --jq '.items[] | [(.repository_url | sub(".*/repos/"; "")), (.number|tostring), .html_url, .title] | @tsv'
}

# 손으로 리뷰를 시작해 초안만 남겨 둔 PR 에 세션을 또 띄우지 않으려고 본다
has_my_pending_review() {  # $1 repo, $2 number
  local n
  n=$(gh api "repos/$1/pulls/$2/reviews" --paginate \
    --jq "[.[] | select(.user.login == \"$ME\" and .state == \"PENDING\")] | length" 2>/dev/null)
  [ "${n:-0}" -gt 0 ] 2>/dev/null
}

ticket_of() {  # $1 title, $2 fallback
  local k; k=$(printf '%s' "$1" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | head -1)
  printf '%s' "${k:-$2}"
}

live_terminals() {
  orca terminal list --json 2>/dev/null \
    | jq -r '.result.terminals[] | select(.connected) | [.handle, (.lastOutputAt // 0 | tostring)] | @tsv'
}

session_of() { awk -v k="$1" '$1==k {print $2}' "$SESSIONS" | tail -1; }

set_session() {
  { grep -v "^$1 " "$SESSIONS"; echo "$1 $2"; } > "$SESSIONS.tmp"; mv "$SESSIONS.tmp" "$SESSIONS"
}

quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# review-by-agents 는 PR 하나를 받고 실행 위치의 레포에서 gh pr diff 를 돌리므로, PR 마다 그 레포 클론에서 세션을 띄운다
# $1 repo#n, $2 url. 성공하면 0
dispatch() {
  local key=$1 urls=$2 prompt handle last now repo dir
  prompt="/review-by-agents $urls"
  repo=${key%#*}; dir=$WORKSPACE/${repo#*/}
  [ -d "$dir/.git" ] || [ -f "$dir/.git" ] || { DEFER_REASON="레포 클론 없음 실패"; log "  $key $dir 클론이 없음"; return 1; }
  handle=$(session_of "$key")
  if [ -n "$handle" ]; then
    last=$(printf '%s\n' "$LIVE" | awk -v h="$handle" '$1==h {print $2}')
    if [ -n "$last" ]; then
      now=$(( $(date +%s) * 1000 ))
      if [ $(( now - last )) -lt $BUSY_MS ]; then
        DEFER_REASON="세션 응답 중"; log "  $key 세션이 응답 중이라 다음 확인으로 미룸"; return 1
      fi
      orca terminal send --terminal "$handle" --text "$prompt" --enter --json >/dev/null 2>&1 \
        || { DEFER_REASON="기존 세션에 보내기 실패"; log "  $key 기존 세션에 보내기 실패"; return 1; }
      log "  $key → 기존 세션 $urls"; return 0
    fi
  fi
  handle=$(orca terminal create --worktree "$WORKTREE_SELECTOR" --title "🔍 리뷰 · ${key#*/}" \
      --command "cd $(quote "$dir") && claude $(quote "$prompt")" --json 2>&1 \
    | grep -oE 'term_[0-9a-f-]+' | head -1)
  [ -n "$handle" ] || { DEFER_REASON="세션 띄우기 실패"; log "  $key 세션 띄우기 실패"; return 1; }
  set_session "$key" "$handle"
  command -v terminal-notifier >/dev/null && terminal-notifier -title "🔍 리뷰 세션 시작" \
    -subtitle "$key" -message "$urls" -sound Glass >/dev/null 2>&1 &
  log "  $key → 새 세션 $urls"
}

check() {
  local reqs total new=0 sent=0
  : > "$DEFERRED"   # 못 보낸 요청은 매번 다시 시도하므로 사유도 매번 새로 쓴다
  if ! reqs=$(fetch_requests 2>&1); then
    log "확인 실패: $(printf '%s' "$reqs" | head -1)"; return
  fi
  total=$(printf '%s' "$reqs" | grep -c . || true)

  # 리뷰를 제출하거나 요청이 풀리면 목록에서 빠진다. 지워 둬야 재요청을 새 요청으로 잡는다
  printf '%s\n' "$reqs" > "$STATE/requests.tsv"
  printf '%s\n' "$reqs" | awk -F'\t' 'NF {print $1"#"$2}' | sort -u > "$STATE/current"
  local gone; gone=$(sort -u "$DISPATCHED" | comm -23 - "$STATE/current")
  [ -z "$gone" ] || printf '%s\n' "$gone" | while read -r id; do log "  $id 요청 해제 (리뷰 제출 또는 요청 취소)"; done
  sort -u "$DISPATCHED" | comm -12 - "$STATE/current" > "$DISPATCHED.tmp"; mv "$DISPATCHED.tmp" "$DISPATCHED"

  # 아직 안 보낸 요청. 줄마다 "repo#n<TAB>repo#n<TAB>url"
  local pending; pending=$(printf '%s\n' "$reqs" | while IFS=$'\t' read -r repo n url title; do
    [ -n "$repo" ] || continue
    grep -qxF "$repo#$n" "$DISPATCHED" && continue
    if has_my_pending_review "$repo" "$n"; then
      echo "$repo#$n" >> "$DISPATCHED"; log "  $repo#$n 내 pending review 가 있어 리뷰 중으로 넘김"; continue
    fi
    printf '%s\t%s\t%s\n' "$repo#$n" "$repo#$n" "$url"
  done)

  if [ -n "$pending" ]; then
    new=$(printf '%s\n' "$pending" | grep -c .)
    LIVE=$(live_terminals)
    local key
    for key in $(printf '%s\n' "$pending" | cut -f1 | sort -u); do
      local urls ids
      urls=$(printf '%s\n' "$pending" | awk -F'\t' -v k="$key" '$1==k {print $3}' | tr '\n' ' ' | sed 's/ $//')
      ids=$(printf '%s\n' "$pending" | awk -F'\t' -v k="$key" '$1==k {print $2}')
      DEFER_REASON=""
      if dispatch "$key" "$urls"; then
        printf '%s\n' "$ids" >> "$DISPATCHED"; sent=$((sent + 1))
      else
        printf '%s\n' "$ids" | while read -r id; do printf '%s\t%s\n' "$id" "$DEFER_REASON"; done >> "$DEFERRED"
      fi
    done
  fi
  log "확인 · 요청 ${total}건 · 새 ${new}건 · 보냄 ${sent}건"
}

truncate() { perl -CSA -e 'my $s = $ARGV[0]; print length($s) > $ARGV[1] ? substr($s, 0, $ARGV[1]) . "\x{2026}" : $s' "$1" "$2"; }

C_RESET=$'\e[0m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'
C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_GRAY=$'\e[90m'; C_CYAN=$'\e[36m'
SEP=$''   # agnoster 와 같은 powerline 구분자

# 배경색 · 글자색 쌍을 받아 이어 붙인 powerline 띠를 그린다. 인자: "bg fg 텍스트" …
segments() {
  local prev="" seg bg fg text
  for seg in "$@"; do
    bg=${seg%% *}; seg=${seg#* }; fg=${seg%% *}; text=${seg#* }
    [ -z "$prev" ] || printf '\e[38;5;%sm\e[48;5;%sm%s' "$prev" "$bg" "$SEP"
    printf '\e[48;5;%sm\e[38;5;%sm %s ' "$bg" "$fg" "$text"
    prev=$bg
  done
  printf '\e[0m\e[38;5;%sm%s\e[0m\n' "$prev" "$SEP"
}

status_of() {  # $1 repo#n
  local reason
  reason=$(awk -F'\t' -v id="$1" '$1==id {print $2}' "$DEFERRED" | tail -1)
  if [ -n "$reason" ]; then
    case $reason in
      *실패*) printf '%s● 세션 실패%s' "$C_RED" "$C_RESET" ;;
      *) printf '%s● 세션 대기 중%s' "$C_YELLOW" "$C_RESET" ;;
    esac
  elif grep -qxF "$1" "$DISPATCHED"; then
    printf '%s● 리뷰 중%s' "$C_GREEN" "$C_RESET"
  fi
}

render() {
  local count
  count=$(grep -c . "$STATE/requests.tsv" 2>/dev/null || true)
  clear
  segments "24 255 $TAB_TITLE" "238 250 요청 ${count:-0}건" "236 245 확인 $(date '+%H:%M')" \
    "234 242 다음 $(date -v+"${INTERVAL}"S '+%H:%M') · $((INTERVAL / 60))분 간격"
  echo
  if [ "${count:-0}" = 0 ]; then
    printf '  %s리뷰 요청 없음%s\n' "$C_DIM" "$C_RESET"
  else
    while IFS=$'\t' read -r repo n url title; do
      [ -n "$repo" ] || continue
      local key label
      key=$(ticket_of "$title" "$repo#$n")
      label=$key; [ "$key" != "$repo#$n" ] || label="-"
      printf '  %s%-10s%s %-36s %s\n' "$C_BOLD$C_CYAN" "$label" "$C_RESET" "${repo#*/}#$n" "$(status_of "$repo#$n")"
      printf '  %-10s %s%s%s\n' "" "$C_DIM" "$(truncate "${title#"$label "}" 50)" "$C_RESET"
    done < "$STATE/requests.tsv"
  fi
  printf '\n  %sEnter 바로 확인 · Ctrl+C 종료%s\n' "$C_DIM" "$C_RESET"
}

rename_tab "$TAB_TITLE"
[ -t 1 ] && printf '\e[?25l'   # 대시보드라 입력 커서를 숨긴다. 끝날 때 되돌린다
log "시작 · ${INTERVAL}초 간격 · 세션 위치 $WORKTREE_SELECTOR"
while :; do
  [ -t 1 ] && printf '\r\e[2K  %s⏳ 확인 중…%s' "$C_YELLOW" "$C_RESET"
  check
  render
  if [ -t 0 ]; then
    read -rs -t "$INTERVAL" _ && log "수동 확인"
  else
    sleep "$INTERVAL"
  fi
done
