#!/usr/bin/env bash
# gstack submodule을 /gstack-upgrade 호환 모드로 준비한다.
#
# /gstack-upgrade는 install type detection에서 .git을 디렉토리로 검사([ -d ".git" ]).
# submodule은 .git이 gitfile(file)이라 그 가지를 통과 못 하고 vendored 분기로 빠진다.
# vendored 분기는 mv로 디렉토리를 옮겨 submodule을 깨뜨린다.
#
# 해법: gitfile을 .git/modules/skills/gstack/로 가는 symlink로 변환.
# [ -d ]는 symlink follow하므로 directory로 인식 → global-git 분기 (git fetch + reset --hard) 진입.
# git submodule status 등 부모 repo 동작은 영향 없다.
#
# 새 머신: git clone --recurse-submodules 후 1회 실행하면 영구 적용된다.
set -euo pipefail

GSTACK_DIR="$HOME/.claude/skills/gstack"
GIT_PATH="$GSTACK_DIR/.git"
GITDIR_REL="../../.git/modules/skills/gstack"
GITDIR_ABS="$HOME/.claude/.git/modules/skills/gstack"

[ -d "$GITDIR_ABS" ] || {
  echo "Error: $GITDIR_ABS not found." >&2
  echo "  -> 'git submodule update --init --recursive'을 먼저 실행하세요." >&2
  exit 1
}

if [ -L "$GIT_PATH" ]; then
  echo "OK: 이미 symlink — 변환 불필요"
  exit 0
fi

if [ -f "$GIT_PATH" ]; then
  rm "$GIT_PATH"
  ln -s "$GITDIR_REL" "$GIT_PATH"
  echo "변환: $GIT_PATH -> $GITDIR_REL"
  echo "/gstack-upgrade가 이제 global-git 분기로 정상 동작합니다."
  exit 0
fi

echo "Error: $GIT_PATH가 file도 symlink도 아님" >&2
exit 1
