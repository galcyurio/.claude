#!/usr/bin/env bash
# 새 worktree에 서브모듈, .claude/, .agent/ 환경을 초기화한다.
#
# 동작:
#   1. 서브모듈 초기화 (메인 worktree에 .gitmodules 있을 때만)
#   2. <worktree>/.claude → 메인의 .claude/ symlink 생성
#      - 메인에 .claude/가 없으면 먼저 생성
#      - worktree에 이미 .claude가 있으면 skip (symlink면 target 출력, 일반 디렉토리면 그대로 둔다)
#      - rules·settings.local.json 등 .claude/ 전체를 메인과 공유하기 위함
#   3. <worktree>/.agent → 메인의 .agent/ symlink 생성
#      - 메인에 .agent/가 없으면 .agent/specs/, .agent/plans/까지 함께 생성
#      - worktree에 이미 .agent가 있으면 skip
#      - spec/plan을 모든 worktree에서 공유하기 위함
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
  echo "[1/3] 서브모듈 초기화..."
  if git -C "$WORKTREE_PATH" submodule update --init --recursive; then
    SUBMODULE_RESULT="완료"
  else
    SUBMODULE_RESULT="실패 (수동 재시도 필요)"
    echo "  ⚠ 서브모듈 초기화 실패. .claude/ 초기화는 계속 진행합니다." >&2
    echo "  수동 재시도: cd $WORKTREE_PATH && git submodule update --init --recursive" >&2
  fi
else
  echo "[1/3] 서브모듈: .gitmodules 없음, skip"
fi
echo ""

# ─── 2. .claude/ symlink ───────────────────────────────────
MAIN_CLAUDE="$MAIN_WORKTREE/.claude"
WORKTREE_CLAUDE="$WORKTREE_PATH/.claude"

if [ -L "$WORKTREE_CLAUDE" ]; then
  CLAUDE_TARGET="$(readlink "$WORKTREE_CLAUDE")"
  if [ ! -e "$WORKTREE_CLAUDE" ]; then
    CLAUDE_RESULT="이미 존재 (broken symlink → $CLAUDE_TARGET)"
  else
    CLAUDE_RESULT="이미 존재 (symlink → $CLAUDE_TARGET)"
  fi
elif [ -e "$WORKTREE_CLAUDE" ]; then
  CLAUDE_RESULT="이미 존재 (skip, symlink 아님)"
else
  if [ ! -d "$MAIN_CLAUDE" ]; then
    mkdir -p "$MAIN_CLAUDE"
    ln -s "$MAIN_CLAUDE" "$WORKTREE_CLAUDE"
    CLAUDE_RESULT="symlink 생성 (메인 .claude/ 신규 생성 포함) → $MAIN_CLAUDE"
  else
    ln -s "$MAIN_CLAUDE" "$WORKTREE_CLAUDE"
    CLAUDE_RESULT="symlink 생성 → $MAIN_CLAUDE"
  fi
fi
echo "[2/3] .claude/: $CLAUDE_RESULT"
echo ""

# ─── 3. .agent/ symlink ────────────────────────────────────
MAIN_AGENT="$MAIN_WORKTREE/.agent"
WORKTREE_AGENT="$WORKTREE_PATH/.agent"

if [ -L "$WORKTREE_AGENT" ]; then
  AGENT_TARGET="$(readlink "$WORKTREE_AGENT")"
  if [ ! -e "$WORKTREE_AGENT" ]; then
    AGENT_RESULT="이미 존재 (broken symlink → $AGENT_TARGET)"
  else
    AGENT_RESULT="이미 존재 (symlink → $AGENT_TARGET)"
  fi
elif [ -e "$WORKTREE_AGENT" ]; then
  AGENT_RESULT="이미 존재 (skip, symlink 아님)"
else
  if [ ! -d "$MAIN_AGENT" ]; then
    mkdir -p "$MAIN_AGENT/specs" "$MAIN_AGENT/plans"
    ln -s "$MAIN_AGENT" "$WORKTREE_AGENT"
    AGENT_RESULT="symlink 생성 (메인 .agent/ 신규 생성 포함) → $MAIN_AGENT"
  else
    ln -s "$MAIN_AGENT" "$WORKTREE_AGENT"
    AGENT_RESULT="symlink 생성 → $MAIN_AGENT"
  fi
fi
echo "[3/3] .agent/: $AGENT_RESULT"
echo ""

# ─── 결과 요약 ─────────────────────────────────────────────
echo "=== 결과 요약 ==="
echo "서브모듈:            $SUBMODULE_RESULT"
echo ".claude/:            $CLAUDE_RESULT"
echo ".agent/:             $AGENT_RESULT"

echo ""
echo "다음: cd $WORKTREE_PATH"
