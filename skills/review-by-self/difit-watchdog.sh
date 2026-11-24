#!/usr/bin/env bash
# difit 지킴이: 세션이 끝나면 우리가 띄운 difit 서버를 대신 종료한다.
#
# 사용: nohup bash difit-watchdog.sh <port> <difit-pid> <claude-pid> >/dev/null 2>&1 &
#
# 종료 조건 (먼저 오는 쪽)
# - claude 프로세스가 사라짐: 터미널 탭을 닫거나 세션이 끝난 경우
# - Orca Chat 탭이 닫힘: Orca 봇 Chat은 탭을 닫아도 claude 프로세스가 남는다.
#   대신 Orca의 열린 탭 목록(agent_session_tabs)에서 그 Chat의 세션 ID(ORCA_AGENT_SESSION_ID)가 빠지므로 이것을 본다.
# difit가 먼저 사라지면 아무것도 하지 않고 물러난다.

PORT=$1
DIFIT_PID=$2
CLAUDE_PID=$3
SESSION_ID=${ORCA_AGENT_SESSION_ID:-}
INTERVAL=2.5      # 연속 2회 확인과 합쳐 Chat을 닫은 뒤 5초 안에 정리한다
CHAT_MISS_LIMIT=2 # 일시적인 조회 누락으로 죽이지 않도록 연속 2회 빠졌을 때만 닫힌 것으로 본다

[ -n "$PORT" ] && [ -n "$DIFIT_PID" ] && [ -n "$CLAUDE_PID" ] || exit 2

# Orca 봇 Chat(structured session)에서 띄운 경우에만 Chat 탭을 감시한다.
TABS_DB="${ORCA_USER_DATA_PATH:-$HOME/Library/Application Support/orca}/agent-session-domain.db"
watch_chat=0
if [ "${ORCA_STRUCTURED_SESSION:-}" = "1" ] && [[ "$SESSION_ID" =~ ^[0-9a-f-]+$ ]] && [ -f "$TABS_DB" ] && command -v sqlite3 >/dev/null 2>&1; then
  watch_chat=1
fi

# 0: 열려 있음, 1: 탭 없음, 2: 조회 실패(판단 보류)
# `orca agent list`는 탭을 닫아도 실행 중인 Chat을 계속 보여 주므로 쓰지 않는다.
# 열린 Chat 탭은 Orca의 agent_session_tabs 테이블에만 남는다(2026-11-24 실측).
chat_state() {
  local n
  n=$(sqlite3 -readonly "$TABS_DB" \
    "select count(*) from agent_session_tabs where session_id = '$SESSION_ID'" 2>/dev/null) || return 2
  case $n in
    0) return 1 ;;
    ''|*[!0-9]*) return 2 ;;
    *) return 0 ;;
  esac
}

misses=0
while kill -0 "$DIFIT_PID" 2>/dev/null; do
  kill -0 "$CLAUDE_PID" 2>/dev/null || break
  if [ "$watch_chat" = 1 ]; then
    chat_state
    case $? in
      0) misses=0 ;;
      1) misses=$((misses + 1)); [ "$misses" -ge "$CHAT_MISS_LIMIT" ] && break ;;
    esac
  fi
  sleep "$INTERVAL"
done

# pid와 포트가 모두 일치할 때만 죽인다. difit가 먼저 끝나 pid가 재사용된 경우를 막는다.
P=$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null)
[ "$P" = "$DIFIT_PID" ] && kill "$P"
exit 0
