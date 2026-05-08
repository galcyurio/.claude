#!/usr/bin/env bash
# gstack wrapper 디렉토리를 .gitignore의 마커 블록에 동기화한다.
# gstack-upgrade로 skill이 추가/제거되면 이 스크립트를 다시 돌려 .gitignore를 갱신한다.
set -euo pipefail

GSTACK_DIR="$HOME/.claude/skills/gstack"
GITIGNORE="$HOME/.claude/.gitignore"
BEGIN="# >>> gstack-wrappers (auto-generated) >>>"
END="# <<< gstack-wrappers <<<"

[ -d "$GSTACK_DIR" ] || { echo "Error: $GSTACK_DIR not found" >&2; exit 1; }
[ -f "$GITIGNORE" ] || { echo "Error: $GITIGNORE not found" >&2; exit 1; }

tmp=$(mktemp)
awk -v b="$BEGIN" -v e="$END" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  !skip
' "$GITIGNORE" > "$tmp"

cp "$tmp" "$GITIGNORE"
rm -f "$tmp"

[ -n "$(tail -c1 "$GITIGNORE" 2>/dev/null)" ] && echo "" >> "$GITIGNORE"
echo "$BEGIN" >> "$GITIGNORE"
for d in "$GSTACK_DIR"/*/; do
  name=$(basename "$d")
  [ -f "$d/SKILL.md" ] && echo "skills/$name/"
done | sort >> "$GITIGNORE"
echo "$END" >> "$GITIGNORE"

count=$(awk -v b="$BEGIN" -v e="$END" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  skip && /^skills\// { n++ }
  END { print n+0 }
' "$GITIGNORE")
echo "Synced $count gstack wrapper paths to $GITIGNORE"
