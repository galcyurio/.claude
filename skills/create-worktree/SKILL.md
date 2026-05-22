---
name: create-worktree
description: git worktree를 추가하고 서브모듈/.claude/.agent 초기화까지 한 번에 처리하는 스킬. 사용자가 'create-worktree', 'worktree 만들어', 'worktree 추가', '워크트리 만들어', '워크트리 생성', '병렬 작업 환경 만들어줘', '새 worktree' 등 worktree 생성을 요청할 때 이 스킬을 사용해야 한다. worktree 삭제/조회 요청에는 사용하지 않는다.
argument-hint: "[branch-name] [base-branch]"
---

## 역할

현재 git 저장소에서 새 worktree를 생성하고, 서브모듈·`.claude/`·`.agent/` 환경까지 새 worktree에서 즉시 작업 가능한 상태로 초기화한다.

사용자 입력: $ARGUMENTS

## 입력 형식

- `branch-name` (선택): worktree에서 사용할 브랜치 이름. 미지정 시 사용자에게 묻는다.
  - 기존 원격/로컬 브랜치 이름이면 해당 브랜치를 체크아웃한다.
  - 신규 이름이면 `base-branch`에서 분기하여 새 브랜치를 만든다.
- `base-branch` (선택): 신규 브랜치 생성 시 분기점. 미지정 시 `develop` → `main` → `master` 순으로 존재하는 첫 번째를 사용한다.

## 사전 검증

### 1. 현재 위치가 메인 worktree인지 확인

`git rev-parse --git-common-dir`과 `git rev-parse --git-dir`을 비교한다. 두 값이 다르면 현재 디렉토리는 이미 worktree이며, 새 worktree는 메인 worktree에서 만드는 것이 자연스럽다.

- 두 값이 같음 → 메인 worktree, 진행
- 두 값이 다름 → "현재 위치는 worktree입니다. 메인 worktree(`<git-common-dir의 부모 디렉토리>`)로 이동한 뒤 다시 실행해 주세요." 안내 후 종료
  - 단, 사용자가 "여기서 그냥 만들어"라고 명시했다면 그대로 진행

### 2. 워킹 디렉토리 상태 확인

`git status --short`로 미커밋 변경이 있는지 확인한다.

- 변경 없음 → 진행
- 변경 있음 → 사용자에게 알리고 진행 여부를 `AskUserQuestion`으로 묻는다.
  - 옵션 1: `그대로 진행 (Recommended)` — worktree 생성은 메인 워킹 디렉토리에 영향 없음
  - 옵션 2: `중단`

worktree 생성은 메인의 워킹 트리를 건드리지 않으므로 기본은 진행이다. 단지 사용자에게 사실을 한 번 알리는 의미.

## 입력 결정

### 1. worktree 디렉토리 경로 결정

현재 메인 worktree의 절대 경로를 `git rev-parse --show-toplevel`로 얻고, 그 부모 디렉토리에서 `<repo-name>-N` 형식의 다음 번호를 자동으로 정한다.

- 예: 메인이 `/Users/olaf/dev/heydealer-android`면 `/Users/olaf/dev/heydealer-android-2`부터 검사
- 이미 `-2`가 존재하면 `-3`, ... 순으로 비어 있는 첫 번호를 사용

### 2. 브랜치 결정

`$ARGUMENTS`가 비어 있으면 `AskUserQuestion`으로 묻는다.

- `question`: `worktree에 사용할 브랜치 이름을 입력해 주세요`
- `header`: `브랜치 선택`
- `multiSelect`: `false`
- `options`:
  1. `현재 브랜치에서 새 브랜치 생성` / `현재 브랜치를 base로 새 브랜치를 만든다`
  2. `develop에서 새 브랜치 생성` / `develop을 base로 새 브랜치를 만든다`
  3. `기존 브랜치 체크아웃` / `이미 존재하는 원격/로컬 브랜치를 그대로 사용한다`

옵션 선택 후 `Other`로 직접 입력받은 브랜치 이름을 사용한다. `$ARGUMENTS`로 직접 들어온 경우 이 단계를 생략한다.

### 3. base-branch 결정 (신규 브랜치인 경우)

- `$ARGUMENTS`로 base가 지정되었으면 그대로 사용
- 미지정 시 `git ls-remote --heads origin develop main master` 결과에서 존재하는 첫 번째 브랜치를 선택
- 기존 브랜치를 체크아웃하는 경우 base는 무시

## 충돌 검증

브랜치 결정 직후, `git worktree add` 호출 전에 충돌을 사전 감지한다. raw 에러 메시지 대신 명확한 안내를 위함이다.

### 기존 브랜치 체크아웃 분기

해당 브랜치가 다른 worktree에서 이미 체크아웃되어 있는지 확인한다:

```bash
git worktree list --porcelain | awk -v b="refs/heads/<branch-name>" '/^worktree /{wt=$2} $1=="branch" && $2==b {print wt; exit}'
```

출력이 비어 있지 않으면 다음을 안내하고 종료한다:

> 이 브랜치는 `<출력된 worktree path>`에서 이미 사용 중입니다. 다른 브랜치를 선택하거나 해당 worktree를 먼저 정리해 주세요.

### 신규 브랜치 생성 분기

같은 이름의 로컬 브랜치가 이미 존재하는지 확인한다:

```bash
git rev-parse --verify --quiet "refs/heads/<branch-name>"
```

종료 코드 0이면 동명 브랜치가 이미 있다는 뜻이다. `AskUserQuestion`으로 옵션을 제시한다:

- 옵션 1: `기존 브랜치 체크아웃으로 전환` — 신규 생성 대신 그 브랜치를 그대로 사용 (이후 위 "기존 브랜치 체크아웃 분기" 검증 다시 수행)
- 옵션 2: `다른 이름 입력` — `Other`로 새 이름 받아 다시 검증
- 옵션 3: `중단`

## 실행

### 1. worktree 생성

신규 브랜치인 경우:

```bash
git worktree add -b <branch-name> <worktree-path> <base-branch>
```

- 예: `git worktree add -b feature/HDA-12345-bug-fix /Users/olaf/dev/heydealer-android-2 develop`

기존 브랜치 체크아웃인 경우:

```bash
git worktree add <worktree-path> <branch-name>
```

- 원격에만 있는 브랜치라면 `git worktree add --track -b <branch-name> <worktree-path> origin/<branch-name>` 형태로 트래킹 브랜치를 함께 만든다.

`git worktree add` 실패 시 에러 메시지를 그대로 노출하고 종료한다.

### 2. 서브모듈/.claude/.agent 초기화

worktree가 생성되면 다음 스크립트를 호출한다:

```bash
~/.claude/skills/create-worktree/init.sh <worktree-path>
```

스크립트는 다음을 idempotent하게 처리한다(같은 worktree에 재실행해도 기존 항목 덮어쓰기 금지):

1. **서브모듈 초기화** — 메인 worktree에 `.gitmodules`가 있을 때만 `git submodule update --init --recursive`를 실행. 실패해도 다음 단계는 계속 진행하며, 수동 재시도 명령을 함께 출력한다.
2. **`.claude/` 디렉토리** — `<worktree>/.claude/`가 없으면 생성, 있으면 skip.
3. **`.claude/rules/` 복제** — 메인 `.claude/rules/` 항목을 새 worktree로 복제한다.
   - **심볼릭 링크**: `readlink`로 원본 타깃을 읽어 같은 타깃 링크를 만든다. 메인이 `~/.android-ai-prompts/rules/...` 같은 절대 경로 링크를 쓰면 그대로 보존된다.
   - **일반 파일/디렉토리**: `cp -R`로 복사.
   - **충돌 시 skip**: 같은 이름이 이미 있으면 덮어쓰지 않고 skip.
   - **broken link 검출**: 링크 생성 후 target이 실재하지 않으면 `broken link: <name> -> <target>` 경고를 별도로 출력.
4. **`settings.local.json`** — 메인에 있고 worktree에 없을 때만 복사. worktree에 이미 있으면 덮어쓰지 않고 skip하며 "메인의 settings.local.json과 다를 수 있음" 경고를 출력.
5. **`.agent/` 심볼릭 링크** — `<worktree>/.agent`를 메인의 `.agent/`로 향하는 symlink로 만든다. spec/plan(`.agent/specs/`, `.agent/plans/`)을 모든 worktree에서 같은 메인 디렉토리로 공유하기 위함이다.
   - 메인에 `.agent/`가 없으면 `.agent/specs/`, `.agent/plans/`까지 함께 신규 생성한 뒤 link한다.
   - worktree에 이미 `.agent`가 존재하면 skip (이미 symlink면 target만 출력, 일반 디렉토리면 그대로 둔다).
   - broken symlink면 경고만 출력하고 진행한다.

메인 `.claude/` 직속의 그 외 항목(사용자 메모, 로컬 스크립트 등)은 자동 복사하지 않는다. 사용자에게 발견 사실만 보고하고 결정은 위임한다.

### 3. 결과 보고

스크립트가 출력한 요약(서브모듈, `.claude/`·`rules/`·`settings.local.json`·`.agent/` 초기화 결과, skip된 항목, broken link 경고)을 그대로 사용자에게 전달한다. 추가로 다음을 함께 안내한다.

- 생성된 worktree 경로와 브랜치
- 충돌 검증 결과 — 사전 감지하여 차단한 충돌이 있었으면 무엇이었는지
- 다음 행동 제안: `cd <worktree-path>`로 이동하여 작업 시작

## 예시

| 메인 | 인자 | worktree 경로 | 브랜치 |
|------|------|--------------|--------|
| `/Users/olaf/dev/heydealer-android` | `feature/HDA-12345-x` | `/Users/olaf/dev/heydealer-android-2` | 신규 `feature/HDA-12345-x` (base develop) |
| `/Users/olaf/dev/heydealer-android` (이미 -2 존재) | `feature/HDA-67890-y develop` | `/Users/olaf/dev/heydealer-android-3` | 신규 `feature/HDA-67890-y` (base develop) |
| `/Users/olaf/dev/revolt-android` | `release/26.05.01` | `/Users/olaf/dev/revolt-android-2` | 기존 원격 브랜치 체크아웃 |

## 주의사항

- **메인 워킹 트리 변경 금지**: 메인 worktree의 파일을 수정하거나 커밋하지 않는다.
- **이미 사용 중인 브랜치**: git은 같은 브랜치를 두 worktree에서 동시에 체크아웃할 수 없다. "충돌 검증" 단계에서 사전 감지하여 어떤 worktree가 점유 중인지 안내한 뒤 종료한다.
- **`.claude/`는 .gitignore 대상**: worktree 생성만으로는 자동 복제되지 않는다. 본 스킬이 명시적으로 초기화한다.
- **`.agent/`는 메인과 공유한다**: spec/plan(`.agent/specs/`, `.agent/plans/`)은 worktree마다 따로 두지 않고 symlink로 메인 디렉토리를 가리키게 한다. worktree에서 작성한 spec/plan을 메인 및 다른 worktree에서도 그대로 읽고 갱신할 수 있다.
- **사용자가 명시한 경로/이름이 있으면 자동 결정 로직보다 우선**한다.
