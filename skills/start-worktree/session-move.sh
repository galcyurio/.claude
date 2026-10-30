#!/usr/bin/env bash
# session-move.sh
# 현재 claude 세션을 다른 worktree로 옮기는 함수 모음. start-worktree.sh와
# move-worktree.sh가 source해서 쓴다. die·warn·info는 부르는 쪽이 정의한다.

# 경로를 Claude Code 프로젝트 저장소 이름으로 바꾼다.
# 경로 구분자와 점이 모두 '-'가 되며 역변환은 불가능하므로 정방향으로만 쓴다.
session_project_dir() {
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's|[/.]|-|g')"
}

# 현재 실행 중인 세션 id. Claude Code가 CLAUDE_CODE_SESSION_ID로 넘겨준다.
# cwd로 역추적하면 안 된다. 세션의 cwd와 스크립트 실행 위치는 다를 수 있다.
current_session_id() {
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then printf '%s' "$CLAUDE_CODE_SESSION_ID"; return; fi
  python3 - "${CLAUDE_PID:-}" <<'PY'
import glob, json, os, sys
pid = sys.argv[1]
out = ''
for f in glob.glob(os.path.expanduser('~/.claude/sessions/*.json')):
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if pid and str(d.get('pid')) == pid:
        out = d.get('sessionId', '')
        break
print(out)
PY
}

# 세션 jsonl의 실제 위치를 찾는다.
# 세션이 시작된 cwd 기준 저장소에 있고 /cd로 옮겨졌을 수도 있으므로,
# 경로를 계산하지 않고 저장소 전체에서 파일 이름으로 찾는다.
#
# 반드시 mtime이 가장 최근인 것을 골라야 한다. 이 설계는 이사할 때 파일을 옮기지 않고
# 복사하므로, 한 번이라도 이사한 세션은 같은 id의 jsonl을 두 곳 이상 갖는다.
# find의 -print -quit은 readdir 순서로 먼저 만난 것에서 멈춰 오래된 사본을 집는다.
session_file_path() {
  find "$HOME/.claude/projects" -maxdepth 2 -name "$1.jsonl" -exec stat -f '%m %N' {} + 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-
}

# git worktree add로 만든 자리를 orca가 인식할 때까지 기다렸다가 id를 낸다.
# repo 설정의 externalWorktreeVisibility가 show라 외부 생성분도 잡히지만 즉시는 아니다.
wait_orca_worktree() {
  local path="$1" i=0 id=""
  while [ "$i" -lt 20 ]; do
    id="$("$ORCA" worktree list --json 2>/dev/null | python3 -c '
import json, sys
p = sys.argv[1]
for w in (json.load(sys.stdin).get("result") or {}).get("worktrees") or []:
    if w.get("path") == p:
        print(w.get("id", "")); break
' "$path" 2>/dev/null || true)"
    if [ -n "$id" ]; then printf '%s' "$id"; return 0; fi
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}


# 현재 orca 터미널 핸들.
orca_terminal_handle() {
  if [ -n "${ORCA_TERMINAL_HANDLE:-}" ]; then printf '%s' "$ORCA_TERMINAL_HANDLE"; return; fi
  [ -n "${ORCA_TAB_ID:-}" ] || return 0
  "$ORCA" terminal list --worktree active --json 2>/dev/null | python3 -c '
import json, os, sys
tab = os.environ.get("ORCA_TAB_ID", "")
leaf = os.environ.get("ORCA_PANE_KEY", "").split(":")[-1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for t in (data.get("result") or {}).get("terminals") or []:
    if t.get("tabId") == tab and (not leaf or t.get("leafId") == leaf):
        print(t.get("handle", ""))
        break
' || true
}

ORCA="${ORCA_CLI_COMMAND:-orca}"

# 현재 세션을 대상 자리로 옮긴다. jsonl을 대상 자리의 프로젝트 저장소로 복사하고, 대상 자리에
# 새 탭을 띄워 첫 프롬프트와 함께 세션을 재개한 뒤 이 탭을 닫는다. 성공하면 돌아오지 않는다.
#
# 사용법: move_session <대상 자리> <탭 제목> <첫 프롬프트> [dry-run 0|1] [이사 단계 표기] [완료 단계 표기]
# 단계 표기는 부르는 스크립트의 진행 번호("[2/3]" 등)를 출력에 그대로 싣기 위한 값이다.
move_session() {
  local target="$1" title="$2" prompt="$3" dry_run="${4:-0}" step_move="${5:-}" step_done="${6:-}"
  local sid src dst_dir wt_id handle
  sid="$(current_session_id)"
  [ -n "$sid" ] || die "현재 세션 id를 찾지 못했습니다."

  # 원본은 계산하지 않고 찾는다. 세션의 cwd와 스크립트 실행 위치가 다를 수 있다.
  src="$(session_file_path "$sid")"
  dst_dir="$(session_project_dir "$target")"

  info "${step_move:+$step_move }세션 이사: $sid"
  info "  ${src:-(찾지 못함)}"
  info "  -> $dst_dir"
  if [ "$dry_run" = 1 ]; then
    info "[dry-run] 여기서 멈춥니다. 실제로는 jsonl을 복사하고 새 탭을 띄운 뒤 이 탭을 닫습니다."
    exit 0
  fi

  [ -n "$src" ] && [ -f "$src" ] || die "세션 파일을 찾지 못했습니다: $sid"
  mkdir -p "$dst_dir"
  cp "$src" "$dst_dir/"

  wt_id="$(wait_orca_worktree "$target")" \
    || die "orca가 worktree를 인식하지 못했습니다: $target"

  "$ORCA" terminal create --worktree "id:$wt_id" --title "$title" \
    --command "claude --resume $sid \"$prompt\"" --json > /dev/null \
    || die "새 탭을 띄우지 못했습니다. 세션 파일은 이미 복사되어 있으니 그 worktree에서 직접 열 수 있습니다."
  info "${step_done:+$step_done }새 탭 기동 완료: $target"

  handle="$(orca_terminal_handle)"
  if [ -z "$handle" ]; then
    warn "터미널 핸들을 찾지 못해 이 탭은 직접 닫아 주세요."
    exit 0
  fi
  exec "$ORCA" terminal close --terminal "$handle" --tab --json
}
