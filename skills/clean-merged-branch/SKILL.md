---
name: clean-merged-branch
effort: low
description: PR이 원격에서 머지된 뒤 남은 로컬 작업 브랜치를 삭제하고 현재 worktree를 base 브랜치로 되돌리는 스킬. 사용자가 'clean-merged-branch', '머지된 브랜치 정리', '브랜치 정리해줘', '브랜치 지우고 base로 돌아가', 'PR 머지됐어 정리해줘', '작업 브랜치 삭제', '머지 끝났으니 정리', '로컬 브랜치 청소' 등을 요청할 때 이 스킬을 사용해야 한다. worktree 디렉토리 자체를 없애는 요청에는 `remove-worktree`를 사용한다 — 이 스킬은 worktree를 유지한 채 브랜치만 정리한다.
argument-hint: "[branch-name]"
---

## 역할

원격에서 머지가 끝난 로컬 작업 브랜치를 안전하게 삭제하고, 현재 worktree를 해당 PR의 base 브랜치로 되돌린다. 머지 여부는 `gh pr`로 확인하고, base는 PR의 `baseRefName`으로 판별하며, worktree 접미사에 맞는 base 사본 브랜치로 전환한다.

사용자 입력: $ARGUMENTS

## 입력 형식

- `branch-name` (선택): 정리할 로컬 브랜치 이름. 미지정 시 현재 체크아웃 중인 브랜치를 대상으로 삼는다.
  - 현재가 detached HEAD이고 인자도 없으면 안내 후 종료: "정리할 브랜치를 지정해 주세요 (현재 detached HEAD)."

## 사전 검증

### 1. 대상 브랜치 확정과 머지 확인

```bash
gh pr list --state merged --head <branch> --json number,baseRefName,mergedAt --limit 1
```

| 결과 | 처리 |
|------|------|
| PR 1건 | `baseRefName`을 base로 확정하고 진행 |
| 빈 배열 | 머지된 PR 없음 → 아래 `AskUserQuestion` |

**upstream이 `gone`이라는 이유만으로 머지되었다고 판정하지 않는다.** 원격 브랜치를 수동 삭제했거나 PR이 머지 없이 닫혔을 때도 `gone`이 된다.

PR이 없으면 `AskUserQuestion`:

- 옵션 1: `중단 (Recommended)` — 머지 여부를 사람이 확인한 뒤 다시 실행
- 옵션 2: `base를 직접 지정하고 진행` — 사용자가 base 브랜치 이름을 입력. 이 경로에서도 삭제는 `-d`를 유지한다.
- 옵션 3: `강제 삭제 -D` — 사용자가 명시적으로 요청한 경우에만. 커밋 손실을 감수한다.

### 2. base 사본 브랜치 결정 (접미사 자동 매칭)

이 저장소는 같은 base를 여러 worktree에서 쓰기 위해 `-2`, `-3` 접미사 사본을 둔다. git은 한 브랜치를 두 worktree에서 동시에 체크아웃할 수 없기 때문이다.

```bash
git rev-parse --git-common-dir   # 메인 worktree의 .git → 부모가 메인 디렉토리
git rev-parse --show-toplevel    # 현재 worktree 디렉토리
```

현재 worktree 디렉토리 이름에서 메인 worktree 디렉토리 이름을 뺀 나머지가 접미사다 (`heydealer-android-3` − `heydealer-android` = `-3`). 메인 worktree면 접미사는 빈 문자열.

후보를 순서대로 시도한다.

| 순서 | 후보 | 채택 조건 |
|------|------|----------|
| 1 | `<baseRefName><접미사>` | 로컬에 존재하고 다른 worktree가 점유하지 않음 |
| 2 | `<baseRefName>` (접미사 없는 원본) | 위가 없고, 이것도 다른 worktree가 점유하지 않음 |
| 3 | — | 둘 다 실패 → `AskUserQuestion` |

3번에 도달하면 `git branch --list '<baseRefName>*'` 결과를 옵션으로 제시하고 사용자가 고르게 한다. 사본을 임의로 새로 만들지 않는다.

점유 여부는 `git worktree list --porcelain`의 `branch refs/heads/<name>` 항목으로 확인한다.

### 3. 손실 위험 점검

대상 브랜치가 **현재 체크아웃 중일 때만** 브랜치를 전환하므로, 아래 검증도 그 경우에만 수행한다.

```bash
git status --porcelain
```

비어 있지 않으면 변경 파일(최대 10개) 표시 후 `AskUserQuestion`:

- 옵션 1: `중단 (Recommended)` — 커밋하거나 stash한 뒤 다시 실행
- 옵션 2: `stash 후 진행` — `git stash push -u -m "clean-merged-branch: <branch>"`

미push 커밋은 별도로 묻지 않는다. base 사본에 포함되지 않은 커밋이 있으면 5단계의 `git branch -d`가 스스로 거부한다.

### 4. 대상 브랜치 점유 확인

대상 브랜치를 다른 worktree가 체크아웃 중이면 삭제할 수 없다. 그 경우 해당 worktree 경로와 함께 보고하고 종료한다.

> `<branch>`는 `<worktree-path>`가 체크아웃 중이라 삭제할 수 없습니다. 그 worktree에서 정리하거나 `remove-worktree`로 제거해 주세요.

**다른 worktree의 브랜치를 대신 전환하지 않는다.** 이 스킬은 현재 worktree만 건드린다.

## 실행

아래 순서를 그대로 따른다. 명령을 생략하거나 순서를 바꾸지 않는다.

### 1. 원격 상태 갱신

```bash
git fetch --prune
```

머지 시 GitHub이 원격 head 브랜치를 자동 삭제하므로, stale 추적 ref만 정리하면 된다. **`git push origin --delete`는 실행하지 않는다.**

### 2. base 사본으로 전환

대상 브랜치가 현재 체크아웃 중일 때만 실행한다. 아니면 이 단계와 3·4단계를 건너뛰고 5단계로 간다.

```bash
git switch <base 사본>
```

### 3. base 사본 최신화

```bash
git pull --ff-only
```

base 사본은 접미사 없는 원격 ref를 upstream으로 갖는다(`develop-3` → `origin/develop`). `--ff-only`로 예기치 않은 머지 커밋 생성을 막는다. 거부되면 사본이 갈라진 상태이니 강제로 맞추지 말고 보고 후 중단한다.

### 4. 서브모듈 동기화

```bash
git submodule update
```

**경로 인자를 붙이지 않는다.** `git submodule update -- prnd-library`와 `git restore --source=HEAD --worktree -- prnd-library`는 훅이 차단한다. 포인터를 의도적으로 바꿔야 하면 `update-git-submodule` 스킬을 경유한다.

### 5. 브랜치 삭제

```bash
git branch -d <branch>
```

**`-D`는 사용자가 명시적으로 요청한 경우에만 쓴다.** `-d`가 거부하면 base에 포함되지 않은 커밋이 있다는 뜻이므로, 거부 메시지를 그대로 보여주고 중단한다. 자동으로 `-D`로 승격하지 않는다.

머지 판정은 항상 **base 기준**이다(`git branch --merged <base 사본>`). develop 기준으로 판정하면 epic base에만 머지된 브랜치를 미머지로 오판한다.

### 6. 결과 보고

- 삭제한 브랜치
- 현재 위치한 base 사본 브랜치와 최신화 결과
- 서브모듈 동기화 여부
- 건너뛴 항목과 이유 (다른 worktree 점유, stash 처리 등)

### 7. 남은 머지 브랜치 보고 (기본 동작)

정리 후 같은 base에 이미 머지된 다른 로컬 브랜치를 조사한다.

```bash
git branch --merged <base 사본>
```

아래를 제외한 나머지가 후보다.

- 현재 브랜치
- base 사본 계열 전부 (`<baseRefName>`, `<baseRefName>-2`, `<baseRefName>-3` …)
- `develop*`, `main`, `master`
- 다른 worktree가 점유 중인 브랜치 (점유 사실과 함께 별도로 표시)

후보가 있으면 목록만 보고하고 자동으로 지우지 않는다. 이어서 `AskUserQuestion`:

- 옵션 1: `여기서 종료 (Recommended)` — 목록만 남긴다
- 옵션 2: `전부 스윕 삭제` — 각 후보에 `git branch -d <candidate>`를 적용한다

**스윕에서는 `gh pr`을 다시 조회하지 않는다.** 후보는 이미 `git branch --merged <base 사본>`로 base 포함이 확인된 브랜치이고, `gh pr`은 base를 알아내기 위한 수단이었을 뿐이다. PR 기록 없이 직접 머지된 브랜치까지 재확인 루프에 가두지 않는다. 스윕에서도 `-d`만 쓰고, 거부당한 후보는 건너뛰어 이유와 함께 보고한다.

후보가 없으면 질문 없이 "추가 정리 대상 없음"으로 마무리한다.

## 예시

| 현재 worktree | 대상 브랜치 | PR base | 전환할 base 사본 |
|---------------|------------|---------|-----------------|
| `heydealer-android-3` | `feature/HDA-22364-...` | `feature-base/HDA-22279-car-list-design-system` | `feature-base/HDA-22279-car-list-design-system-3` |
| `heydealer-android` (메인) | `feature/HDA-22339-...` | `develop` | `develop` |
| `heydealer-android-2` | `feature/HDA-22338-...` | `develop` | `develop-2` (없으면 `develop`) |

## 주의사항

- **base를 develop으로 가정하지 않는다.** 이 프로젝트는 에픽 단위 `feature-base/HDA-xxxxx-*` 위에서 작업 브랜치가 갈라진다. base는 항상 PR의 `baseRefName`에서 온다.
- **머지 판정은 `gh pr`로 한다.** upstream `gone`은 근거가 되지 않는다.
- **삭제는 `-d`만.** `-D`는 사용자 명시 요청 전용.
- **원격 브랜치는 건드리지 않는다.** GitHub이 머지 시 자동 삭제한다. `git fetch --prune`으로 충분하다.
- **현재 worktree만 건드린다.** 다른 worktree의 브랜치는 보고만 하고 전환·삭제하지 않는다.
- **범위 밖은 손대지 않는다**: worktree 제거(`remove-worktree`), develop 반영(`merge-develop`), 서브모듈 포인터 변경(`update-git-submodule`), 무관한 stash 정리, reflog에 떠 있는 버려진 커밋 복구. 발견하면 보고만 한다.
