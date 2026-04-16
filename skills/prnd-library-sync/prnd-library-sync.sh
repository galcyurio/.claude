#!/usr/bin/env bash
# prnd-library-sync.sh
# 사용법: prnd-library-sync.sh <branch> <command> <절대경로1> [절대경로2] ...
# 프로젝트 경로는 AI가 절대경로로 변환해서 전달한다

set -euo pipefail

if [ $# -lt 3 ]; then
  echo "사용법: $0 <branch> <command> <절대경로1> [절대경로2] ..." >&2
  exit 1
fi

BRANCH="$1"
CMD="$2"
shift 2

FAILED=0

for PROJECT in "$@"; do
  LIB_DIR="$PROJECT/prnd-library"

  echo ""
  echo "=========================================="
  echo "프로젝트: $PROJECT"
  echo "경로: $LIB_DIR"
  echo "=========================================="

  if [ ! -d "$LIB_DIR" ]; then
    echo "[오류] 디렉토리가 존재하지 않음: $LIB_DIR"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "[1/3] git fetch"
  if ! git -C "$LIB_DIR" fetch; then
    echo "[오류] git fetch 실패: $PROJECT"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "[2/3] 브랜치 존재 확인: $BRANCH"
  if ! git -C "$LIB_DIR" rev-parse --verify "refs/remotes/origin/$BRANCH" > /dev/null 2>&1 && \
     ! git -C "$LIB_DIR" rev-parse --verify "refs/heads/$BRANCH" > /dev/null 2>&1; then
    echo "[오류] 브랜치가 존재하지 않음: $BRANCH ($PROJECT)"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "[3/3] git checkout $BRANCH"
  if ! git -C "$LIB_DIR" checkout "$BRANCH"; then
    echo "[오류] git checkout 실패: $PROJECT"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "[4/4] $CMD"
  if ! (cd "$PROJECT" && eval "$CMD"); then
    echo "[오류] 명령어 실패: $PROJECT"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "[완료] $PROJECT"
done

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "결과: ${FAILED}개 프로젝트 실패"
  exit 1
else
  echo "결과: 모든 프로젝트 성공"
fi
