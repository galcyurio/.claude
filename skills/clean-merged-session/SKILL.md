---
name: clean-merged-session
effort: low
description: PR이 원격에서 머지된 뒤 남은 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 브랜치로 되돌린 다음, orca 워크스페이스 카드를 Todo로 되돌리고 작업 탭을 닫아 세션을 마감하는 스킬. 사용자가 'clean-merged-session', '머지된 브랜치 정리', '브랜치 정리해줘', '브랜치 지우고 base로 돌아가', 'PR 머지됐어 정리해줘', '작업 브랜치 삭제', '머지 끝났으니 정리', '로컬 브랜치 청소', '세션 정리', '작업 끝났으니 정리하고 탭 닫아' 등을 요청할 때 이 스킬을 사용해야 한다. worktree 디렉토리 자체를 없애는 요청에는 `remove-worktree`를 사용한다 — 이 스킬은 worktree를 유지한 채 브랜치만 정리한다.
argument-hint: "[branch-name]"
allowed-tools: Bash
---

## 역할

머지가 끝난 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 사본으로 되돌린 뒤, Orca 카드를 Todo로 되돌리고 작업 탭을 닫는다. 현재 브랜치가 이미 base(`develop`·`feature-base/*` 등)면 삭제할 작업 브랜치가 없으므로 **최신화 전용 모드**로 돌아 base를 원격 최신으로 맞추고 세션만 마감한다. 판정과 실행은 전부 스크립트가 한다. 이 스킬이 하는 일은 사용자 발화를 플래그로 옮기고, 스크립트가 중단했을 때 그 이유를 사용자에게 전달하는 것뿐이다.

사용자 입력: $ARGUMENTS

## 입력을 플래그로 옮긴다

| 사용자 발화 | 플래그 |
|---|---|
| 브랜치 이름을 지정 | 첫 인자 (생략하면 현재 브랜치) |
| "base는 X야" | `--base X` |
| "변경사항은 stash하고 정리해" | `--stash` |
| "커밋 날아가도 좋으니 지워" | `--force-delete` |
| "머지된 브랜치 다 지워" | `--sweep` |
| "결과 보고 먼저 보고 싶어", "탭은 두고" | `--no-close` |

**플래그를 추정해서 붙이지 않는다.** `--stash`, `--force-delete`, `--sweep`은 사용자가 그 뜻으로 말했을 때만 붙이고, 판단이 필요하면 `AskUserQuestion`으로 묻는다.

## 실행

worktree 루트에서 아래 한 줄을 Bash 도구로 실행한다.

```
${CLAUDE_SKILL_DIR}/clean-merged-session.sh [<branch>] [플래그]
```

스크립트가 수행하는 일:

1. 대상 브랜치 확정 (detached HEAD·미존재는 중단). 보호 브랜치는 **인자로 지정했을 때만** 중단하고, 현재 브랜치가 보호 브랜치면 최신화 전용 모드로 전환한다
2. `gh pr list --state merged`로 머지 확인, `baseRefName`으로 base 판별
3. worktree 디렉토리 접미사에 맞는 base 사본 선택 (`develop` → `develop-3`), 다른 worktree 점유 확인
4. working tree 검사 → `git fetch --prune` → base 사본으로 `git switch`(이미 그 브랜치면 생략) → `git pull --ff-only` → `git submodule update`
5. `git branch -d` (기본), 남은 머지 브랜치 목록 보고 또는 스윕 삭제. 최신화 전용 모드에서는 삭제를 건너뛴다
6. `orca worktree set --workspace-status todo` → `orca terminal close --tab`

접미사 매칭 예시:

| 현재 worktree | PR base | 전환할 base 사본 |
|---|---|---|
| `heydealer-android-3` | `feature-base/HDA-22279-...` | `feature-base/HDA-22279-...-3` |
| `heydealer-android` (메인) | `develop` | `develop` |
| `heydealer-android-2` | `develop` | `develop-2` (없으면 `develop`) |

## 스크립트가 중단했을 때 (exit 1)

중단하면 카드 상태와 탭은 그대로 남는다. 스크립트 출력을 그대로 사용자에게 전달하고, 아래 판단을 **사용자에게 넘긴다**.

| 중단 이유 | 다음 행동 |
|---|---|
| 머지된 PR 없음 | 머지 여부를 사용자가 확인한다. base를 알려주면 `--base`로 재실행. **base를 추정하지 않는다.** |
| working tree가 깨끗하지 않음 | 커밋할지 stash할지 사용자가 고른다. |
| 인자로 지정한 브랜치가 보호 브랜치 | 지울 대상이 맞는지 사용자가 확인한다. 인자 없이 실행하면 최신화 전용 모드로 돈다. |
| `git branch -d` 거부 | 거부 메시지를 그대로 보여준다. `--force-delete`는 명시 요청 전용. |
| base 사본을 못 찾음 | 스크립트가 출력한 후보 목록을 보여주고 사용자가 고르게 한다. **사본을 새로 만들지 않는다.** |
| 다른 worktree가 점유 | 그 worktree 경로를 보고하고 끝낸다. |

## 주의

- **스크립트를 우회해 git 명령을 직접 실행하지 않는다.** 가드레일이 스크립트 안에 있다.
- **성공 경로에서는 보고할 기회가 없다.** 탭이 닫히는 순간 이 세션이 끝나므로 스크립트 뒤에 아무것도 출력할 수 없다. 결과를 보여줘야 하는 상황이면 `--no-close`로 실행하고, 탭은 사용자가 닫도록 안내한다.
- **절전(sleep) 전환은 orca CLI에 명령이 없어 범위 밖이다.** 필요하면 사용자가 사이드바에서 직접 절전한다.
- **범위 밖은 손대지 않는다**: worktree 제거(`remove-worktree`), develop 반영(`merge-develop`), 서브모듈 포인터 변경(`update-git-submodule`), 무관한 stash 정리, reflog에 떠 있는 버려진 커밋 복구. 발견하면 보고만 한다.
