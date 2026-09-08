#!/usr/bin/env bash
# start-worktree.sh
# Jira 이슈 하나를 worktree에서 착수한다. 유휴 worktree를 재사용하거나 새로 만들고,
# 브랜치를 끊고, 현재 claude 세션을 그 자리로 옮긴 뒤 원래 탭을 닫는다.
#
# 사용법: start-worktree.sh <JIRA-KEY> [옵션]
#   --base <ref>      작업 브랜치를 끊을 지점 (기본: 에픽의 feature-base, 없으면 develop)
#   --pool <ref>      유휴 worktree를 찾는 기준 base (기본: --base 값)
#   --slot <접미사>   유휴 자리를 찾을 슬롯 계열 (기본: 숫자 접미사 슬롯만)
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
# 메인 worktree 옆에 <repo>-<이슈키>[-N] 형식으로 비어 있는 자리를 정한다.
# 이름만 보고 어떤 피처의 자리인지 알 수 있게 이슈키를 넣는다.
# release-worktree는 이름 끝의 -<한두자리 숫자>만 브랜치 접미사로 읽으므로,
# 이슈키의 숫자 부분(HDA-22644의 22644)과 섞이지 않는다.
next_worktree_path() {
  local key="$1" main_wt parent repo stem n
  main_wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  parent="$(dirname "$main_wt")"
  repo="$(basename "$main_wt")"
  stem="$parent/$repo-$key"
  if [ ! -e "$stem" ]; then printf '%s' "$stem"; return; fi
  n=2
  while [ -e "$stem-$n" ]; do n=$((n+1)); done
  printf '%s-%s' "$stem" "$n"
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

issue_key=""
opt_base=""
opt_pool=""
opt_slot=""
opt_branch=""
opt_new=0
opt_no_move=0
opt_dry_run=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base) opt_base="${2:-}"; shift 2 ;;
    --pool) opt_pool="${2:-}"; shift 2 ;;
    --slot) opt_slot="${2:-}"; shift 2 ;;
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
# 유휴 자리를 찾는 기준. 지정하지 않으면 분기 지점과 같다 — 에픽 base에서 그대로
# 끊는 통상적인 경우다.
pool_ref="${opt_pool:-$opt_base}"
slot_name="$opt_slot"
work_branch="$opt_branch"

# 풀 base 기준으로 재사용 가능한 worktree 경로를 고른다.
# 조건: 메인이 아니고, 브랜치가 <pool>-<접미사>, upstream이 origin/<pool>,
#       미커밋 변경 없음. 후보가 여럿이면 가장 오래 손대지 않은 것을 고른다.
#
# 여기서 쓰는 기준은 작업 브랜치를 끊을 지점(--base)이 아니라 그 자리가 속한 에픽
# base(--pool)다. 형제 이슈 브랜치 위에 얹으려고 --base를 그 브랜치로 지정하더라도
# 자리를 찾는 기준은 바뀌지 않아야 한다. 두 개념을 한 값으로 묶으면 에픽의 유휴
# 자리가 후보에서 빠져 매번 새 worktree가 생긴다.
#
# 메인 제외가 핵심이다. heydealer-android와 revolt-android 같은 메인 worktree도
# develop을 물고 upstream이 origin/develop이며 대개 깨끗해서, 이 조건이 없으면
# 메인이 후보로 잡혀 그 위에 작업 브랜치가 만들어진다(spec 3절).
#
# 접미사가 없는 <base> 자체도 같은 이유로 뺀다. 그 자리는 start-feature가 만든 상위
# base worktree여서, 재사용하면 에픽의 기준 자리가 작업 브랜치로 덮여 사라진다.
# 하위 작업용 자리는 <base>-2, <base>-3처럼 접미사를 달고 upstream만 origin/<base>를
# 가리키므로, 브랜치 이름의 접미사 유무로 상위와 하위가 갈린다.
#
# 접미사는 두 성격으로 갈리며 섞이면 안 된다. 숫자 접미사(develop-2, develop-3)는 어느
# 이슈나 받는 범용 슬롯이고, 이름 접미사(develop-AGP-10-migration)는 특정 에픽 전용으로
# 만들어 둔 슬롯이다. 두 번째 인자로 계열 이름을 받아 후보를 그 계열로 한정하며, 비어
# 있으면 범용 슬롯만 후보가 된다. 이 구분이 없으면 원격 feature-base가 없는 에픽에서
# 풀 base가 develop으로 내려가는 순간 두 성격이 한 후보군에 섞이고, 최종 선택이 디렉토리
# mtime 1초 차이에 좌우된다(2026-09-08 실측: 후보 4자리의 mtime이 2초 안에 몰려 있었다).
#
# 계열 안에서도 상위와 하위가 갈린다. develop-AGP-10-migration 자리는 그 계열의 상위 base
# worktree이므로 접미사 없는 <base> 자리와 똑같이 후보에서 빼고, develop-AGP-10-migration-2
# 처럼 숫자 사본을 문 자리만 받는다. 상위 자리를 작업 브랜치로 덮으면 그 계열의 기준
# 자리가 사라지고 release-worktree가 되돌아갈 사본도 없어진다.
find_idle_worktree() {
  local pool="$1" slot="${2:-}" main_wt best="" best_ts="" wt br up ts suffix
  main_wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    [ "$wt" != "$main_wt" ] || continue
    br="$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [ -n "$br" ] || continue
    case "$br" in "$pool"-*) ;; *) continue ;; esac
    suffix="${br#"$pool"-}"
    if [ -n "$slot" ]; then
      # 지목받은 계열의 숫자 사본만 받는다. 접미사가 계열 이름뿐인 자리는 상위 base다.
      case "$suffix" in
        "$slot"-[0-9]|"$slot"-[0-9][0-9]) ;;
        *) continue ;;
      esac
    else
      # 범용 슬롯만 받는다. 이름 접미사 자리는 지목받을 때만 쓴다.
      case "$suffix" in
        [0-9]|[0-9][0-9]) ;;
        *) continue ;;
      esac
    fi
    up="$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    [ "$up" = "origin/$pool" ] || continue
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
  target_worktree="$(find_idle_worktree "$pool_ref" "$slot_name")"
fi

if [ -n "$target_worktree" ]; then
  pick_reason="유휴 worktree를 재사용했다"
  info "[1/3] 유휴 worktree 재사용: $target_worktree ($(git -C "$target_worktree" symbolic-ref --short HEAD) -> $work_branch, base: $base_ref)"
  if [ "$opt_dry_run" = 0 ]; then
    if [ "$base_ref" = "$pool_ref" ]; then
      # 유휴 브랜치가 곧 분기 지점이므로, 그 브랜치를 최신화한 뒤 거기서 끊는다.
      git -C "$target_worktree" fetch origin "$base_ref"
      git -C "$target_worktree" pull --ff-only \
        || die "유휴 브랜치가 원격과 갈라졌습니다. 강제로 맞추지 않고 중단합니다."
      git -C "$target_worktree" checkout -b "$work_branch"
    else
      # 분기 지점이 유휴 브랜치와 다르다. 유휴 브랜치를 최신화할 이유가 없으므로
      # 그대로 두고 base의 원격 tip 커밋에서 끊는다. start-point로 커밋 id를 주면
      # 원격 ref를 붙이지 않으므로 upstream이 자동으로 걸리지 않는다(rules/git.md).
      git -C "$target_worktree" fetch origin "$base_ref" \
        || warn "원격에서 $base_ref 를 가져오지 못했습니다. 로컬 ref로 진행합니다."
      start_commit="$(git -C "$target_worktree" rev-parse --verify --quiet "refs/remotes/origin/$base_ref" || true)"
      [ -n "$start_commit" ] \
        || start_commit="$(git -C "$target_worktree" rev-parse --verify --quiet "refs/heads/$base_ref" || true)"
      [ -n "$start_commit" ] || die "base를 찾지 못했습니다: $base_ref"
      git -C "$target_worktree" checkout -b "$work_branch" "$start_commit"
    fi
  fi
else
  # 계열을 지목받았는데 그 안에 빈 자리가 없으면 새 자리를 만들지 않고 멈춘다. 새로
  # 만들면 이름이 <repo>-<이슈키>가 되어 지목받은 계열에서 벗어나므로, 계열을 넓힐지는
  # 사용자가 결정할 일이다.
  if [ -n "$slot_name" ] && [ "$opt_new" = 0 ]; then
    echo "[오류] $slot_name 계열에 유휴 자리가 없습니다 (풀 base: $pool_ref)." >&2
    echo "  계열 브랜치와 점유 상태:" >&2
    git branch --list "$pool_ref-$slot_name" "$pool_ref-$slot_name-*" >&2
    git worktree list >&2
    echo "  자리를 새로 만들려면 --new, 범용 슬롯을 쓰려면 --slot 없이 다시 실행하세요." >&2
    exit 1
  fi
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
  target_worktree="$(next_worktree_path "$issue_key")"
  info "  새 자리: $target_worktree"
  git worktree add -b "$work_branch" "$target_worktree" "$base_ref" \
    || die "worktree를 만들지 못했습니다: $target_worktree"
  bash "$(dirname "$0")/init.sh" "$target_worktree"
fi

if [ "$opt_no_move" = 1 ]; then
  info "--no-move 이므로 세션을 옮기지 않습니다. 자리: $target_worktree"
  exit 0
fi

sid="$(current_session_id)"
[ -n "$sid" ] || die "현재 세션 id를 찾지 못했습니다. --no-move로 자리만 준비할 수 있습니다."

# 원본은 계산하지 않고 찾는다. 세션의 cwd와 스크립트 실행 위치가 다를 수 있다.
src="$(session_file_path "$sid")"
dst_dir="$(session_project_dir "$target_worktree")"

info "[2/3] 세션 이사: $sid"
info "  ${src:-(찾지 못함)}"
info "  -> $dst_dir"
if [ "$opt_dry_run" = 1 ]; then
  info "[dry-run] 여기서 멈춥니다. 실제로는 jsonl을 복사하고 새 탭을 띄운 뒤 이 탭을 닫습니다."
  exit 0
fi

[ -n "$src" ] && [ -f "$src" ] || die "세션 파일을 찾지 못했습니다: $sid"
mkdir -p "$dst_dir"
cp "$src" "$dst_dir/"

wt_id="$(wait_orca_worktree "$target_worktree")" \
  || die "orca가 worktree를 인식하지 못했습니다: $target_worktree"

# 어느 자리를 골랐는지는 이 프롬프트로만 전달된다. 옛 탭의 stdout은 곧 닫혀 사라지고,
# jsonl 복사는 이 실행 도중에 일어나 이 스크립트의 출력이 새 세션에 실리지 않는다(spec 4.2-4).
first_prompt="$issue_key 작업을 이어서 시작한다. 작업 자리는 $target_worktree ($work_branch, base $base_ref)이고 $pick_reason."

"$ORCA" terminal create --worktree "id:$wt_id" --title "$issue_key" \
  --command "claude --resume $sid \"$first_prompt\"" --json > /dev/null \
  || die "새 탭을 띄우지 못했습니다. 세션 파일은 이미 복사되어 있으니 그 worktree에서 직접 열 수 있습니다."
info "[3/3] 새 탭 기동 완료: $target_worktree"

handle="$(orca_terminal_handle)"
if [ -z "$handle" ]; then
  warn "터미널 핸들을 찾지 못해 이 탭은 직접 닫아 주세요."
  exit 0
fi
exec "$ORCA" terminal close --terminal "$handle" --tab --json
