---
name: start-worktree
effort: low
description: Jira 이슈 하나를 worktree에서 착수하는 스킬. 유휴 worktree를 재사용하거나 새로 만들고 브랜치를 끊은 뒤, 현재 claude 세션을 대화 이력째 그 자리로 옮기고 원래 탭을 닫는다. 사용자가 'start-worktree', '이 이슈 작업 시작해', 'worktree에서 시작해', '작업 시작해줘', '착수해줘' 등을 Jira 키와 함께 요청할 때 이 스킬을 사용해야 한다. 피처 자체를 여는 요청에는 `start-feature`, 작업을 끝내고 자리를 반납하는 요청에는 `release-worktree`를 사용한다.
argument-hint: "<JIRA-KEY> [--base <ref>] [--pool <ref>] [--slot <계열>] [--new] [--no-move]"
allowed-tools: Bash, AskUserQuestion
---

## 역할

Jira 이슈 하나를 착수한다. base를 재사용할 수 있는 유휴 worktree가 있으면 거기서 작업 브랜치를 끊고, 없으면 새 worktree를 만든다. 그 자리로 현재 claude 세션을 대화 이력째 옮기고 원래 탭을 닫는다. 판정과 실행은 전부 `start-worktree.sh`가 맡고, 이 스킬은 사용자 발화와 Jira 조회 결과를 스크립트 플래그로 옮기는 얇은 층이다.

사용자 입력: $ARGUMENTS

## 절차

1. **이슈 키 확정** — 인자에 없으면 대화에서 찾는다. 그래도 없으면 `AskUserQuestion`으로 묻는다.
2. **base 결정** — 값이 셋이다. **자리를 찾는 기준**과 **브랜치를 끊을 지점**은 다른 개념이므로 하나로 합치지 않는다.
   - **풀 base (`--pool`)** — 유휴 worktree를 찾는 기준이다. `mcp__claude_ai_Atlassian__getJiraIssue`로 부모 에픽 키를 얻고, `git ls-remote --heads origin 'feature-base/<에픽키>*'`에 결과가 있으면 그 전체 이름을, 없으면 `develop`을 쓴다. 후보가 둘 이상이면 `AskUserQuestion`으로 묻는다.
   - **분기 지점 (`--base`)** — 작업 브랜치를 끊을 ref다. 기본값은 풀 base와 같다. 사용자가 형제 이슈 브랜치 위에서 진행하라고 지시하면(예: "위를 base로 진행해") 그 브랜치를 여기에만 넣는다. **이때도 풀 base는 그대로 구해서 넘긴다.** 자리를 찾는 기준까지 바꾸면 에픽의 유휴 자리가 후보에서 빠져 매번 새 worktree가 생긴다.
   - **슬롯 계열 (`--slot`)** — 풀 base 안에서 어느 슬롯 계열의 자리를 쓸지다. 풀 base가 `develop`으로 내려간 경우에만 판정하며, 원격 feature-base를 찾았다면 넘기지 않는다. 아래 순서를 그대로 밟는다.
     1. `git for-each-ref --format='%(refname:short)' 'refs/heads/develop-*'`로 로컬 슬롯 브랜치를 모은다. 접미사가 숫자뿐인 것(`develop-2`, `develop-3`)은 어느 이슈나 받는 범용 슬롯이므로 걷어낸다.
     2. 남은 이름에서 `develop-` 접두사와 끝의 `-<숫자>`를 떼면 계열 이름이다 (`develop-AGP-10-migration-2` → `AGP-10-migration`). 같은 계열의 사본이 여러 개면 계열 이름은 하나로 합쳐 센다. 계열이 하나도 없으면 `--slot`을 넘기지 않는다.
     3. 계열이 있으면 에픽 제목으로 대조한다. 에픽 제목에는 한글이 섞여 있어 기계적 치환으로는 계열 이름이 나오지 않으므로, `copy-new-branch-name`의 **에픽 slug 규칙**(마지막 대괄호 그룹의 내용을 명사구 kebab-case 영어로 옮긴다)을 적용해 slug를 만들고, 계열 이름은 소문자로만 바꿔 비교한다. 에픽 `[공통][AGP 10.0 마이그레이션]`의 slug는 `agp-10-migration`이고 계열 `AGP-10-migration`을 소문자로 바꾸면 같아진다.
     4. 정확히 하나가 맞으면 그 계열 이름을 `--slot`으로 넘긴다.
     5. **맞는 계열이 없는데 계열이 존재하거나, 둘 이상이 맞으면 `AskUserQuestion`으로 어느 자리에서 시작할지 확인받는다.** 추정으로 넘기지 않고, 확인 없이 범용 슬롯으로 떨어지지도 않는다.
3. **브랜치 이름** — `copy-new-branch-name` 스킬의 규칙을 그대로 적용해 `feature/<키>-<slug>`를 만든다. 규칙 본문은 그 스킬의 SKILL.md를 읽어 확인한다.
4. **Jira 상태 전이** — `~/.claude/references/jira-start-work.md` 절차로 이슈를 "진행 중"으로 옮긴다.
5. **스크립트 호출**

```
bash ~/.claude/skills/start-worktree/start-worktree.sh <키> --pool <풀 base> --base <분기 지점> --branch <branch> [--slot <계열>]
```

**스크립트가 성공하면 이 탭을 닫으므로, 호출 이후에는 어떤 도구도 부르지 않고 어떤 메시지도 쓰지 않는다.** 착수 보고는 새로 열린 탭이 이어받아서 한다.

스크립트가 0이 아닌 코드로 끝나면 탭이 닫히지 않은 것이므로, 그때는 출력된 오류를 사용자에게 그대로 전달한다.

## 옵션

| 사용자 발화 | 플래그 |
|---|---|
| "새로 만들어", "유휴 자리 말고" | `--new` |
| "자리만 준비해줘", "옮기지 마" | `--no-move` |
| base를 직접 지정 | `--base <ref>` (분기 지점만 바뀐다. `--pool`은 2번 절차대로 구해서 그대로 넘긴다) |
| "AGP 자리에서 해", 특정 계열을 지목 | `--slot <계열 이름>` |

**플래그를 추정해서 붙이지 않는다.** `--new`, `--no-move`는 사용자가 그 뜻으로 말했을 때만 붙인다. `--slot`은 2번 절차의 대조나 사용자 지목으로 계열이 확정됐을 때만 붙인다.

## 주의

- **스크립트를 우회해 git·orca 명령을 직접 실행하지 않는다.** 유휴 worktree 판별(메인 제외, mtime 정렬)과 세션 이사 순서가 스크립트 안에 있다.
- **사용자가 지정한 base 때문에 자리 탐색 기준을 바꾸지 않는다.** 유휴 자리는 `<풀 base>-<접미사>` 브랜치를 물고 upstream이 `origin/<풀 base>`인 자리이며, 형제 이슈 브랜치는 그 조건을 만족하지 않는다.
- **숫자 접미사 슬롯과 이름 접미사 슬롯을 한 후보군으로 다루지 않는다.** `develop-2`는 어느 이슈나 받는 범용 자리이고 `develop-AGP-10-migration`은 특정 에픽 전용으로 만들어 둔 자리인데, 풀 base가 `develop`으로 내려가면 둘이 같은 후보군에 들어간다. 스크립트는 `--slot` 없이는 범용 슬롯만 후보로 삼으므로, 전용 자리를 쓰려면 2번 절차대로 계열을 확정해 넘겨야 한다. 2026-09-08에 이 구분이 없어 AGP 10 마이그레이션 이슈가 `heydealer-android-2`에 들어갔고, 후보 네 자리의 mtime이 2초 안에 몰려 있어 선택이 사실상 임의였다.
- **계열을 지목해도 그 계열의 상위 base 자리는 후보가 아니다.** 접미사가 계열 이름뿐인 `develop-AGP-10-migration` 자리는 계열의 기준 자리이므로, 숫자 사본을 문 `develop-AGP-10-migration-2`·`-3` 자리만 받는다. 기준 자리를 작업 브랜치로 덮으면 그 계열이 되돌아갈 사본이 사라진다.
- **성공 경로에서는 보고할 기회가 없다.** 탭이 닫히는 순간 이 세션이 끝난다. 결과를 보여줘야 하는 상황이면 `--no-move`로 자리만 준비하고 사용자에게 안내한다.
- **범위 밖은 손대지 않는다**: 피처(에픽) 자체를 여는 일(`start-feature`), worktree 반납·삭제(`release-worktree`, `remove-worktree`).
