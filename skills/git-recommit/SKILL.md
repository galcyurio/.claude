---
name: git-recommit
description: 작업을 마친 브랜치의 커밋 히스토리를 처음부터 작업한 것처럼 다시 찍어야 할 때 사용한다. 피드백 반영 과정에서 "fix:"·"refactor:" 같은 보정 커밋이 쌓였거나, 커밋 단위·순서·메시지가 최종 결과와 맞지 않을 때가 대상이다. 사용자가 'git-recommit', 'recommit', '리커밋', '커밋 다시 찍어', '커밋 처음부터 다시', '처음부터 작업한 것처럼 커밋 정리', '커밋 재구성', '히스토리 다시 만들어', 'PR 올리기 전에 커밋 정리' 등을 요청하면 이 스킬을 사용한다. 피드백 하나를 특정 기존 커밋에 흡수하는 요청에는 `rebase-fix`를 사용한다.
allowed-tools: Bash(git:*), Bash(gh:*), Read, Write, Grep, Glob, AskUserQuestion
---

# git-recommit

브랜치의 최종 결과는 그대로 두고, 그 결과에 이르는 커밋을 처음부터 작업한 것처럼 다시 만든다. 피드백 때문에 생긴 보정 커밋은 사라지고, 각 변경은 원래 속해야 할 논리 단위 커밋에 들어간다.

`rebase-fix`는 피드백 하나를 기존 커밋 하나에 흡수한다. 이 스킬은 범위 안의 커밋 전체를 해체하고 새로 구성한다.

## 범위 모드

| 모드 | 진입 조건 | 다시 찍는 범위 |
|------|----------|---------------|
| **기본** | 별도 지시 없음 | push하지 않은 커밋만 (`git rev-list HEAD --not --remotes`) |
| **전체** | 인자 `--all`, 또는 "base 이후 전부", "push된 것도 포함" 같은 명시적 지시 | base 브랜치 분기점 이후 전부. force push가 필요해진다 |

기본 모드에서 push하지 않은 커밋이 없으면 아무것도 하지 않고 그 사실만 보고한다.

## 워크플로우

### 1. 사전 점검

```bash
git status --porcelain -uno
git rev-parse --abbrev-ref HEAD
```

- 추적 중인 파일에 변경이 있으면 중단하고 사용자에게 알린다. 작업 중인 변경이 새 커밋에 섞이기 때문이다. 원래 untracked였던 파일(`.agent/` 등)은 무시한다.
- 현재 브랜치가 `main`/`master`/`develop`/`release/*`이거나 `feature-base/*`면 중단한다.

### 2. 시작점(START) 결정

START는 다시 찍을 범위 바로 앞의 커밋이다. 이 커밋 자체는 건드리지 않는다.

**기본 모드**

```bash
OLDEST=$(git rev-list --reverse HEAD --not --remotes | head -1)
START=$(git rev-parse "$OLDEST^")
```

**전체 모드**: base 브랜치를 아래 순서로 정한다.

1. 열린 PR이 있으면 `gh pr view --json baseRefName -q .baseRefName`
2. 없으면 후보(`origin/feature-base/*`, `origin/develop`, `origin/main`, `origin/master`) 가운데 `git rev-list --count <merge-base>..HEAD`가 가장 작은 브랜치
3. 후보가 비슷하게 가까워 판단이 애매하면 `AskUserQuestion`으로 묻는다

```bash
START=$(git merge-base HEAD origin/<base>)
```

두 모드 모두, 범위에 머지 커밋이 있으면(`git rev-list --merges "$START"..HEAD`) 중단하고 사용자에게 보고한다. 머지 커밋은 다시 찍을 수 없다.

Bash 호출 사이에는 셸 변수가 유지되지 않는다. START와 이후의 BACKUP은 SHA·이름 값을 기록해 두고, 다음 명령에 값으로 직접 넣는다.

### 3. 백업

```bash
BACKUP=backup/$(git rev-parse --abbrev-ref HEAD)-$(date +%Y%m%d-%H%M%S)
git branch "$BACKUP"
```

이후 모든 비교와 복구는 `$BACKUP`을 기준으로 한다.

### 4. 새 커밋 구성안 작성

먼저 `~/.claude/references/commit-rules.md`를 Read한다. 그다음 아래 재료를 모은다.

```bash
git log --reverse --format='%h %s%n%b' "$START"..HEAD   # 기존 커밋의 의도
git diff --stat "$START" HEAD                           # 최종 변경 범위
git diff "$START" HEAD                                  # 최종 변경 내용
```

구성 원칙은 다음과 같다.

- **최종 diff만 보고 설계한다.** 기존 커밋 경계는 참고만 한다. 피드백으로 추가했다가 되돌린 코드는 최종 diff에 없으므로 어떤 커밋에도 나타나지 않는다.
- **보정 커밋을 남기지 않는다.** 작업 중 사용자 피드백으로 생긴 "피드백 반영", "누락 수정", "이름 변경" 같은 커밋은 그 변경이 속하는 논리 단위 커밋에 녹인다. 리네임도 처음부터 최종 이름으로 작성한 것으로 취급한다. 기본 모드는 push 전 커밋만 다루므로 commit-rules.md의 "PR 생성 전 커밋 전략"에 해당한다. 전체 모드에서 PR을 올린 뒤 다른 사람에게 받은 리뷰를 반영한 커밋까지 녹이는 것은 사용자가 전체 모드를 명시적으로 지시했기 때문에 허용되는 예외다.
- **단위와 순서는 commit-rules.md를 따른다.** 의존되는 쪽(모델·공용 컴포넌트)을 앞에, 사용하는 쪽을 뒤에 둔다. 각 커밋 시점에 존재하지 않는 코드를 참조하지 않게 배치한다.
- **기존 메시지가 여전히 맞으면 재사용한다.** 내용이 바뀌었거나 태그가 변경 성격과 맞지 않는 커밋(기능 추가인데 `fix:`인 경우 등)은 메시지를 새로 쓴다. 메시지 형식은 commit-rules.md를 따른다.

구성안을 `AskUserQuestion`으로 한 번 확인받는다. 커밋마다 메시지와 포함 파일(파일 일부만 들어가면 어느 부분인지)을 적고, 전후 커밋 수를 함께 보여 준다.

```
기존 7개 → 새 4개

1. feat(Login): 로그인 화면 골격을 추가한다
   - LoginScreen.kt, LoginUiState.kt
2. feat(Login): 로그인 실패 시 에러 메시지를 보여준다
   - LoginViewModel.kt, LoginScreen.kt(에러 표시 부분)
...
```

사용자가 수정을 요청하면 구성안을 고쳐 다시 확인받는다. 승인 전에는 히스토리를 바꾸지 않는다.

### 5. 다시 찍기

```bash
git reset --mixed "$START"
```

working tree에는 최종 결과가 그대로 남는다. 범위 안에서 새로 만든 파일은 이제 `??`(untracked)로 보이며, 1단계에서 무시한 원래 untracked 파일과 달리 반드시 어느 커밋에 넣어야 한다. 구성안 순서대로 커밋마다 해당 변경만 index에 올리고 커밋한다.

- **파일 전체가 한 커밋에 속하면** `git add <파일>` (삭제는 `git rm --cached <파일>`)
- **파일 일부만 속하면** 그 커밋 시점의 파일 내용을 만들어 index에만 올린다. working tree는 건드리지 않는다.

  ```bash
  # 방법 A: 해당 hunk만 남긴 patch를 index에 적용
  git diff "$START" "$BACKUP" -- <파일> > "$TMP/part.patch"   # 불필요한 hunk를 지운 뒤
  git apply --cached "$TMP/part.patch"

  # 방법 B: 그 시점의 파일 내용을 직접 작성해 index에 기록
  BLOB=$(git hash-object -w "$TMP/<파일 중간본>")
  git update-index --add --cacheinfo 100644,"$BLOB",<파일>
  ```

  `$TMP`는 세션 scratchpad 디렉토리를 쓴다. 실행 파일이면 모드를 `100755`로 맞춘다.

- 커밋 전에 `git diff --cached --stat`으로 이번 커밋에 들어갈 내용만 올라갔는지 확인한다.

### 6. 검증

```bash
git diff "$BACKUP" HEAD --stat    # 출력이 비어 있어야 한다
git status --porcelain -uno       # 출력이 비어 있어야 한다
git log --oneline "$START"..HEAD
```

빠뜨린 새 파일은 `status -uno`에 나타나지 않으므로 `git diff "$BACKUP" HEAD`가 기준이다. 차이가 남았는데 어느 커밋에 속하는지 분명하면, 그 변경만 올려 `git commit --fixup=<그 커밋>` 후 `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash "$START"`로 흡수하고 다시 검증한다. 어디에 속하는지 불분명하거나 충돌이 나면 `git rebase --abort` 후 `git reset --hard "$BACKUP"`으로 되돌리고 보고한다.

### 7. 보고

- 전후 커밋 목록
- 백업 브랜치 이름과 되돌리는 명령: `git reset --hard <BACKUP>`
- 백업이 필요 없어지면 지우는 명령: `git branch -D <BACKUP>`
- 전체 모드에서 push된 커밋을 다시 찍었다면 force push가 필요하다는 사실 한 줄

push는 하지 않는다.

## 안전장치

- 승인 전에는 `reset`을 실행하지 않는다
- 백업 브랜치를 만들기 전에는 `reset`을 실행하지 않는다
- 기본 모드에서는 원격에 있는 커밋을 범위에 넣지 않는다
- 검증 단계에서 `$BACKUP`과 tree가 다르면 완료로 보고하지 않는다
- 백업 브랜치를 스스로 지우지 않는다

## 자주 하는 실수

| 실수 | 결과 | 바로잡는 방법 |
|------|------|--------------|
| 기존 커밋을 그대로 squash만 한다 | 보정 커밋 내용이 엉뚱한 커밋에 들어가거나 순서가 그대로 남는다 | 최종 diff 기준으로 단위를 새로 설계한다 |
| 피드백 반영분을 마지막 커밋으로 따로 둔다 | "처음부터 작업한 것처럼"이 깨진다 | 그 변경이 속하는 논리 단위 커밋에 넣는다 |
| `git add -p`를 쓴다 | 대화형 입력을 기다리며 멈춘다 | `git apply --cached` 또는 `git update-index --cacheinfo`를 쓴다 |
| 파일 일부를 올리려고 working tree를 고친다 | 최종 결과가 훼손된다 | index에만 기록한다 |
| 기본 모드에서 `merge-base`를 START로 쓴다 | push된 커밋까지 다시 찍혀 force push가 필요해진다 | 기본 모드는 `--not --remotes`로 START를 정한다 |
| 검증 없이 완료를 보고한다 | 코드가 빠지거나 더해진 채 남는다 | `git diff "$BACKUP" HEAD`가 비어 있는지 확인한다 |
