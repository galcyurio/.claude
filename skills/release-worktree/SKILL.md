---
name: release-worktree
effort: low
description: PR이 원격에서 머지된 뒤 남은 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 브랜치로 되돌린 다음, 이 worktree의 세션 이력을 메인 저장소로 회수하고 orca 워크스페이스 카드를 Todo로 되돌리고 작업 탭을 닫아 세션을 마감하는 스킬. 사용자가 'release-worktree', '자리 반납', '작업 끝났어 정리해줘', '머지된 브랜치 정리', '브랜치 정리해줘', '브랜치 지우고 base로 돌아가', 'PR 머지됐어 정리해줘', '작업 브랜치 삭제', '머지 끝났으니 정리', '로컬 브랜치 청소', '세션 정리', '작업 끝났으니 정리하고 탭 닫아' 등을 요청할 때 이 스킬을 사용해야 한다. worktree 디렉토리 자체를 없애는 요청에는 `remove-worktree`를 사용한다 — 이 스킬은 worktree를 유지한 채 브랜치만 정리한다.
argument-hint: "[branch-name]"
allowed-tools: Bash
---

## 역할

머지가 끝난 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 사본으로 되돌린 뒤, 이 worktree에 쌓인 세션 이력을 메인 저장소로 회수하고, Orca 카드를 Todo로 되돌리고 작업 탭을 닫는다. 현재 브랜치가 이미 base(`develop`·`feature-base/*` 등)면 삭제할 작업 브랜치가 없으므로 **최신화 전용 모드**로 돌아 base를 원격 최신으로 맞추고 세션만 마감한다. 판정과 실행은 전부 스크립트가 한다. 이 스킬이 하는 일은 사용자 발화를 플래그로 옮기고, 스크립트가 중단했을 때 그 이유를 사용자에게 전달하는 것뿐이다.

사용자 입력: $ARGUMENTS

## 입력을 플래그로 옮긴다

| 사용자 발화 | 플래그 |
|---|---|
| 브랜치 이름을 지정 | 첫 인자 (생략하면 현재 브랜치) |
| "base는 X야" | `--base X` |
| "PR 없어도 해제해", "머지 안 됐어도 비워", "force로 정리해" | `--force` |
| "변경사항은 stash하고 정리해" | `--stash` |
| "커밋 날아가도 좋으니 지워" | `--force-delete` |
| "머지된 브랜치 다 지워" | `--sweep` |
| "결과 보고 먼저 보고 싶어", "탭은 두고" | `--no-close` |

**플래그를 추정해서 붙이지 않는다.** `--force`, `--stash`, `--force-delete`, `--sweep`은 사용자가 그 뜻으로 말했을 때만 붙이고, 판단이 필요하면 `AskUserQuestion`으로 묻는다.

## 실행

worktree 루트에서 아래 한 줄을 Bash 도구로 실행한다.

```
${CLAUDE_SKILL_DIR}/release-worktree.sh [<branch>] [플래그]
```

스크립트가 수행하는 일:

1. 대상 브랜치 확정 (detached HEAD·미존재는 중단). 보호 브랜치는 **인자로 지정했을 때만** 중단하고, 현재 브랜치가 보호 브랜치면 최신화 전용 모드로 전환한다
2. `gh pr list --state merged`로 머지 확인, `baseRefName`으로 base 판별. `--force`면 머지 확인을 건너뛰고, base는 PR이 있으면 머지 상태와 무관하게 그 `baseRefName`을, PR이 아예 없으면 이 자리의 base 사본(`develop-AGP-10-migration-2` 등)에서 upstream을 거꾸로 읽어 얻는다. 사본 후보가 여럿이면 추정하지 않고 `--base`를 요구한다
3. worktree 디렉토리 접미사에 맞는 base 사본 선택 (`develop` → `develop-3`), 다른 worktree 점유 확인. 디렉토리 이름에서 저장소 이름을 뗀 나머지가 숫자가 아니면 그 이름을 계열로 보고 `<base>-<계열>`을 먼저 시도하므로, 이름 슬롯 자리는 `develop`이 아니라 자기 계열 사본으로 되돌아간다. 맞는 사본이 없으면 `origin/<base>`로 새로 만들고 upstream을 건다
4. working tree 검사 → `git fetch --prune` → base 사본으로 `git switch`(이미 그 브랜치면 생략) → `git pull --ff-only` → `git submodule update`
5. 이 worktree에 쌓인 세션 이력(`.claude/projects/`)을 메인 저장소로 회수 (`cp -n`, 기존 파일은 덮어쓰지 않음)
6. `git branch -d` (기본), 남은 머지 브랜치 목록 보고 또는 스윕 삭제. 최신화 전용 모드에서는 삭제를 건너뛴다
7. `orca worktree set --workspace-status todo` → `orca terminal close --tab`

접미사 매칭 예시:

| 현재 worktree | PR base | 전환할 base 사본 |
|---|---|---|
| `heydealer-android-3` | `feature-base/HDA-22279-...` | `feature-base/HDA-22279-...-3` |
| `heydealer-android` (메인) | `develop` | `develop` |
| `heydealer-android-2` | `develop` | `develop-2` (없으면 `develop`) |
| `heydealer-android-AGP-10-migration` | `develop` | `develop-AGP-10-migration` |
| `heydealer-android-AGP-10-migration-2` | `develop` | `develop-AGP-10-migration-2` |

## 스크립트가 중단했을 때 (exit 1)

중단하면 카드 상태와 탭은 그대로 남는다. 스크립트 출력을 그대로 사용자에게 전달하고, 아래 판단을 **사용자에게 넘긴다**.

| 중단 이유 | 다음 행동 |
|---|---|
| 머지된 PR 없음 | 머지 여부를 사용자가 확인한다. base를 알려주면 `--base`로 재실행. **base를 추정하지 않는다.** 사용자가 머지 여부와 무관하게 비우라고 하면 `--force`. |
| 추적 중인 파일에 미커밋 변경 | 커밋할지 stash할지 사용자가 고른다. `--force`면 태그를 붙여 stash로 치우고 진행한다. |
| 인자로 지정한 브랜치가 보호 브랜치 | 지울 대상이 맞는지 사용자가 확인한다. 인자 없이 실행하면 최신화 전용 모드로 돈다. |
| `git branch -d` 거부 | 거부 메시지를 그대로 보여준다. `--force-delete`와 `--force`는 명시 요청 전용. |
| base 사본 후보가 전부 다른 worktree에 점유됨 | 스크립트가 출력한 후보 목록을 보여주고 사용자가 고르게 한다. (맞는 이름의 사본이 아예 없으면 `origin/<base>`로 새로 만들고 진행하므로 중단하지 않는다.) |
| 다른 worktree가 점유 | 그 worktree 경로를 보고하고 끝낸다. |

## `--force`가 넘기지 못하는 것

`--force`가 넘기는 것은 네 가지다. 머지 확인, 추적 파일의 미커밋 변경, 서브모듈 되돌리기 실패, `git branch -d` 거부. 가운데 두 가지는 그냥 버리지 않고 흔적을 남긴다. 미커밋 변경은 `release-worktree-force: <브랜치> @ <시각>` 태그를 붙여 stash로 치우므로 `git stash list`에서 찾아 apply할 수 있고, 서브모듈은 `git submodule update --force`로 base가 기록한 커밋에 맞춘다.

아래는 되돌아갈 자리 자체가 없거나 대상이 잘못된 경우여서 `--force`로도 막힌다.

| 중단 이유 | 왜 막는가 | 해소 |
|---|---|---|
| base 사본이 원격과 갈라져 `pull --ff-only` 실패 | 강제로 맞추면 로컬 커밋이 사라진다 | 사용자가 사본을 직접 정리 |
| base 사본이 다른 worktree에 점유 | 되돌아갈 자리가 없다 | `--base`로 비어 있는 사본 지정 |
| detached HEAD, 없는 브랜치, 보호 브랜치를 인자로 지정 | 지울 대상 자체가 잘못됐다 | 브랜치를 바르게 지정 |
| `--force`로도 base를 특정하지 못함 | 자리의 base 사본 후보가 여럿이거나 없다 | `--base <name>`을 함께 지정 |

`--force`로 브랜치를 지울 때 base에 들어가지 않은 커밋이 있으면 그 개수를 경고로 남기고 진행한다. 커밋은 reflog에만 남는다.

## 막지 않는 것

아래 둘은 중단 사유가 아니다. 세션 마감을 막을 이유가 없고, base를 최신으로 맞추는 데 방해가 되지도 않는다.

- **untracked 파일** — 하네스·임시 스크립트처럼 일부러 커밋하지 않은 파일이 남아 있어도 그대로 두고 진행한다.
- **서브모듈 포인터 드리프트** — 서브모듈이 작업 브랜치를 가리키고 있어도 막지 않는다. `git submodule update`가 base가 기록한 커밋으로 되돌리며, 그 전에 무엇을 가리키고 있었는지(브랜치명과 커밋)를 경고로 남긴다. 서브모듈 커밋을 아직 push하지 않았다면 이 스킬을 실행하기 전에 push한다.

## 주의

- **스크립트를 우회해 git 명령을 직접 실행하지 않는다.** 가드레일이 스크립트 안에 있다.
- **성공 경로에서는 보고할 기회가 없다.** 탭이 닫히는 순간 이 세션이 끝나므로 스크립트 뒤에 아무것도 출력할 수 없다. 결과를 보여줘야 하는 상황이면 `--no-close`로 실행하고, 탭은 사용자가 닫도록 안내한다.
- **절전(sleep) 전환은 orca CLI에 명령이 없어 범위 밖이다.** 필요하면 사용자가 사이드바에서 직접 절전한다.
- **범위 밖은 손대지 않는다**: worktree 제거(`remove-worktree`), develop 반영(`merge-develop`), 서브모듈 포인터 변경(`git-submodule-update`), 무관한 stash 정리, reflog에 떠 있는 버려진 커밋 복구. 발견하면 보고만 한다.
