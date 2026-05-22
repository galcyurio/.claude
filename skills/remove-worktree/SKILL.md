---
name: remove-worktree
description: git worktree를 안전하게 제거하는 스킬. 사용자가 'remove-worktree', 'worktree 삭제', 'worktree 정리', 'worktree 제거', '워크트리 삭제', '워크트리 정리', '워크트리 지워', 'worktree prune', 'worktree cleanup' 등 worktree 제거를 요청할 때 이 스킬을 사용해야 한다. worktree 생성 요청에는 `create-worktree`를 사용한다.
argument-hint: "[worktree-path-or-name]"
---

## 역할

dev/* 프로젝트의 worktree를 안전하게 제거한다. 미커밋 변경과 미push 커밋을 사전 검증해 손실을 막은 뒤, worktree 제거 → 옵션에 따른 브랜치 삭제 → `git worktree prune`까지 일관 수행한다.

사용자 입력: $ARGUMENTS

## 입력 형식

- `worktree-path-or-name` (선택): 제거할 worktree의 절대 경로 또는 디렉토리 이름. 미지정 시 사용자에게 목록을 보여주고 묻는다.
  - 디렉토리 이름만 입력 가능 (예: `heydealer-android-2`) — 메인 worktree의 부모 디렉토리에서 검색.

## 사전 검증

### 1. 현재 위치가 메인 worktree인지 확인

`git rev-parse --git-common-dir`과 `git rev-parse --git-dir`을 비교한다.

- 두 값이 같음 → 메인 worktree, 진행.
- 두 값이 다름 → 현재 위치는 worktree다. 안내 후 종료한다:

> 현재 위치는 worktree입니다(`<현재 git-dir 부모>`). worktree 제거는 메인 worktree(`<git-common-dir 부모>`)에서 실행해 주세요.
> git은 자기 자신을 체크아웃 중인 worktree를 제거할 수 없습니다.

사용자가 "여기서 그냥 진행"을 명시하면 그래도 거부한다 — 자기 자신 제거는 git이 본질적으로 막는 동작이다.

### 2. 메인 worktree 자체를 제거 대상으로 받았는지 확인

`git worktree list --porcelain` 첫 번째 항목이 메인. 사용자가 그 경로를 제거 대상으로 지정했으면 거부:

> 메인 worktree(`<path>`)는 본 스킬로 제거할 수 없습니다. 저장소를 통째로 정리하려면 별도 절차로 진행해 주세요.

## 입력 결정

### 1. 대상 worktree 선택

`$ARGUMENTS`로 경로/이름이 지정된 경우 이 단계를 생략한다. 그렇지 않으면 메인을 제외한 worktree 목록을 추출하여 `AskUserQuestion`으로 제시한다.

```bash
git worktree list --porcelain | awk '
  /^worktree /{wt=$2}
  /^branch /{br=$2}
  /^$/{ if (wt) print wt "\t" br; wt=""; br="" }
  END { if (wt) print wt "\t" br }
' | tail -n +2
```

각 항목을 옵션 label로 표시(`<디렉토리 이름> [<브랜치>]`). 옵션이 0개면 "제거할 worktree가 없습니다" 안내 후 종료. 4개 초과면 처음 3개만 표시 + `Other`로 나머지 직접 입력.

### 2. 경로 정규화

사용자 입력이:
- 절대 경로 → 그대로 사용
- 디렉토리 이름만 → 메인 worktree 부모에서 `<parent>/<name>` 형태로 결합

정규화된 경로가 `git worktree list --porcelain`에 실재하는지 확인. 없으면 안내 후 종료:

> 해당 경로(`<path>`)는 worktree 목록에 없습니다. `git worktree list`로 확인해 주세요.

### 3. 대상 worktree의 브랜치 식별

`git worktree list --porcelain`에서 정규화된 경로의 `branch refs/heads/<name>` 항목을 추출. detached HEAD인 worktree는 브랜치 없음으로 처리(이후 브랜치 정리 단계 자동 skip).

## 안전 검증

손실 위험이 있는 항목을 점검한다. 셋 다 통과하지 못하면 사용자 확인을 받기 전에는 절대 제거하지 않는다.

### 1. 미커밋 변경사항

```bash
git -C <worktree-path> status --porcelain
```

출력이 비어 있지 않으면 변경 파일 목록(최대 10개) 표시 후 `AskUserQuestion`:

- 옵션 1: `중단 (Recommended)` — 사용자가 직접 커밋/stash 후 다시 실행
- 옵션 2: `강제 제거 (변경사항 폐기)` — `git worktree remove --force` 사용

### 2. 미 push 커밋

```bash
git -C <worktree-path> rev-list @{u}..HEAD 2>/dev/null
```

`@{u}` 조회가 실패하면(upstream 없음) 다음을 사용:

```bash
git -C <worktree-path> log --oneline <branch> --not --remotes
```

결과가 비어 있지 않으면 미 push 커밋 목록(`<sha> <subject>`, 최대 10개) 표시 후 `AskUserQuestion`:

- 옵션 1: `중단 (Recommended)` — push하고 다시 실행
- 옵션 2: `강제 제거` — 커밋 손실 감수

## 실행

### 1. worktree 제거

`git worktree remove <worktree-path>`. 안전 검증에서 사용자가 강제 진행을 택한 경우에만 `--force`를 더한다.

```bash
git worktree remove [--force] <worktree-path>
```

명령 실패 시 에러 메시지를 그대로 노출하고 종료. 후속 단계는 진행하지 않는다(브랜치를 잘못 지우는 위험 회피).

### 2. 브랜치 정리

대상 worktree에 식별된 브랜치가 있으면 `AskUserQuestion`으로 삭제 여부를 묻는다. base 브랜치는 `develop` → `main` → `master` 순으로 존재하는 첫 번째.

먼저 merged 여부 확인:

```bash
git branch --merged <base> | grep -qx "  <branch>"
```

판정에 따라 옵션 라벨을 다르게 표시한다.

| merged 여부 | 옵션 |
|------------|------|
| merged | 1) `안전 삭제 -d (Recommended)` 2) `유지` |
| not merged | 1) `유지 (Recommended)` 2) `강제 삭제 -D` |

선택에 따라 `git branch -d <branch>` 또는 `git branch -D <branch>` 실행.

### 3. 원격 브랜치 정리

로컬 브랜치를 삭제한 경우, 원격에도 같은 이름의 브랜치가 있는지 확인:

```bash
git ls-remote --heads origin <branch>
```

존재하면 `AskUserQuestion`:

- 옵션 1: `유지 (Recommended)` — 원격 삭제는 협업 영향이 있으므로 안전 기본
- 옵션 2: `원격에서도 삭제` — `git push origin --delete <branch>`

### 4. prune

```bash
git worktree prune
```

stale worktree 메타데이터를 정리한다.

### 5. 결과 보고

- 제거된 worktree 경로
- 삭제된 로컬 브랜치 (있으면)
- 삭제된 원격 브랜치 (있으면)
- 강제 진행한 안전 검증 항목 (있으면 — "미커밋 변경사항 폐기", "미 push 커밋 손실" 등)
- prune으로 정리된 stale entry 수

## 예시

| 메인 | 인자 | 대상 worktree | 결과 |
|------|------|--------------|------|
| `/Users/olaf/dev/heydealer-android` | `heydealer-android-2` | `/Users/olaf/dev/heydealer-android-2` | 제거 + 브랜치(merged) 삭제 + prune |
| `/Users/olaf/dev/heydealer-android` | (없음) | 사용자 선택 | 〃 |
| `/Users/olaf/dev/revolt-android` | `release/26.04.30` | (해당 경로 없음) | "worktree 목록에 없음" 안내 후 종료 |

## 주의사항

- **자기 자신 제거 금지**: 현재 위치가 worktree면 거부. git이 본질적으로 막는 동작.
- **메인 worktree 제거 금지**: 본 스킬은 보조 worktree 제거만 책임.
- **손실 가능성 있는 동작은 모두 명시적 승인**: 미커밋·미 push는 자동 진행하지 않는다.
- **원격 브랜치 삭제는 보수적 기본값(유지)**: 협업 영향이 있어 사용자 명시 승인 필요.
- **base 추정은 `develop` → `main` → `master` 순**: `create-worktree`와 동일 규칙.
- **`.claude/`의 rules 심볼릭 링크와 settings.local.json은 별도 백업하지 않는다**: rules는 외부 절대 경로 링크라 worktree 제거와 함께 사라져도 정보 손실 없음. settings.local.json은 메인이 정본.
