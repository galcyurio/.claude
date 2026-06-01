---
name: review-by-agents
description: "코드 변경사항을 여러 에이전트 관점(Logic, Convention, Security, Architecture)에서 병렬 리뷰하는 스킬. 사용자가 'review-by-agents', '코드 리뷰', '에이전트 리뷰', 'code review', '리뷰해줘', 'PR 리뷰해줘', '변경사항 리뷰', '코드 검토', '멀티 에이전트 리뷰', '병렬 리뷰' 등 코드/PR 리뷰를 요청할 때 이 스킬을 사용해야 한다. 단순 PR 조회나 보안 전용 리뷰(security-review 스킬 사용)에는 사용하지 않는다."
argument-hint: "[PR URL, 파일 경로, 또는 생략(현재 변경사항)]"
---

# Review by Agents - 병렬 에이전트 코드 리뷰

코드 변경사항을 여러 에이전트 관점에서 동시에 리뷰하는 읽기 전용 스킬이다. 코드를 수정하지 않으며, 발견된 이슈는 제안으로만 제공한다.

## 입력 형태

| 입력 형태 | 처리 |
|-----------|------|
| 인자 없음 | 현재 브랜치의 base 대비 diff (base 브랜치 자동 감지) |
| PR URL | `gh pr diff <number>` |
| 파일 경로 | 해당 파일 전체 리뷰 |

---

## 워크플로우

### 1단계: 입력 파싱 및 diff 추출

인자 유형을 판별한다:
- `github.com` 또는 `github.com/.../pull/` 패턴 → PR 모드: PR 번호 추출 후 `gh pr diff <number>`
- 파일 경로로 존재하는 경우 → 파일 모드: 해당 파일을 Read로 읽음
- 인자 없음 → 현재 변경사항 모드

인자 없음일 때 base 브랜치 자동 감지:
1. `gh pr view --json baseRefName`으로 현재 브랜치에 연결된 PR의 base 브랜치 확인
2. PR이 없으면 `git remote show origin`에서 HEAD branch 사용
3. `git diff <base>...HEAD`로 diff 추출

diff가 비어있으면 "리뷰할 변경사항이 없습니다"를 출력하고 종료한다.

diff가 3000행을 초과하면 사용자에게 파일 단위 분할 리뷰를 제안하고 진행 여부를 확인한다.

### 2단계: 외부 링크 컨텍스트 수집 (PR 모드만)

`gh pr view --json body`로 PR 본문을 가져온다.

본문에서 외부 링크를 추출하고, `~/.claude/rules/external-links.md` 규칙에 따라 각 링크에서 관련 정보를 수집한다.

수집된 정보를 요약하여 에이전트 프롬프트의 CONTEXT에 전달한다.

Figma 링크(`figma.com/design/`)가 포함되어 있으면 Designer 에이전트를 스폰할 대상으로 표시한다.

**디자인 변경 감지 시 Figma 링크 확보 (fallback 체인)**:

적용 모드는 **diff가 존재하는 모드(PR 모드 + 현재 변경사항 모드)**다. 파일 모드는 diff가 없어 디자인 변경 판정이 어려우므로 건너뛴다.

먼저 diff가 **디자인 관련 변경**(화면에 드러나는 색상·간격·크기·레이아웃·타이포·컴포넌트 등 시각 요소의 신규·변경)을 포함하는지 판단한다. 순수 로직·데이터 변경만 있으면 "디자인 변경 없음"으로 본다.

디자인 변경이 **없으면** 이 fallback을 건너뛴다. 디자인 변경이 **있는데 PR 본문에서 Figma 링크를 확보하지 못했으면**, 먼저 0번으로 이슈 정보를 확보한 뒤 1~3번을 **순서대로** 시도하고 **링크를 하나라도 확정하면 즉시 중단**한다. **frame 단위로 좁혀진 링크를 페이지 단위 링크보다 항상 우선**한다.

**0. 사전 — 이슈 ID·epic_key·폴백 링크 확보 (공통 전제)**

이슈 ID는 PR 제목·본문 → 브랜치명(`git rev-parse --abbrev-ref HEAD`) → 최근 커밋 메시지에서 `{PROJECT}-{번호}`(예 `HDA-21304`) 패턴으로 추출한다. `mcp__claude_ai_Atlassian__getJiraIssue(issueIdOrKey, fields=["summary","description","comment","parent","issuetype"], responseContentFormat="markdown")`와 `mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks`를 호출해 다음을 동시에 확보한다:

- **epic_key**: 이슈타입이 Epic이면 그 이슈 ID, subtask·story면 `parent` 이슈 ID (1번 feature-memory 조회 키)
- **이슈 컨텍스트**: `summary`(제목)·description — 1번 frame 자동 매칭의 신호로 사용
- **Jira 페이지 링크(폴백용)**: description·comment·웹 링크의 `figma.com/design/`·`figma.com/board/` URL. 보통 Epic 페이지 단위라 범위가 넓다 → 2번 폴백에서만 사용

**1. feature-memory frame 좁히기 (최우선)** — feature-memory는 Epic의 Figma 페이지를 직계 자식 frame 단위로 라벨링해 `## 📚 Reference`의 `Figma frame 목록` 표에 저장해 둔다. 0번의 epic_key로 `mcp__claude_ai_Notion__notion-search` → 페이지가 있으면 `mcp__claude_ai_Notion__notion-fetch(page_id)`로 본문을 받아 그 표를 찾는다.

   - **`Figma frame 목록` 표가 있으면**: 표의 각 행(`이름` · `크기` · `[Figma](node-id 링크)`)을 파싱한 뒤, 리뷰 대상 이슈와 연관된 frame을 **자동 매칭**한다. 매칭 신호는 ① frame 이름 키워드 ↔ 이슈 `summary`·description, ② frame 이름 ↔ 변경된 화면/컴포넌트 파일명, ③ frame 이름 ↔ diff에 등장하는 UI 텍스트·컴포넌트명이다.
     - **정확히 1개로 좁혀지면** → 그 frame 링크를 Figma 링크로 확정한다 (페이지 전체가 아닌 frame 단위로 Designer에 전달). 즉시 중단.
     - **0개거나 2개 이상이면** → `AskUserQuestion`으로 후보 frame 이름들을 옵션으로 제시(2개 이상이면 매칭된 후보 우선, 0개면 표 전체에서)하고 사용자가 리뷰할 frame을 고르게 한다. 선택된 frame 링크를 확정하고 중단한다. 사용자 응답 전에는 2번으로 넘어가지 않는다.
   - **`Figma frame 목록` 표가 없으면**(feature-memory 미등록이거나 frame 목록 미생성) → 좁히기를 적용하지 않고 2번으로 폴백한다. feature-memory의 `## 한눈에 보기` 페이지 링크는 2번 Jira 링크와 동일한 Epic Figma를 가리키므로 따로 쓰지 않는다.

**2. Jira 페이지 링크 (폴백)** — 0번에서 확보한 Jira Figma 링크가 있으면 그대로 채택한다. frame 좁히기는 적용되지 않으며 Designer가 Epic 페이지 전체를 검토하게 된다. 링크가 없으면 3번으로.

**3. 사용자에게 요청** — 1·2 모두 실패하면 `AskUserQuestion`으로 묻는다. 질문은 "디자인 변경이 감지됐지만 Figma 링크를 찾지 못했습니다. 어떻게 진행할까요?", 옵션은 ① `Figma 링크 제공`(링크는 Other 또는 후속 메시지로 받음) ② `링크 없이 리뷰 진행`. **사용자 응답을 받기 전에는 3단계 에이전트 스폰으로 넘어가지 않는다.**

확보 결과를 다음 단계에 넘긴다:

- Figma 링크 확보(출처 무관) → Designer 스폰 대상으로 표시한다. **frame 단위로 좁혀진 경우(1번)** 페이지가 아닌 그 frame 링크를, 페이지 단위(2번·사용자 제공)면 그 링크를 그대로 전달한다.
- 디자인 변경 있음 + 사용자가 "링크 없이 진행" 선택 → `디자인 변경 감지됨 · Figma 없음`으로 기록한다(3·6단계에서 사용).

**TODO·후속 작업·시리즈 PR 컨텍스트 추출**:

diff와 PR 본문에서 아래 신호들을 추출해 에이전트 프롬프트의 CONTEXT 섹션에 별도 블록으로 정리해 전달한다. 에이전트가 "보고 제외 기준"을 정확히 적용할 수 있도록 미리 사실관계를 명시해주는 단계다.

- diff 내 `// TODO`, `// FIXME` 주석에 포함된 후속 이슈 ID·PR 번호
- PR 본문의 "후속 PR", "다음 PR", "후속 이슈", "이번 PR은 …, …는 다음 PR에서" 같은 문구
- 시리즈 PR 표시 ("분할 PR의 N번째", "후속 PR로 완성", base 브랜치가 `feature-base/…`처럼 통합 브랜치인 경우)
- production 경로(`default()`, ViewModel 초기값 등)에 mock/sample 데이터가 들어 있고 그 옆에 후속 작업이 명시된 케이스

이 블록은 에이전트 프롬프트에 다음 형식으로 들어간다:

```
## CONTEXT — TODO / 후속 작업 / 시리즈 정보
- TODO 후속 이슈: HDA-XXXXX (파일:라인, "데이터 연결" 등 요지)
- PR 본문 명시: "실제 데이터 연결은 HDA-XXXXX 후속 PR" 등 원문 인용
- 시리즈 PR: base 브랜치 feature-base/... — 통합 브랜치 머지, 메인 직접 머지 아님
- production 경로 mock 데이터: MarketHomeUiState.default()에 PreviewMarketCarPreviewProvider 사용 → HDA-XXXXX로 정리 예정
```

이 컨텍스트가 명시되면 에이전트는 해당 항목을 "보고 제외 기준"에 따라 issue로 올리지 않아야 한다. 동일한 항목을 그래도 보고하려면 "면제 예외(빌드/보안취약점/데이터 유실)"에 정확히 해당함을 issue 본문에 근거로 적어야 한다.

### 3단계: 에이전트 병렬 스폰

아래 에이전트를 **동시에** Agent 도구로 스폰한다:

| 에이전트 | 관점 | 스폰 방식 | 조건 |
|----------|------|----------|------|
| Code Reviewer | Logic + Convention + Security | `model: "sonnet"` (subagent_type 생략) | 항상 |
| Oracle | Architecture | `subagent_type: "Oracle"` | 항상 |
| Designer | Design (Figma-구현 일치) | `subagent_type: "Designer"` | Figma 링크가 확보됐을 때 (출처: PR 본문 / Jira 이슈 / feature-memory / 사용자 제공). 디자인 변경이 감지됐으나 사용자가 "링크 없이 진행"을 택한 경우는 스폰하지 않음 |

각 에이전트에 아래 4섹션 구조의 프롬프트를 전달한다:

```
## REVIEW SCOPE
[diff 내용 또는 파일 내용]

## PERSPECTIVE
[관점별 체크리스트]

## CONTEXT
[외부 링크에서 수집한 정보 요약]
[변경 파일의 import, 함수 시그니처 등 주변 코드]

## OUTPUT FORMAT
아래 JSON 배열 형식으로만 출력하라. 이슈가 없으면 빈 배열 [].
[{
  "severity": "critical|warning|info",
  "perspective": "Logic|Convention|Security|Architecture|Design",
  "file": "파일 경로",
  "line": 라인번호,
  "issue": "이슈 설명 (한 문장)",
  "problem_code": "문제가 되는 원본 코드 스니펫 (1~5줄, 코드펜스 없이 본문만, 개행은 \\n). 핵심 라인 위주로 컴팩트하게 잘라낸다.",
  "language": "코드블록 언어 식별자 (예: ts, kt, py). 파일 확장자에서 추론하라.",
  "suggestion": "수정 제안 (한 문장 텍스트)",
  "suggestion_code": "선택 — 수정안 코드 스니펫 (코드펜스 없이 본문만). 단순 텍스트 제안으로 충분하면 필드를 생략하거나 빈 문자열."
}]

**개수 제한은 에이전트별로 다르다**:
- Code Reviewer / Oracle: **정말 중요한 것만 최대 3개**까지. 사소한 네이밍·스타일 지적은 제외하고, 실제 버그·보안 취약점·구조적 결함·사용자 영향이 큰 이슈 위주로 선별하라. 억지로 3개를 채우지 말고, 중요한 게 1개면 1개만 보고하라.
- Designer: **개수 제한 없음**. Figma 디자인과 구현의 모든 시각적 불일치를 보고하라. 코드 이슈의 Top 3 제한과는 완전히 별개다.

**보고 제외 기준 (모든 에이전트 공통)**:

다음에 해당하면 명백한 문제처럼 보여도 issue로 보고하지 않는다. 이런 항목은 의도된 임시 상태이고 후속 작업이 보장된 상태다.

- **TODO/FIXME 주석 + 후속 작업 명시**: 코드에 `// TODO`, `// FIXME` 등이 있고, 같은 주석이나 PR 본문에 후속 작업 위치가 명시된 경우 (예: `// TODO: HDA-21172에서 BottomSheet 연결`, PR 본문의 "후속 PR: #N", "이번 PR은 X만 추가, Y는 다음 PR에서").
- **명시적 placeholder/stub**: 함수 본문이 비어 있거나 stub 구현인데, 주석으로 "추후 구현", "다음 PR에서" 같이 의도가 분명히 표시된 경우.
- **시리즈 PR의 중간 단계**: PR 본문에서 "분할 PR의 N번째", "후속 PR로 완성" 같이 시리즈임을 명시한 경우.
- **production 코드 안 mock/sample 데이터 + 후속 데이터 연결 작업 명시**: UiState `default()`, ViewModel 초기값, 화면 미리보기용으로 임시 mock/sample 데이터를 production 경로에 박아뒀는데, 같은 위치 또는 PR 본문에서 실제 데이터 연결을 담당하는 후속 작업(이슈 ID/PR 번호)이 명시된 경우. mock UI가 사용자에게 잠시 보이는 것 자체는 "보안 취약점이 외부에 노출"이나 "데이터 유실/손상"에 해당하지 않으므로 제외 예외 사유로 끌어오지 않는다.

단, 다음은 위 면제에서 제외하고 정상 보고한다:
- 주석이 모호하거나 후속 작업 위치(이슈/PR 번호)가 명시되지 않은 경우. 단순 `// TODO`만 있고 어디에서 마무리될지 없는 경우 포함.
- 후속 작업 명시 여부와 무관하게 **이번 변경이 머지되는 순간 빌드/테스트가 깨지거나, 보안 취약점이 외부에 노출되거나, 데이터 유실/손상이 발생**하는 경우. 여기서 "보안 취약점 노출"은 시크릿/PII/공격 표면(인젝션·인증 우회 등)이 외부에 드러나는 좁은 의미이며, **mock UI 노출이나 잘못된 라벨 표기**는 포함되지 않는다. "데이터 유실/손상"도 DB 데이터/사용자 자산 손상·마이그레이션 깨짐 같은 영구적 손상으로 한정한다.
```

- `perspective` 값은 에이전트별로 다음을 사용한다:
  - Code Reviewer: `Logic`, `Convention`, `Security` 중 하나
  - Oracle: `Architecture`
  - Designer: `Design`
- `issue`는 간결한 한 문장으로 작성한다.
- `suggestion`은 코드 예시가 있으면 코드블록(` ``` `)을 포함하여 작성한다.

#### Code Reviewer 체크리스트

- **Logic**: 버그, null safety, 경계 조건, 에러 핸들링 누락, 레이스 컨디션
- **Convention**: 네이밍 일관성, 프로젝트 패턴, 코드 중복, 매직 넘버
- **Security**: 인젝션(SQL/XSS/SSRF), 인증/인가 우회, 민감정보 노출, 안전하지 않은 API 사용

#### Oracle 체크리스트

- 의존성 방향 위반, 레이어 위반, 단일 책임 위반, 불필요한 결합 도입

#### Designer 체크리스트

- Figma 디자인과 구현의 시각적 일치 여부 (컴포넌트, 레이아웃, 색상, 간격)

### 4단계: 결과 통합

에이전트 결과(JSON 배열)를 **두 그룹으로 분리**하여 처리한다:

- **코드 이슈 그룹**: Code Reviewer + Oracle (Logic, Convention, Security, Architecture)
- **디자인 이슈 그룹**: Designer (Design) — 별도 섹션으로 출력한다

각 그룹 공통 처리:

1. **중복 제거**: 같은 `file:line` 이슈는 심각도가 높은 쪽을 유지한다
2. **선별**:
   - 코드 이슈: **정말 중요한 것 최대 3개**만 남긴다 (Top 3). 억지로 채우지 않고, 중요한 게 1개면 1개만 남긴다
   - 디자인 이슈: **개수 제한 없음**. Designer가 보고한 이슈 전체를 그대로 출력한다. 코드 이슈의 Top 3 제한과 완전히 별개다
3. **정렬**: 심각도 내림차순 → `file` → `line` 오름차순

### 5단계: 오케스트레이터 판정

에이전트들의 리뷰가 모두 끝난 뒤, 오케스트레이터(스킬 호출자)가 통합된 결과를 종합해 **OKAY** 또는 **REJECT**를 결정한다. 이 단계는 에이전트가 아닌 오케스트레이터가 직접 수행한다.

**판정 규칙**:

- **❌ REJECT** — 다음 중 하나라도 해당:
  - Critical 이슈가 1건 이상 존재 (관점 무관: Logic/Convention/Security/Architecture/Design)
  - 머지/배포 시 즉시 사용자에게 영향이 가는 Warning 이슈가 존재 (예: 노출된 시크릿, 깨진 빌드, 데이터 유실 가능성)
- **✅ OKAY** — 위에 해당하지 않음. Warning/Info만 존재하거나 이슈가 없을 때.

판정 근거를 **한~두 문장**으로 정리해 출력에 포함한다. 근거에는 어떤 이슈가 판정을 좌우했는지(또는 차단 이슈가 없었다는 점)를 구체적으로 적는다. Critical이 없어도 머지 차단 수준의 Warning이 있다고 판단해 REJECT를 내릴 때는 그 이유를 명시한다.

### 6단계: 최종 출력

최종 출력 형식:

````markdown
# 코드 리뷰 결과

리뷰 대상: {설명 — PR #N, 파일 경로, 또는 `base...HEAD` diff} · 변경 파일 N개 · 에이전트: Code Reviewer, Oracle{, Designer}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 📌 핵심 이슈 (N건)

### 1. [🔴 Critical · 🧠 Logic] `src/foo.ts:42` — {한 문장 요약}

{이슈 설명을 한~두 문장으로 풀어 쓴다}.

**문제 코드**:

```ts
const session = await getUserSession(req)
return { email: session.email }
```

**제안**: {수정 제안 한 문장}.

```ts
if (session == null) return redirect('/login')
return { email: session.email }
```

### 2. [🟡 Warning · 🛡️ Security] `src/auth.ts:18` — {한 문장 요약}

{이슈 설명}.

**문제 코드**:

```ts
const sql = `SELECT * FROM users WHERE id = '${userId}'`
```

**제안**: Prepared statement 사용.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🎨 디자인 검토 (N건)

> Figma 디자인과 구현의 시각적 일치 여부. Figma 링크가 PR 본문에 포함되어 Designer가 스폰된 경우에만 렌더링한다.

### 1. [🟡 Warning · 🎨 Design] `src/Button.tsx:30` — 버튼 높이 불일치

Figma(48px) 대비 구현이 40px로 다르다.

**문제 코드**:

```tsx
<button className="h-10 px-4 ...">
```

**제안**: `h-12` (48px)로 수정.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## ✅ 이상 없음

🛡️ Security · 🎨 Design

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 🧑‍⚖️ 판정: ❌ REJECT

Critical Logic 이슈(`src/foo.ts:42` 세션 null 미체크)가 머지 시 사용자 로그인 흐름을 깨뜨릴 수 있어 차단한다.
````

**포맷 규칙**:

- **요약 라인**: 표를 사용하지 않고 한 줄로 압축한다. 형식: `리뷰 대상: {설명} · 변경 파일 N개 · 에이전트: {목록}`.
- **핵심 이슈 섹션**: Code Reviewer + Oracle 결과만 포함한다 (Logic/Convention/Security/Architecture). 최대 3개. 이슈가 0개면 섹션 전체를 생략한다.
- **디자인 검토 섹션**: Designer 결과만 포함한다. Figma 링크가 없고 디자인 변경도 없어 Designer를 스폰하지 않은 경우 섹션 전체를 생략한다. Designer가 스폰됐지만 이슈가 0건이면 섹션 대신 "이상 없음"에 `🎨 Design`만 표시한다. **디자인 변경은 감지됐으나 사용자가 "링크 없이 진행"을 택해 Designer를 스폰하지 못한 경우**, 디자인 검토 섹션 대신 판정 섹션 바로 위에 `⚠️ 디자인 변경이 감지됐으나 Figma 링크가 없어 디자인 정합성은 검토하지 못했습니다` 한 줄을 남긴다.
- 각 이슈는 표 없이 헤딩 한 줄 + 본문 형식으로 구성한다 (위 마크다운 예시 참고). 헤딩은 다음 순서로 구성한다: 순번 `N.`, 공백, 대괄호로 묶은 메타 `[심각도 이모지+이름 · 관점 이모지+이름]`, 공백, 백틱으로 감싼 `파일:라인`, ` — `, 한 문장 요약.
  - 디자인 검토에서도 동일 헤딩 형식을 쓴다. 관점은 항상 `🎨 Design`이다.
- 헤딩 다음 줄에 빈 줄 1개, 그 아래에 이슈 설명을 한~두 문장으로 풀어 쓴다.
- 그 다음 줄에 빈 줄 1개, 그 아래에 `**문제 코드**:` 한 줄, 빈 줄 1개, 언어 지정 코드블록(1~5줄)을 배치한다. JSON의 `problem_code`를 그대로 코드블록에 넣고 언어는 `language` 필드를 사용한다. 코드는 이슈 핵심 라인을 컴팩트하게 잘라낸다.
- 그 다음 줄에 빈 줄 1개, 그 아래에 `**제안**: {수정 제안 한 문장}.` 형태로 작성한다.
- 제안 코드 예시가 필요한 경우 (JSON의 `suggestion_code`가 비어 있지 않을 때) 제안 줄 다음에 빈 줄 1개를 두고 언어 지정 코드블록을 배치한다. `suggestion_code`가 없거나 빈 문자열이면 코드블록을 두지 않는다.
- 이슈 사이에는 빈 줄 1개만 둔다. 각 섹션 헤딩 바로 위에는 Unicode 구분선 `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━` 한 줄을 둔다 (첫 섹션 포함, 단 `# 코드 리뷰 결과` 상단에는 두지 않는다).
- **섹션 헤딩 prefix 이모지**: `## 📌 핵심 이슈`, `## 🎨 디자인 검토`, `## ✅ 이상 없음`, `## 🧑‍⚖️ 판정`.
- **이모지 매핑** (이슈 헤딩 인라인용):
  - 심각도: Critical = 🔴, Warning = 🟡, Info = 🔵
  - 관점: Logic = 🧠, Convention = 📏, Security = 🛡️, Architecture = 🏛️, Design = 🎨
- **"이상 없음" 섹션**: 이슈가 없었던 관점만 `{이모지} {이름}` 형태로 한 줄에 ` · `로 구분해 나열한다 (예: `🛡️ Security · 🎨 Design`). 모든 관점에 이슈가 있으면 이 섹션은 생략한다.
- **"판정" 섹션** (항상 출력, 가장 마지막):
  - 헤딩은 `## 🧑‍⚖️ 판정: ✅ OKAY` 또는 `## 🧑‍⚖️ 판정: ❌ REJECT` 형태로 결과를 한 줄에 표시한다.
  - 헤딩 다음 줄에 빈 줄 1개, 그 아래에 판정 근거를 한~두 문장으로 적는다. 판정에 결정적이었던 이슈가 있다면 `파일:라인`을 백틱으로 인용한다.
  - 이슈가 0건이어도 이 섹션은 생략하지 않고 `✅ OKAY`로 출력한다.

---

## 주의사항

- **읽기 전용**: 코드를 수정하지 않는다
- **어드바이저리**: 결과는 제안이며 자동 수정하지 않는다
- **이슈 제한**:
  - Code Reviewer + Oracle: 정말 중요한 것 최대 3개만 보고, 최종 출력도 Top 3만 남긴다. 중요하지 않으면 3개를 채우지 않는다
  - Designer: **개수 제한 없음**. 발견된 모든 시각적 불일치를 보고하며, 코드 이슈의 Top 3 제한과 완전히 별개 섹션으로 출력한다
- **판정은 오케스트레이터의 책임**: OKAY/REJECT 결정은 에이전트가 아닌 오케스트레이터가 직접 내린다. 에이전트 프롬프트에는 판정을 요청하지 않으며, 에이전트는 이슈 보고까지만 담당한다. 판정 규칙은 5단계를 따른다.
