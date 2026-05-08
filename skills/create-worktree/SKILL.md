---
name: create-worktree
description: git worktree를 추가하고 서브모듈/.claude 초기화까지 한 번에 처리하는 스킬. 사용자가 'create-worktree', 'worktree 만들어', 'worktree 추가', '워크트리 만들어', '워크트리 생성', '병렬 작업 환경 만들어줘', '새 worktree' 등 worktree 생성을 요청할 때 이 스킬을 사용해야 한다. worktree 삭제/조회 요청에는 사용하지 않는다.
argument-hint: "[branch-name] [base-branch]"
---

## 역할

현재 git 저장소에서 새 worktree를 생성하고, 서브모듈과 `.claude/` 환경까지 새 worktree에서 즉시 작업 가능한 상태로 초기화한다.

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

### 2. 서브모듈 초기화

메인 worktree의 `.gitmodules` 존재 여부를 먼저 확인한다.

- `.gitmodules`가 없으면 이 단계를 건너뛴다.
- 있으면 새 worktree로 이동(`cd <worktree-path>`) 후 다음을 순서대로 실행한다:

```bash
git submodule update --init --recursive
```

서브모듈이 여러 개거나 깊은 트리인 경우에도 `--recursive`로 전부 처리한다.

명령 실패 시 에러를 그대로 노출하고, 후속 단계인 `.claude/` 초기화는 계속 진행한다. 사용자가 즉시 수동 재시도할 수 있도록 다음 안내를 함께 출력한다:

> 서브모듈 초기화에 실패했습니다. `.claude/` 초기화는 계속 진행합니다.
> 수동 재시도:
>   cd <worktree-path>
>   git submodule update --init --recursive

### 3. `.claude/` 초기화

메인 worktree의 `<main>/.claude/`를 참조하여 새 worktree의 `<worktree-path>/.claude/`를 구성한다.

모든 sub-step은 **idempotent**하게 동작한다. 같은 worktree 경로에 재실행해도 기존 항목을 덮어쓰지 않고, 누락된 항목만 채운 뒤 결과 보고에 "skipped"로 기록한다.

#### 3-1. `.claude/` 자체

- 새 worktree에 `.claude/` 디렉토리가 없으면 생성한다. 이미 있으면 skip.

#### 3-2. `.claude/rules/`

메인의 `.claude/rules/` 안에 있는 항목을 그대로 새 worktree에 복제한다. **새 worktree에 같은 이름의 항목이 이미 있으면 skip하고 결과 보고에 "skipped"로 기록한다(기존 항목 덮어쓰기 금지).**

- **심볼릭 링크**: `readlink`로 원본 타깃을 읽어 새 worktree의 같은 위치에 동일 타깃을 가리키는 심볼릭 링크를 만든다. 메인이 `~/.android-ai-prompts/rules/...` 형태의 절대 경로 링크를 쓰므로 그대로 사용한다.
  - **target 실재 검증**: 링크 생성 직전에 `[ -e <target> ]`로 target 존재를 확인한다. target이 실재하지 않으면 링크는 만들되 결과 보고에 `broken link: <link path> -> <target> (target 부재)` 경고를 추가한다(silent failure 방지).
- **일반 파일/디렉토리**: 발견되면 `cp -R`로 복사한다.
- 메인에 `.claude/rules/`가 없으면 이 단계를 건너뛴다.

#### 3-3. `.claude/plans/`

새 worktree에 `.claude/plans/` 빈 디렉토리를 만든다. 이미 있으면 skip하고 내부 plan 파일은 그대로 둔다. 메인의 plan 파일은 복사하지 않는다(plan은 worktree별 작업 단위).

#### 3-4. `.claude/settings.local.json`

메인에 `settings.local.json`이 있으면 그대로 새 worktree로 복사한다. 없으면 생성하지 않는다. **새 worktree에 이미 `settings.local.json`이 있으면 덮어쓰지 않고 skip하며, 결과 보고에 "메인의 settings.local.json과 다를 수 있음" 경고를 추가한다.**

#### 3-5. 그 외 메인 `.claude/` 항목

메인 `.claude/` 직속의 다른 파일/디렉토리(예: 사용자가 별도로 둔 메모, 로컬 스크립트)는 자동 복사하지 않는다. 사용자에게 발견 사실만 보고하고 결정은 위임한다.

### 4. 결과 보고

다음 정보를 사용자에게 출력한다.

- 생성된 worktree 경로와 브랜치
- 충돌 검증 결과 — 사전 감지하여 차단한 충돌이 있었으면 무엇이었는지
- 서브모듈 초기화 결과 (수행/생략/실패 — 실패 시 수동 재시도 명령 함께)
- `.claude/` 초기화 결과
  - 복제된 rules 항목 목록 (`common`, `heydealer` 등)
  - **이미 존재해서 skip된 항목 목록** (재실행 시)
  - **broken symlink 경고 목록** (target 부재인 링크가 있었던 경우)
  - `plans/` 생성/skip 여부
  - `settings.local.json` 복사/skip 여부 (skip 시 메인과 다를 수 있음 경고)
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
- **plans는 복사하지 않는다**: worktree는 새 작업 단위이므로 메인의 진행 중인 plan을 함께 가져가면 혼동을 유발한다.
- **사용자가 명시한 경로/이름이 있으면 자동 결정 로직보다 우선**한다.
