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

# base 기준으로 재사용 가능한 worktree 경로를 고른다.
# 조건: 메인이 아니고, 브랜치가 <base> 또는 <base>-<접미사>, upstream이 origin/<base>,
#       미커밋 변경 없음. 후보가 여럿이면 가장 오래 손대지 않은 것을 고른다.
#
# 메인 제외가 핵심이다. heydealer-android와 revolt-android 같은 메인 worktree도
# develop을 물고 upstream이 origin/develop이며 대개 깨끗해서, 이 조건이 없으면
# 메인이 후보로 잡혀 그 위에 작업 브랜치가 만들어진다(spec 3절).
find_idle_worktree() {
  local base="$1" main_wt best="" best_ts="" wt br up ts
  main_wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    [ "$wt" != "$main_wt" ] || continue
    br="$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ -n "$br" ] || continue
    case "$br" in "$base"|"$base"-*) ;; *) continue ;; esac
    up="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    [ "$up" = "origin/$base" ] || continue
    [ -z "$(git -C "$wt" status --porcelain --untracked-files=no --ignore-submodules=all)" ] || continue
    # 마지막 커밋 시각은 같은 브랜치를 문 worktree끼리 동일해 변별력이 없다.
    # 디렉토리 mtime은 빌드 산출물 때문에 실제 사용 시점을 따라간다.
    ts="$(stat -f %m "$wt" 2>/dev/null || echo 0)"
    if [ -z "$best" ] || [ "$ts" -lt "$best_ts" ]; then best="$wt"; best_ts="$ts"; fi
  done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')
  printf '%s' "$best"
}

target_worktree=""
if [ "$opt_new" = 0 ]; then
  target_worktree="$(find_idle_worktree "$base_ref")"
fi

if [ -n "$target_worktree" ]; then
  pick_reason="유휴 worktree를 재사용했다"
  info "[1/3] 유휴 worktree 재사용: $target_worktree ($(git -C "$target_worktree" symbolic-ref --short HEAD))"
  if [ "$opt_dry_run" = 0 ]; then
    git -C "$target_worktree" fetch origin "$base_ref"
    git -C "$target_worktree" pull --ff-only \
      || die "유휴 브랜치가 원격과 갈라졌습니다. 강제로 맞추지 않고 중단합니다."
    git -C "$target_worktree" checkout -b "$work_branch"
  fi
else
  if [ "$opt_new" = 1 ]; then
    pick_reason="--new 지시에 따라 새로 만들었다"
  else
    pick_reason="재사용할 자리가 없어 새로 만들었다"
  fi
  info "[1/3] 재사용할 자리가 없어 새로 만듭니다 (base: $base_ref)"
  if [ "$opt_dry_run" = 1 ]; then
    info "[dry-run] 새 worktree를 만들 자리까지만 확인했습니다. 이후 단계는 실제 경로가 있어야 진행합니다."
    exit 0
  fi
  repo_root="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  target_worktree="$("$ORCA" worktree create --repo "path:$repo_root" \
    --name "$work_branch" --base-branch "$base_ref" --json \
    | python3 -c 'import json,sys; print((json.load(sys.stdin).get("result") or {}).get("worktree",{}).get("path",""))')"
  [ -n "$target_worktree" ] || die "orca worktree create가 경로를 돌려주지 않았습니다."
  bash "$(dirname "$0")/init.sh" "$target_worktree"
fi
