---
name: rebase-fix
description: 리뷰 피드백을 기존 커밋에 fixup + autosquash로 흡수해서 새 커밋을 쌓지 않게 하는 스킬. 사용자가 'rebase-fix', '기존 커밋에 합쳐줘', '여기 별로네 다시', '이 부분 마음에 안 들어', '새 커밋 쌓지 말고', 'fixup으로', 'amend로', 'interactive rebase로 가서 수정', '히스토리 깨끗하게', '리뷰 반영해줘 (기존 커밋에)', '여기 수정해줘 (직전 작업)' 등 — AI가 만든 기존 커밋의 코드를 수정해야 하는 리뷰 피드백을 줄 때 이 스킬을 사용해야 한다. 새 기능 추가, 별도 변경, working tree에 있는 단순 수정에는 사용하지 않는다.
allowed-tools: Bash(git:*), Read, Edit, Grep, Glob, AskUserQuestion
---

# rebase-fix

리뷰 피드백을 받았을 때 새 "fix: ..." 커밋을 쌓지 않고, `git commit --fixup` + `git rebase -i --autosquash`로 원래 만든 커밋에 흡수한다.

## 언제 사용하는가

**사용한다**
- AI가 작업한 결과(현재 브랜치의 커밋들)를 리뷰하다가 기존 커밋 내부의 코드를 고쳐야 할 때
- "여기 별로네", "이 부분 다시 해줘", "마음에 안 들어", "이 함수 이름 바꿔줘" 같은 피드백
- 한 번에 여러 곳을 고쳐야 할 때(피드백 모아서 일괄 처리)

**사용하지 않는다**
- 새 기능을 추가할 때(정상적인 새 커밋이 맞다)
- working tree에 아직 커밋되지 않은 변경만 있을 때(그냥 수정하면 됨)
- main/master/develop 등 보호 브랜치 위에서 직접 작업 중일 때
- 분기점(base) 이전의 history를 건드려야 할 때

## 자동 진입 조건

slash command 외에, 아래 조건이 **모두** 충족될 때만 자동 진입한다. 하나라도 어긋나면 자동 진입하지 않고 사용자에게 확인한다.

1. 사용자 발화에 수정 의도가 명확하다 — "별로네", "다시", "수정해", "마음에 안 들어"
2. 변경 대상이 현재 브랜치의 분기점 이후 커밋 안의 코드다
3. 단순 추가가 아닌, 기존 코드의 변경/개선이다

## 워크플로우

### 1. 사전 점검 (필수)

```bash
git status --porcelain                       # working tree clean 확인
git rev-parse --abbrev-ref HEAD              # 현재 브랜치 확인
```

- working tree가 dirty하면 → 사용자에게 stash/커밋 후 재시도 안내하고 중단
- 현재 브랜치가 `main`/`master`/`develop`이면 → 중단

### 2. base 결정

분기점(merge-base)을 자동 탐지한다.

```bash
git merge-base HEAD origin/main 2>/dev/null \
  || git merge-base HEAD origin/master 2>/dev/null \
  || git merge-base HEAD origin/develop 2>/dev/null
```

- 모두 실패하면 `AskUserQuestion`으로 base 브랜치를 묻는다
- 결정된 base SHA를 변수로 보관(이후 단계에서 재사용)

### 3. 피드백 정리

사용자의 피드백을 항목별로 재진술. 여러 항목이면 리스트로 보여주고 한 번만 확인한다.

```
받은 피드백:
1. src/login.ts: 에러 메시지를 사용자 친화적으로
2. src/utils/format.ts: 함수명 formatDate -> toIsoString
3. test/login.spec.ts: 케이스 1개 추가

위 항목을 fixup 커밋으로 처리한 후 한 번에 autosquash 합니다. 진행할까요?
```

### 4. 각 피드백을 fixup 커밋으로 (반복)

피드백마다 다음을 수행:

```bash
# target 커밋 찾기 — 둘 다 활용
git log --oneline <base>..HEAD -- <file>     # 해당 파일을 건드린 커밋들
git blame -L <start>,<end> <file>            # 정확한 라인의 origin 커밋
```

- 후보가 여러 개면 가장 관련성 높은 것을 골라 SHA와 이유를 함께 출력
- target SHA가 base 이전이면 **즉시 중단** — 이미 합쳐진 history는 건드리지 않는다

코드 수정 후:

```bash
git add <변경된 파일들만>
git commit --fixup=<targetSha>
```

### 5. 일괄 autosquash

모든 fixup 커밋 생성이 끝나면 미리보기를 보여주고 일괄 squash.

```bash
git log --oneline <base>..HEAD               # fixup! 로 시작하는 커밋들 확인
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>
```

- `GIT_SEQUENCE_EDITOR=:`로 에디터를 띄우지 않고 자동 진행
- 충돌 발생 시: `git rebase --abort`로 즉시 원복하고 사용자에게 보고(자동 해결 금지)

### 6. 종료 안내

```bash
git log --oneline <base>..HEAD               # 최종 history 확인
```

다음 메시지를 출력하고 종료:

```
완료. 새 커밋을 쌓지 않고 기존 커밋에 흡수했습니다.

이미 push된 브랜치라면 다음 명령으로 force push가 필요합니다:
  git push --force-with-lease

push는 직접 실행해 주세요.
```

## 안전장치

- working tree가 clean하지 않으면 시작하지 않는다
- 보호 브랜치(main/master/develop) 위에서 동작하지 않는다
- base 결정이 모호하면 사용자에게 묻는다
- target SHA가 base 이전이면 즉시 중단한다
- 충돌 발생 시 자동 해결을 시도하지 않는다 — 항상 `--abort` 후 사용자에게 보고
- push는 절대 자동으로 실행하지 않는다

## 자주 하는 실수

- **stashing 누락**: working tree에 변경이 남아 있으면 fixup이 의도와 다른 변경까지 흡수한다. 시작 전 반드시 `git status --porcelain`로 확인.
- **target SHA 잘못 잡기**: 같은 파일을 여러 커밋이 건드렸을 때 단순 last-touch만 보면 틀린다. `git blame -L <start>,<end>`로 라인 단위로 확인.
- **base를 hard-code**: `main`이 없는 저장소(예: `master`만 있는 곳)에서 깨진다. 자동 탐지 + 모호하면 묻기.
- **분기점 이전 커밋 건드리기**: 이미 합쳐진 history를 건드리면 다른 사람의 작업에 영향이 간다. target이 base보다 오래되면 즉시 중단.
- **`git rebase -i`를 editor 열린 채로 호출**: 대화형 에디터가 열리면 흐름이 멈춘다. 반드시 `GIT_SEQUENCE_EDITOR=:`와 `--autosquash` 조합 사용.

## 핵심 명령 요약

```bash
# 사전 점검
git status --porcelain
BASE=$(git merge-base HEAD origin/main)      # 또는 master/develop

# 피드백마다
git log --oneline $BASE..HEAD -- <file>
git blame -L <start>,<end> <file>
# ... 코드 수정 ...
git add <file>
git commit --fixup=<targetSha>

# 일괄 squash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash $BASE

# 결과
git log --oneline $BASE..HEAD
```
