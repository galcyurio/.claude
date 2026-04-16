---
name: review-by-agents
description: "코드 변경사항을 여러 에이전트 관점(Logic, Convention, Security, Architecture)에서 병렬 리뷰한다. 사용자가 'review-by-agents', '코드 리뷰', '에이전트 리뷰', 'code review' 등을 언급할 때 이 스킬을 사용해야 한다."
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

### 3단계: 에이전트 병렬 스폰

아래 에이전트를 **동시에** Agent 도구로 스폰한다:

| 에이전트 | 관점 | 스폰 방식 | 조건 |
|----------|------|----------|------|
| Code Reviewer | Logic + Convention + Security | `model: "sonnet"` (subagent_type 생략) | 항상 |
| Oracle | Architecture | `subagent_type: "Oracle"` | 항상 |
| Designer | Design (Figma-구현 일치) | `subagent_type: "Designer"` | Figma 링크가 있을 때만 |

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
[{ "severity": "critical|warning|info", "perspective": "Logic|Convention|Security|Architecture|Design", "file": "파일 경로", "line": 라인번호, "issue": "이슈 설명 (한 문장)", "suggestion": "수정 제안 (코드 예시 포함 가능)" }]
최대 10개.
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

### 4단계: 결과 통합 및 출력

에이전트 결과(JSON 배열)를 수집하여 아래 순서로 처리한다:

1. **중복 제거**: 같은 `file:line` 이슈는 심각도가 높은 쪽을 유지한다
2. **정렬**:
   - 1차: 심각도 (Critical → Warning → Info)
   - 2차: 같은 심각도 내에서는 `file` → `line` 오름차순
3. **번호 매기기**: 각 심각도 섹션 내에서 1부터 시작하는 순번을 부여한다

최종 출력 형식:

````markdown
## 코드 리뷰 결과

### 요약

| 항목 | 값 |
|------|---|
| 리뷰 대상 | {설명 — PR #N, 파일 경로, 또는 `base...HEAD` diff} |
| 변경 파일 | N개 |
| 발견 이슈 | 총 N개 · Critical N · Warning N · Info N |
| 참여 에이전트 | Code Reviewer, Oracle{, Designer} |

---

### Critical (N건)

#### 1. src/foo.ts:42

| 항목 | 내용 |
|------|------|
| 관점 | Logic |
| 이슈 | {한 문장 이슈 설명} |
| 제안 | {수정 제안 — 한 줄 요약. 코드 예시가 있으면 아래 코드블록 참조} |

```ts
if (user != null) { ... }
```

#### 2. src/auth.ts:18

| 항목 | 내용 |
|------|------|
| 관점 | Security |
| 이슈 | {한 문장 이슈 설명} |
| 제안 | Prepared statement 사용 |

---

### Warning (N건)

#### 1. src/bar.ts:10

| 항목 | 내용 |
|------|------|
| 관점 | Convention |
| 이슈 | {한 문장 이슈 설명} |
| 제안 | {수정 제안} |

---

### Info (N건)

#### 1. src/baz.ts:5

| 항목 | 내용 |
|------|------|
| 관점 | Architecture |
| 관찰 | {관찰 내용} |
| 참고 | {참고 사항} |

---

### 이상 없음

| 관점 | 결과 |
|------|------|
| Security | 보안 이슈 없음 |
| Design | Figma 디자인과 구현이 일치함 |
````

**포맷 규칙**:

- 각 이슈는 `#### {순번}. {파일:라인}` 헤딩 + 3~4행짜리 세로 표로 구성한다. 표 자체가 이슈 간 경계 역할을 하므로 이슈 사이에는 빈 줄만 둔다 (`---` 구분선 불필요).
- 표의 첫 행은 항상 `관점` (Logic/Convention/Security/Architecture/Design).
- Critical/Warning: 표 행은 `관점` · `이슈` · `제안` 순.
- Info: 표 행은 `관점` · `관찰` · `참고` 순.
- 표의 `이슈`/`제안` 셀은 한 문장으로 작성한다. 표 셀 내부에 여러 줄이나 코드블록을 넣지 않는다 (렌더링 깨짐 방지).
- 코드 예시가 필요한 경우 표 바로 아래에 언어 지정 코드블록을 배치한다. 표와 코드블록 사이에는 빈 줄 1개를 둔다.
- 심각도 섹션 사이에는 `---` 구분선을 둔다 (Critical / Warning / Info / 이상 없음 경계).
- "이상 없음" 섹션도 `관점` · `결과` 2열 표로 통일한다. 이슈가 없는 관점만 행으로 나열하며, 모든 관점에 이슈가 있으면 이 섹션은 생략한다.
- 특정 심각도에 이슈가 없으면 해당 섹션 전체(헤딩 + 표)를 렌더링하지 않는다.

---

## 주의사항

- **읽기 전용**: 코드를 수정하지 않는다
- **어드바이저리**: 결과는 제안이며 자동 수정하지 않는다
- **이슈 제한**: 각 에이전트에 최대 이슈 10개 제한
