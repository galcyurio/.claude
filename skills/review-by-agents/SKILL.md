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

**개수 제한은 에이전트별로 다르다**:
- Code Reviewer / Oracle: **정말 중요한 것만 최대 3개**까지. 사소한 네이밍·스타일 지적은 제외하고, 실제 버그·보안 취약점·구조적 결함·사용자 영향이 큰 이슈 위주로 선별하라. 억지로 3개를 채우지 말고, 중요한 게 1개면 1개만 보고하라.
- Designer: **개수 제한 없음**. Figma 디자인과 구현의 모든 시각적 불일치를 보고하라. 코드 이슈의 Top 3 제한과는 완전히 별개다.
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

에이전트 결과(JSON 배열)를 **두 그룹으로 분리**하여 처리한다:

- **코드 이슈 그룹**: Code Reviewer + Oracle (Logic, Convention, Security, Architecture)
- **디자인 이슈 그룹**: Designer (Design) — 별도 섹션으로 출력한다

각 그룹 공통 처리:

1. **중복 제거**: 같은 `file:line` 이슈는 심각도가 높은 쪽을 유지한다
2. **선별**:
   - 코드 이슈: **정말 중요한 것 최대 3개**만 남긴다 (Top 3). 억지로 채우지 않고, 중요한 게 1개면 1개만 남긴다
   - 디자인 이슈: **개수 제한 없음**. Designer가 보고한 이슈 전체를 그대로 출력한다. 코드 이슈의 Top 3 제한과 완전히 별개다
3. **정렬**: 심각도 내림차순 → `file` → `line` 오름차순

최종 출력 형식:

````markdown
## 코드 리뷰 결과

### 요약

| 항목 | 값 |
|------|---|
| 리뷰 대상 | {설명 — PR #N, 파일 경로, 또는 `base...HEAD` diff} |
| 변경 파일 | N개 |
| 참여 에이전트 | Code Reviewer, Oracle{, Designer} |

---

### 핵심 이슈 (N건)

#### 1. src/foo.ts:42

| 항목 | 내용 |
|------|------|
| 심각도 | Critical |
| 관점 | Logic |
| 이슈 | {한 문장 이슈 설명} |
| 제안 | {한 문장 수정 제안. 코드 예시가 있으면 아래 코드블록 참조} |

```ts
if (user != null) { ... }
```

#### 2. src/auth.ts:18

| 항목 | 내용 |
|------|------|
| 심각도 | Warning |
| 관점 | Security |
| 이슈 | {한 문장 이슈 설명} |
| 제안 | Prepared statement 사용 |

---

### 디자인 검토 (N건)

> Figma 디자인과 구현의 시각적 일치 여부. Figma 링크가 PR 본문에 포함되어 Designer가 스폰된 경우에만 렌더링한다.

#### 1. src/Button.tsx:30

| 항목 | 내용 |
|------|------|
| 심각도 | Warning |
| 이슈 | 버튼 높이가 Figma(48px) 대비 구현(40px)과 다름 |
| 제안 | `h-12` (48px)로 수정 |

---

### 이상 없음

| 관점 | 결과 |
|------|------|
| Security | 보안 이슈 없음 |
| Design | Figma 디자인과 구현이 일치함 |
````

**포맷 규칙**:

- **핵심 이슈 섹션**: Code Reviewer + Oracle 결과만 포함한다 (Logic/Convention/Security/Architecture). 최대 3개. 이슈가 0개면 섹션 전체를 생략한다.
- **디자인 검토 섹션**: Designer 결과만 포함한다. Figma 링크가 없어 Designer를 스폰하지 않은 경우 섹션 전체를 생략한다. Designer가 스폰됐지만 이슈가 0건이면 섹션 대신 "이상 없음"에 `Design` 행으로만 표시한다.
- 각 이슈는 `#### {순번}. {파일:라인}` 헤딩 + 세로 표로 구성한다. 이슈 사이에는 빈 줄만 둔다.
  - 핵심 이슈 표 행: `심각도` · `관점` · `이슈` · `제안` (4행)
  - 디자인 검토 표 행: `심각도` · `이슈` · `제안` (3행, 관점은 항상 Design이라 생략)
- 표의 `이슈`/`제안` 셀은 한 문장으로 작성한다. 표 셀 내부에 여러 줄이나 코드블록을 넣지 않는다 (렌더링 깨짐 방지).
- 코드 예시가 필요한 경우 표 바로 아래에 언어 지정 코드블록을 배치한다. 표와 코드블록 사이에는 빈 줄 1개를 둔다.
- 섹션 사이(핵심 이슈 / 디자인 검토 / 이상 없음)에는 `---` 구분선을 둔다.
- "이상 없음" 섹션은 이슈가 없었던 관점만 행으로 나열한다. 모든 관점에 이슈가 있으면 이 섹션은 생략한다.

---

## 주의사항

- **읽기 전용**: 코드를 수정하지 않는다
- **어드바이저리**: 결과는 제안이며 자동 수정하지 않는다
- **이슈 제한**:
  - Code Reviewer + Oracle: 정말 중요한 것 최대 3개만 보고, 최종 출력도 Top 3만 남긴다. 중요하지 않으면 3개를 채우지 않는다
  - Designer: **개수 제한 없음**. 발견된 모든 시각적 불일치를 보고하며, 코드 이슈의 Top 3 제한과 완전히 별개 섹션으로 출력한다
