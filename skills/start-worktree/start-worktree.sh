#!/usr/bin/env bash
# start-worktree.sh
# Jira 이슈 하나를 worktree에서 착수한다. 유휴 worktree를 재사용하거나 새로 만들고,
# 브랜치를 끊고, 현재 claude 세션을 그 자리로 옮긴 뒤 원래 탭을 닫는다.
#
# 사용법: start-worktree.sh <JIRA-KEY> [옵션]
#   --base <ref>      base 브랜치를 직접 지정 (기본: 에픽의 feature-base, 없으면 develop)
#   --branch <name>   작업 브랜치 이름을 직접 지정
#   --new             유휴 worktree를 찾지 않고 새로 만든다
#   --no-move         세션을 옮기지 않는다 (자리만 준비)
#   --dry-run         파괴적 동작 없이 계획만 출력
set -euo pipefail

die() { echo "[오류] $*" >&2; exit 1; }
warn() { echo "[경고] $*" >&2; }
info() { echo "$*"; }

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

issue_key=""
opt_base=""
opt_branch=""
opt_new=0
opt_no_move=0
opt_dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) opt_base="${2:-}"; shift 2 ;;
    --branch) opt_branch="${2:-}"; shift 2 ;;
    --new) opt_new=1; shift ;;
    --no-move) opt_no_move=1; shift ;;
    --dry-run) opt_dry_run=1; shift ;;
    -*) die "알 수 없는 옵션: $1" ;;
    *) issue_key="$1"; shift ;;
  esac
done

[ -n "$issue_key" ] || die "Jira 키가 필요합니다. 사용법: start-worktree.sh <JIRA-KEY>"
[ -n "$opt_base" ] || die "base 브랜치가 필요합니다. SKILL.md가 --base로 넘깁니다."
[ -n "$opt_branch" ] || die "작업 브랜치 이름이 필요합니다. SKILL.md가 --branch로 넘깁니다."
base_ref="$opt_base"
work_branch="$opt_branch"
