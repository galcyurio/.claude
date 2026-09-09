---
name: create-pr
effort: medium
allowed-tools: Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git remote:*), Bash(git ls-remote:*), Bash(git status:*), Bash(git push:*), Bash(grep:*), mcp__claude_ai_Atlassian__getAccessibleAtlassianResources, mcp__claude_ai_Atlassian__getJiraIssue, Bash(gh pr create:*), Read, AskUserQuestion
description: PR 생성 (간결한 본문 + 복잡한 경우 mermaid 다이어그램). 사용자가 'create-pr', 'PR 생성', 'PR 만들어', 'PR 만들어줘', 'PR 작성', 'PR 올려줘', 'PR 올려', 'pull request 생성', 'pull request 만들어', '풀리퀘 생성', '풀리퀘 만들어' 등 PR 생성을 요청할 때 이 스킬을 사용해야 한다. PR 리뷰/조회 요청에는 사용하지 않는다.
---

## Context

- Current branch: !`git branch --show-current`
- Remote URL: !`git remote get-url origin`

## Your task

### 0. 사전 검증
`git status`로 워킹 디렉토리 상태를 확인합니다.

- **커밋되지 않은 변경사항이 있는 경우**: 사용자에게 알리고 종료
  - "커밋되지 않은 변경사항이 있습니다. 먼저 커밋한 후 다시 PR 생성을 실행해주세요."
- **remote에 push되지 않은 커밋이 있는 경우** (`git ls-remote --heads origin <branch>`로 remote 브랜치 존재 확인 후, 있으면 `git log origin/<branch>..HEAD`, 없으면 신규 브랜치로 간주):
  - 확인 없이 `git push`를 실행한 후 계속 진행한다. (이 스킬에 진입한 것 자체가 push 동의를 의미하므로 별도로 묻지 않는다)

### 1. 기본 정보 추출
- 브랜치 이름에서 JIRA 티켓 ID 추출 (예: `feature/HDA-20017-*` → HDA-20017). 없으면 사용자에게 알리고 종료
- owner/repo는 `gh`가 현재 디렉토리의 origin remote로 자동 감지하므로 별도 추출하지 않는다

### 2. JIRA 티켓 조회
- `mcp__claude_ai_Atlassian__getAccessibleAtlassianResources`로 cloudId 가져오기
- `mcp__claude_ai_Atlassian__getJiraIssue`로 티켓 조회 (반드시 `fields: ["summary", "description", "parent"]` 명시)
- **인증 실패 시**: develop으로 임의 진행하지 말고, AskUserQuestion으로 **base 브랜치를 사용자에게 확인**한다.
  - 후보 제시: `develop` + `git branch -r | grep "origin/feature-base/"` 목록. 사용자가 고른 브랜치를 base로 3번 단계를 건너뛰고 진행한다. (PR 제목은 세션에서 확보한 summary나 사용자 입력을 사용)
  - 사용자가 재인증을 택하면 "'/mcp'로 JIRA를 재인증한 후 다시 '/pr'을 실행해주세요" 출력 후 종료한다.

### 3. base 브랜치 결정

| 조건 | base |
|------|------|
| 사용자 지정 | 지정 브랜치 |
| JIRA 에픽 있음 | `git branch -r \| grep "origin/feature-base/{EPIC-KEY}"` 결과로 결정 (0개→develop, 1개→해당 브랜치, 여러개→사용자 선택) |
| 그 외 | develop |

### 4. PR 본문 작성

#### 작성 원칙 (필수)

- 마크다운 형식으로 작성한다.
- **기본 본문은 최소형이다.** 아래 두 섹션만 쓰고, 나머지(작업사항·다이어그램 등)는 "예외일 때만 추가"한다. 단 **스냅샷 이미지가 커밋돼 있으면 `## 반영화면`은 항상 채운다** (아래 "반영화면 작성 기준").

   ```markdown
   ## 개요
   <왜 이 변경이 필요한가 — 1~2문장>

   ## 관련 채널 내용
   <Jira 본문에서 추출한 링크 — 있을 때만>
   ```

- **개요는 1~2문장**으로 "왜 이 변경이 필요한가"만 적는다. 구현 방식·레이어·필드명은 본문에 적지 않는다.
- **템플릿에 없는 섹션을 임의로 만들지 않는다.** `## 기타`·`## 변경 이유` 등 AI가 덧붙이는 섹션은 금지.
- **커밋 메시지와 중복 금지**: 커밋 제목/메시지를 PR 본문에 나열하지 않는다. 리뷰어는 커밋 목록을 별도로 본다. PR 본문은 "커밋 히스토리로는 보이지 않는 맥락"만 담는다.
- **구어체로 작성**: PR 본문 문장은 `~합니다` 체로 작성한다. `~한다` 같은 평서형 문어체는 사용하지 않는다.
   - 예: `~ 문제를 해결한다.` → `~ 문제를 해결합니다.`
- **작업사항·mermaid는 예외일 때만 추가한다.** 기본은 생략. 추가 기준은 아래 "작업사항·mermaid 추가 기준" 참고. 애매하면 생략한다.
- **반영화면은 스냅샷이 있으면 채운다.** 스냅샷 이미지가 이번 브랜치에 커밋돼 있으면 그것을 `## 반영화면`에 넣고, 이미 있던 스냅샷이 변경된 경우에는 Before/After 표로 넣는다. 작성 방법은 아래 "반영화면 작성 기준" 참고.

#### 반영화면 작성 기준

이번 브랜치가 **스냅샷 이미지를 추가·변경했으면** 그 이미지를 `## 반영화면`에 넣는다. 캡처를 새로 요청하거나 실기기 스크린샷을 대신 올리지 않는다 — 스냅샷은 이미 커밋에 들어 있어 코드와 함께 갱신되므로 PR 본문이 낡지 않는다.

1. 대상 이미지와 변경 유형을 함께 찾는다. `A`는 이번에 새로 추가된 스냅샷이고, `M`은 이미 있던 스냅샷이 변경된 경우다.

   ```bash
   git diff --name-status --diff-filter=AM {base}...HEAD -- '*/src/test/screenshots/*'
   ```

2. 각 이미지 URL은 **커밋 SHA로 고정**한다. 브랜치 이름을 ref로 쓰면 이름 안의 슬래시가 경로와 섞여 링크가 깨지고, 이후 force push로 그림이 바뀐다.

   ```
   https://github.com/{owner}/{repo}/raw/{SHA}/{경로}
   ```

   | 이미지 | SHA를 구하는 명령 |
   | --- | --- |
   | After (변경 후) | `git rev-parse HEAD` |
   | Before (변경 전) | `git merge-base {base} HEAD` |

   Before에 merge-base 커밋을 쓰는 이유는, 1번의 3점 diff가 바로 이 커밋을 기준으로 비교하기 때문이다. 이 링크는 push된 커밋에만 유효한데, After는 0번 단계에서 push를 먼저 하므로 순서가 어긋나지 않고 Before는 base 브랜치에 이미 올라가 있는 커밋이다.

3. 표의 모양은 **기존 스냅샷이 변경됐는지(`M`)** 에 따라 달라진다. 열 제목이나 행 제목으로 쓰는 상태 이름은 두 경우 모두 Preview 함수명을 그대로 쓰지 않고 **사람이 읽을 이름**으로 적는다 (`Preview` → 입력 전, `PreviewUsed` → 사용 완료).

   - **`A`만 있는 경우** (스냅샷이 이번 브랜치에서 처음 생겼다): 비교할 이전 상태가 없으므로 상태를 한 줄로 나열한다.

     ```markdown
     | 입력 전 | 사용 완료 |
     | --- | --- |
     | <img width="280" src="{HEAD SHA}/..."> | <img width="280" src="{HEAD SHA}/..."> |
     ```

   - **`M`이 하나라도 있는 경우**: Before/After를 열로 두고 상태를 행으로 나열해서, 리뷰어가 같은 상태의 변경 전후를 나란히 볼 수 있게 한다. 상태를 열로 두면 한 행에 이미지가 4개 이상 들어가 본문 폭을 넘기므로 이 방향을 뒤집지 않는다.

     ```markdown
     | 상태 | Before | After |
     | --- | --- | --- |
     | 입력 전 | <img width="280" src="{merge-base SHA}/..."> | <img width="280" src="{HEAD SHA}/..."> |
     | 사용 완료 | (신규) | <img width="280" src="{HEAD SHA}/..."> |
     ```

     같은 표에 `A` 이미지가 섞여 있으면 그 행의 Before 칸에는 `(신규)`라고 적는다. 존재하지 않는 변경 전 이미지를 임의로 채워 넣거나, 그 행을 표에서 빼지 않는다.

4. 폭은 `width="280"`을 기본으로 둔다. 원본 크기로 넣으면 본문이 화면을 넘긴다.

스냅샷이 없으면 이 섹션을 제거한다. 화면이 바뀌었는데 스냅샷이 없는 경우에도 임의로 캡처해 채우지 않고, 섹션을 비운 채 사용자에게 캡처를 붙일지 물어본다.

#### 작업사항·mermaid 추가 기준

`## 작업사항` 섹션은 **개요만으로 리뷰어가 변경 흐름을 이해할 수 없을 때만** 추가한다.

| 상황 | 본문 |
|------|------|
| 개요 1~2문장으로 충분 (단순 추가, DTO/레이어 배선, 이름 정리, 버그 픽스) | 작업사항 **생략** |
| 흐름이 있으나 글로 충분 | bullet 1~3개 |
| 화면/상태 전환·호출/데이터 흐름·모듈 구조 변경이 **리뷰의 핵심**이고 글로 설명이 어려움 | mermaid (`flowchart`/`stateDiagram`/`sequenceDiagram`/`classDiagram`) |

**애매하면 생략한다.** DTO/레이어 매핑처럼 기계적으로 자명한 흐름은 mermaid로 그리지 않는다.

#### before/after 비교

변경 전/후 구조나 흐름을 mermaid로 비교할 때는 **반드시 별도의 mermaid 블록 2개로 분리**하여 작성한다. 하나의 블록에 `subgraph`나 좌/우 배치로 합치지 않는다.

- 각 블록 위에 `**Before**`, `**After**` 헤더를 붙여 구분한다.
- Before/After 블록은 동일한 다이어그램 유형(flowchart/sequenceDiagram 등)과 동일한 방향(LR/TD 등)을 사용해 비교하기 쉽게 한다.

예시:

~~~markdown
**Before**

```mermaid
flowchart LR
    A[결제 요청] --> B[완료]
```

**After**

```mermaid
flowchart LR
    A[결제 요청] --> B{성공?}
    B -->|Yes| C[완료]
    B -->|No| D[재시도]
```
~~~

#### 좋은 예 / 나쁜 예

**나쁜 예 1** (커밋 메시지 나열, 장황, 중복):

```markdown
## 개요
HDA-20017 이슈에 따라 이용약관 버튼을 추가합니다. 사용자가 로그인 화면에서 이용약관을 확인할 수 있도록 버튼을 추가하고, 클릭 시 이용약관 화면으로 이동하도록 합니다. 또한 이용약관 화면에서 뒤로가기 시 로그인 화면으로 돌아오도록 합니다.

## 작업사항
- feat: 이용약관 버튼 추가
- feat: 이용약관 화면 네비게이션 추가
- refactor: LoginViewModel 정리
- test: 버튼 클릭 테스트 추가
```

**나쁜 예 2** (자명한 DTO/레이어 흐름을 mermaid로 그리고, 코드로 보이는 구현·범위를 `## 기타`로 덧붙임):

~~~markdown
## 개요
서버에 필터 API가 추가됨에 따라 앱이 두 필터 값을 주고받도록 API/DTO 레이어를 추가합니다.

## 작업사항

```mermaid
flowchart LR
    Response --> Entity --> Domain --> Model
```
- 응답에서 옵션 목록을 받아 전 레이어로 전달합니다.

## 기타
- 서버 배포 전 nullable + 빈 목록 폴백으로 처리했습니다.
- 컴포넌트 이름 정리(AccidentType* → AccidentRepairsSummary*)뿐입니다.
~~~

**좋은 예 — 기본 (최소형)** — 위 "나쁜 예 2"를 이 형태로 줄인다:

```markdown
## 개요
API 변경사항을 반영합니다.

## 관련 채널 내용
https://...
```

**좋은 예 — 예외 (mermaid 사용)** — 화면/흐름/구조 변경이 리뷰의 핵심일 때만:

~~~markdown
## 개요
결제 실패 시 재시도 플로우가 없던 문제를 해결합니다. 재시도 3회 초과 시 고객센터 안내로 분기합니다.

## 작업사항

```mermaid
flowchart LR
    A[결제 요청] --> B{성공?}
    B -->|Yes| C[완료]
    B -->|No| D[재시도 화면]
    D -->|< 3회| A
    D -->|>= 3회| E[고객센터 안내]
```
~~~

### 5. PR 생성
1. PR 템플릿 읽기 (`.github/PULL_REQUEST_TEMPLATE.md`)
2. JIRA 본문에서 링크 추출 (Figma, Slack 등)
3. 템플릿 섹션 채우기:
   - "## 개요": 4번 전략으로 작성 (필수)
   - "### 디자인 화면": Figma 링크 있을 때만
   - "### 관련 채널 내용": 관련 링크 있을 때만
   - "## 작업사항": 4번 "작업사항·mermaid 추가 기준"에 해당할 때만 추가 (기본 생략)
   - "## 반영화면": 이번 브랜치가 스냅샷 이미지를 추가·변경했으면 4번 "반영화면 작성 기준"대로 채움
   - 비어있는 섹션은 제거
4. PR 본문을 임시 markdown 파일로 저장한다 (예: `/tmp/pr-body-{티켓ID}.md`).
   - 본문에 mermaid·백틱·대괄호가 포함되므로 `--body`에 인라인하지 않고 **반드시 `--body-file`로 전달**한다. (`--body "..."`에 백틱을 넣으면 셸 명령 치환으로 깨진다)
5. `gh pr create`로 PR을 생성한다:
   - `--title "{티켓ID} {JIRA summary}"` — **반드시 JIRA summary 필드 값을 그대로 사용** (요약/가공/의역 금지)
   - `--base {3번에서 결정한 브랜치}`
   - `--head {현재 브랜치}`
   - `--body-file {4번 임시 파일}`
   - `--assignee @me` — assignee를 본인으로 설정 (`gh`는 `@me`를 현재 인증 사용자로 해석)

## 예시

| 상황 | 브랜치 | base | PR 제목 |
|------|--------|------|---------|
| 에픽 있음 | feature/HDA-20017-agreement-button | feature-base/HDA-20000-agreement | HDA-20017 [고객][이용약관] 이용약관 버튼 추가 |
| 에픽 없음 | feature/HDA-20018-notification-fix | develop | HDA-20018 알림 버그 수정 |

## 중요
- 사용자 명시 요청 시 해당 내용 우선
- **JIRA 인증 실패 시 절대 임의 진행 금지 — 반드시 사용자에게 확인**
