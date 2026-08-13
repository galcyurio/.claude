#!/usr/bin/env bash
# prnd-library 서브모듈 포인터를 손으로 바꾸는 Bash 명령을 차단하고
# update-git-submodule 스킬로 유도한다.
#
# 스킬 스크립트는 문제의 git 명령을 자기 내부에서 실행하므로
# Bash 도구 호출로 노출되지 않는다. 따라서 이 훅이 스킬 자신을 막지 않는다.
set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || printf '')

[ -z "$cmd" ] && exit 0

REASON='prnd-library 서브모듈 포인터를 손으로 바꾸지 않는다. update-git-submodule 스킬을 사용하라 — Skill(update-git-submodule, args: "release/... 또는 feature/... 브랜치명"). 이 스킬이 .gitmodules의 branch 필드와 서브모듈 포인터를 한 커밋으로 함께 처리한다. 손으로 하면 .gitmodules 갱신이 빠진다.'

deny() {
  jq -n --arg reason "$REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# 스킬 경로와 worktree 초기화는 통과
case "$cmd" in
  *update-git-submodule.sh*|*create-worktree/init.sh*) exit 0 ;;
esac

# 1. .gitmodules의 추적 브랜치를 바꾸는 명령
printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+submodule[[:space:]]+set-branch' && deny

# 2. 서브모듈을 원격 tip으로 옮기는 명령 (--remote 없는 update는 기록된 포인터 복원이라 허용)
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+submodule[[:space:]]+update' \
  && printf '%s' "$cmd" | grep -Fq -- '--remote'; then
  deny
fi

# 3. 서브모듈 안에서 직접 checkout/switch
#    단, 새 브랜치 생성(-b/-B/-c)은 현재 커밋에 이름을 붙이는 것이라
#    포인터를 원격 tip으로 옮기지 않으므로 통과시킨다.
if printf '%s' "$cmd" | grep -Fq 'prnd-library' \
  && printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+([^|;&]*[[:space:]])?(checkout|switch)[[:space:]]' \
  && ! printf '%s' "$cmd" | grep -Eq '(checkout|switch)[[:space:]]+(-[bBc])[[:space:]]'; then
  deny
fi

# 4. 서브모듈 포인터 스테이징
printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+add[[:space:]][^|;&]*prnd-library' && deny

exit 0
