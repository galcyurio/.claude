---
name: merge-develop
description: PRND Android에서 develop의 최신 변경을 epic base 브랜치(feature-base/HDA-xxxx)에 반영하는 스킬. merge/HDA-xxxx 브랜치를 만들어 develop을 머지하고 push하면 create_merge_pr.yml workflow가 base로 향하는 PR을 자동 생성하고 auto-merge를 켠다. 사용자가 'merge-develop', 'develop 최신화', 'develop 최신화 반영', 'epic 브랜치 최신화', 'feature-base 최신화', 'base 브랜치에 develop 반영', 'develop 머지해줘', 'merge 브랜치 만들어 develop 반영' 등을 요청할 때 사용한다. 단순 PR 생성이나 prnd-library 서브모듈 최신화에는 사용하지 않는다.
allowed-tools: Bash, AskUserQuestion
---

# merge-develop

PRND Android에서 `develop`의 최신 변경을 epic base 브랜치(`feature-base/HDA-xxxx`)에 반영한다. base는 보호되어 직접 push할 수 없으므로, `merge/HDA-xxxx` 브랜치에 develop을 머지해 push한다. 절차 대부분이 결정적이라 지원 스크립트가 브랜치 생성부터 보고까지 한 번에 수행한다.

## 핵심 메커니즘 (반드시 이해)

`merge/**` 브랜치가 push되면 `create_merge_pr.yml`(`PRNDcompany/prnd-android-workflows`) workflow가 자동으로:

1. 브랜치명에서 `HDA-xxxx` 키 추출 → 대응하는 `feature-base/HDA-xxxx*` base 브랜치 resolve
2. `merge/HDA-xxxx` → `feature-base/HDA-xxxx` PR 생성 (제목 `HDA-xxxx develop 브랜치 최신화`)
3. **auto-merge 활성화**

이후는 모드에 따라 지원 스크립트가 담당한다:

- **기본**: 자동 생성 PR 감지 → CI Check 완료 대기 → 결과 보고
- **auto**: 위 + CI 통과 시 **approve** → auto-merge 발동 → 실제 머지 완료까지 대기 → 보고

PR 작성자는 workflow의 CI 토큰이라, 개발자 approve는 셀프 승인이 아니다.

스크립트 밖에서 **수동으로 하지 않는다**:

- ❌ `gh pr create` — PR은 workflow가 만든다 (수동 생성 시 auto-merge 유실·중복)
- ❌ `gh pr merge <pr> --merge` (즉시 머지) — 머지는 approve → auto-merge 경로로만 (`auto` 모드의 approve는 스크립트가 수행)

## 언제 사용 / 안 함

**사용한다**
- epic 작업 중 develop이 앞서 나가 base 브랜치를 최신화해야 할 때
- epic PR(feature-base → develop)에 develop 충돌이 생겨 풀어야 할 때

**사용하지 않는다**
- 일반 PR 생성 (이 스킬은 develop → base 반영 전용)
- prnd-library 서브모듈 브랜치 전환
- caller workflow(`.github/workflows/create_merge_pr.yml`)가 없는 repo — push해도 자동 PR이 안 생긴다(먼저 workflow 설치 필요)

## 실행

지원 스크립트가 **브랜치 생성 → develop 머지 → push → PR 감지 → CI 대기 → 보고**까지 한 번에 처리한다:

```bash
${CLAUDE_SKILL_DIR}/merge-develop.sh <feature-base 브랜치 | HDA-키> [auto]
```

- 인자로 `feature-base/HDA-xxxx-...` 브랜치명 또는 `HDA-xxxx` 키를 넘긴다. 키면 스크립트가 base를 resolve하고, 후보가 여럿이면 정확한 브랜치명을 요구한다.
- `auto`: CI 통과 시 approve까지 걸어 auto-merge를 유발하고, **실제 머지 완료까지 대기**한 뒤 보고한다.
- 단독 실행 가능 — git·gh만 있으면 터미널에서 직접 실행한다(스킬 없이도). 도움말: `merge-develop.sh -h`.

### 스크립트 단계

1. 사전 점검 — 리포/working tree clean 확인, `git fetch origin --prune`
2. 대상 `feature-base` resolve, `merge/` 브랜치명 결정 (`feature-base/` → `merge/` 치환)
3. `origin/feature-base` tip에서 `merge/` 브랜치 생성 → `git merge --no-edit origin/develop`
4. push (base 직접/force push 안 함) → workflow가 PR·auto-merge 생성
5. 자동 생성 PR 감지 → CI Check 완료 대기 → pass/fail 보고
6. `auto`: approve → auto-merge → `merged` 확인까지 대기 → 보고

exit: `0` 성공 · `1` 실패 · `2` 사용법/사전조건 · `3` 머지 충돌(사람 해결) · `4` gh 인증 · `124` 타임아웃

### 충돌이 나면 (사람이 해결)

3단계에서 develop 머지가 충돌하면 스크립트는 **자동 해결하지 않고 중단**한다(exit 3). 충돌 파일을 보고한다. 타 팀 코드 충돌은 도메인 지식이 필요하므로 **사용자에게 넘긴다.** 해결 후 재개:

```bash
# 충돌 수정 → git add <파일> → git commit  (머지 커밋 완성)
${CLAUDE_SKILL_DIR}/merge-develop.sh <feature-base 브랜치> [auto] --continue
```

`--continue`는 현재 `merge/` 브랜치에서 머지가 커밋됐는지 확인하고 push부터 이어서 진행한다. (되돌리려면 `git merge --abort`.)

스크립트 종료 후 결과(통과/실패, 머지 여부, PR URL)를 사용자에게 그대로 보고한다.

## 안전장치

- working tree가 clean하지 않으면 시작하지 않는다
- `origin/feature-base` tip 기준으로 merge 브랜치를 만든다 (stale 로컬 base 아님)
- develop 머지 충돌은 자동 해결하지 않고 사용자에게 넘긴다 (exit 3)
- base 직접 push / force-push 하지 않는다
- 스크립트 밖에서 수동 `gh pr create` / `gh pr merge --merge` 하지 않는다

## 자주 하는 실수

- **rebase/squash로 develop 반영**: 공유 base 히스토리를 rewrite/평탄화한다. 반드시 merge commit으로 남긴다 (스크립트는 `git merge --no-edit`).
- **stale 로컬 base 기준으로 브랜치 생성**: 로컬 `feature-base`가 origin보다 뒤처져 있으면 낡은 base에서 판다. 스크립트는 `origin/feature-base` tip을 쓴다.
- **충돌 자동 해결**: 타 팀 코드와의 충돌은 도메인 지식이 필요하다. exit 3에서 멈추고 사람이 푼다.
- **수동 PR 생성/즉시 머지**: `gh pr create`나 `gh pr merge --merge`를 직접 하면 auto-merge 유실·중복이 생긴다. PR 생성=workflow, 머지=approve→auto-merge에 맡긴다.
- **base 직접 push**: 보호되어 거부된다(개발 계정 admin→maintain). merge 브랜치로만 반영한다.

## 핵심 명령 요약

```bash
# 전체 (브랜치 생성 → 머지 → push → PR 감지 → CI 대기 → 보고)
${CLAUDE_SKILL_DIR}/merge-develop.sh feature-base/HDA-xxxx-<suffix>
# CI 통과 시 approve+머지까지 자동
${CLAUDE_SKILL_DIR}/merge-develop.sh HDA-xxxx auto
# 충돌 해결(git add·commit) 후 재개
${CLAUDE_SKILL_DIR}/merge-develop.sh feature-base/HDA-xxxx-<suffix> auto --continue
```
