#!/usr/bin/env bash
# 새 worktree에 서브모듈과 .claude/ 환경을 초기화한다.
#
# 동작:
#   1. 서브모듈 초기화 (메인 worktree에 .gitmodules 있을 때만)
#   2. <worktree>/.claude/ 디렉토리 생성
#   3. 메인의 .claude/rules/ 항목 복제
#      - symlink: readlink로 타깃을 읽어 동일 타깃 symlink 생성
#      - 일반 파일/디렉토리: cp -R
#      - 같은 이름이 이미 있으면 skip (덮어쓰기 금지)
#      - 생성 후 target 부재면 broken link 경고
#   4. <worktree>/.claude/plans/ 빈 디렉토리 생성 (메인 plan은 가져오지 않음)
#   5. 메인의 .claude/settings.local.json 복사 (worktree에 없을 때만)
#
# Idempotent: 같은 worktree 경로에 재실행해도 기존 항목을 덮어쓰지 않는다.
# 서브모듈 초기화가 실패해도 .claude/ 초기화는 계속 진행한다.
#
# 사용:
#   ~/.claude/skills/create-worktree/init.sh <worktree-path>
#
# create-worktree skill의 `## 실행 > 2. 서브모듈/.claude 초기화` 단계에서 호출된다.
set -euo pipefail

WORKTREE_PATH="${1:-}"

if [ -z "$WORKTREE_PATH" ]; then
  echo "Error: worktree 경로가 필요합니다." >&2
  echo "  Usage: $0 <worktree-path>" >&2
  exit 1
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "Error: '$WORKTREE_PATH'는 존재하지 않거나 디렉토리가 아닙니다." >&2
  exit 1
fi

WORKTREE_PATH="$(cd "$WORKTREE_PATH" && pwd)"

if ! git -C "$WORKTREE_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: '$WORKTREE_PATH'는 git 작업 트리가 아닙니다." >&2
  exit 1
fi

# 메인 worktree 경로 결정: git-common-dir의 부모
GIT_COMMON_DIR="$(git -C "$WORKTREE_PATH" rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) ;;
  *)  GIT_COMMON_DIR="$WORKTREE_PATH/$GIT_COMMON_DIR" ;;
esac
GIT_COMMON_DIR="$(cd "$GIT_COMMON_DIR" && pwd)"
MAIN_WORKTREE="$(dirname "$GIT_COMMON_DIR")"

if [ "$MAIN_WORKTREE" = "$WORKTREE_PATH" ]; then
  echo "Error: '$WORKTREE_PATH'는 메인 worktree입니다. 새 worktree 경로를 지정해 주세요." >&2
  exit 1
fi

echo "=== worktree 초기화 ==="
echo "메인:  $MAIN_WORKTREE"
echo "신규:  $WORKTREE_PATH"
echo ""

# ─── 1. 서브모듈 초기화 ────────────────────────────────────
SUBMODULE_RESULT="skip (.gitmodules 없음)"
if [ -f "$MAIN_WORKTREE/.gitmodules" ]; then
  echo "[1/5] 서브모듈 초기화..."
  if git -C "$WORKTREE_PATH" submodule update --init --recursive; then
    SUBMODULE_RESULT="완료"
  else
    SUBMODULE_RESULT="실패 (수동 재시도 필요)"
    echo "  ⚠ 서브모듈 초기화 실패. .claude/ 초기화는 계속 진행합니다." >&2
    echo "  수동 재시도: cd $WORKTREE_PATH && git submodule update --init --recursive" >&2
  fi
else
  echo "[1/5] 서브모듈: .gitmodules 없음, skip"
fi
echo ""

# ─── 2. .claude/ 디렉토리 ──────────────────────────────────
CLAUDE_DIR="$WORKTREE_PATH/.claude"
if [ -d "$CLAUDE_DIR" ]; then
  CLAUDE_DIR_RESULT="이미 존재 (skip)"
else
  mkdir -p "$CLAUDE_DIR"
  CLAUDE_DIR_RESULT="생성"
fi
echo "[2/5] .claude/: $CLAUDE_DIR_RESULT"

# ─── 3. .claude/rules/ ─────────────────────────────────────
MAIN_RULES="$MAIN_WORKTREE/.claude/rules"
WORKTREE_RULES="$CLAUDE_DIR/rules"
RULES_COPIED=()
RULES_SKIPPED=()
RULES_BROKEN=()

if [ -d "$MAIN_RULES" ]; then
  echo "[3/5] .claude/rules/ 복제..."
  mkdir -p "$WORKTREE_RULES"
  for entry in "$MAIN_RULES"/* "$MAIN_RULES"/.[!.]*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    name="$(basename "$entry")"
    dest="$WORKTREE_RULES/$name"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
      RULES_SKIPPED+=("$name")
      continue
    fi

    if [ -L "$entry" ]; then
      target="$(readlink "$entry")"
      ln -s "$target" "$dest"
      if [ ! -e "$dest" ]; then
        RULES_BROKEN+=("$name -> $target")
      fi
      RULES_COPIED+=("$name (symlink → $target)")
    else
      cp -R "$entry" "$dest"
      RULES_COPIED+=("$name")
    fi
  done
  echo "  복제 ${#RULES_COPIED[@]}개 / skip ${#RULES_SKIPPED[@]}개 / broken ${#RULES_BROKEN[@]}개"
else
  echo "[3/5] .claude/rules/: 메인에 없음, skip"
fi

# ─── 4. .claude/plans/ ─────────────────────────────────────
WORKTREE_PLANS="$CLAUDE_DIR/plans"
if [ -d "$WORKTREE_PLANS" ]; then
  PLANS_RESULT="이미 존재 (skip)"
else
  mkdir -p "$WORKTREE_PLANS"
  PLANS_RESULT="생성"
fi
echo "[4/5] .claude/plans/: $PLANS_RESULT"

# ─── 5. .claude/settings.local.json ────────────────────────
MAIN_SETTINGS="$MAIN_WORKTREE/.claude/settings.local.json"
WORKTREE_SETTINGS="$CLAUDE_DIR/settings.local.json"
SETTINGS_WARN=""

if [ -f "$MAIN_SETTINGS" ]; then
  if [ -e "$WORKTREE_SETTINGS" ]; then
    SETTINGS_RESULT="이미 존재 (skip)"
    SETTINGS_WARN=" — 메인의 settings.local.json과 다를 수 있음"
  else
    cp "$MAIN_SETTINGS" "$WORKTREE_SETTINGS"
    SETTINGS_RESULT="복사"
  fi
else
  SETTINGS_RESULT="메인에 없음, skip"
fi
echo "[5/5] settings.local.json: $SETTINGS_RESULT"
echo ""

# ─── 결과 요약 ─────────────────────────────────────────────
echo "=== 결과 요약 ==="
echo "서브모듈:            $SUBMODULE_RESULT"
echo ".claude/:            $CLAUDE_DIR_RESULT"
echo ".claude/plans/:      $PLANS_RESULT"
echo ".claude/settings:    $SETTINGS_RESULT${SETTINGS_WARN}"

if [ ${#RULES_COPIED[@]} -gt 0 ]; then
  echo ""
  echo "복제된 rules (${#RULES_COPIED[@]}):"
  for item in "${RULES_COPIED[@]}"; do
    echo "  + $item"
  done
fi

if [ ${#RULES_SKIPPED[@]} -gt 0 ]; then
  echo ""
  echo "skip된 rules — 이미 존재 (${#RULES_SKIPPED[@]}):"
  for item in "${RULES_SKIPPED[@]}"; do
    echo "  · $item"
  done
fi

if [ ${#RULES_BROKEN[@]} -gt 0 ]; then
  echo ""
  echo "⚠ broken symlink — target 부재 (${#RULES_BROKEN[@]}):"
  for item in "${RULES_BROKEN[@]}"; do
    echo "  ! $item"
  done
fi

echo ""
echo "다음: cd $WORKTREE_PATH"
