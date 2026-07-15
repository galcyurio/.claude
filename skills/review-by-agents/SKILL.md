---
name: review-by-agents
description: "코드 변경사항을 여러 에이전트 관점(Logic, Convention, Security, Architecture)에서 병렬 리뷰하는 스킬. 사용자가 'review-by-agents', '코드 리뷰', '에이전트 리뷰', 'code review', '리뷰해줘', 'PR 리뷰해줘', '변경사항 리뷰', '코드 검토', '멀티 에이전트 리뷰', '병렬 리뷰' 등 코드/PR 리뷰를 요청할 때 이 스킬을 사용해야 한다. 단순 PR 조회나 보안 전용 리뷰(security-review 스킬 사용)에는 사용하지 않는다."
argument-hint: "[PR URL, PR 번호, 파일 경로, 또는 생략(현재 변경사항)]"
---

# Review by Agents - 병렬 에이전트 코드 리뷰

코드 변경사항을 여러 에이전트 관점에서 동시에 리뷰하는 읽기 전용 스킬이다. 코드를 수정하지 않으며, 발견된 이슈는 제안으로만 제공한다.

diff 모드(PR · 현재 변경사항)에서 **이슈가 1건 이상**이면 리뷰 결과를 difit 뷰어에 인라인 코멘트로 프리로드해 띄우고(상세는 difit에서 확인), 터미널에는 인덱스와 판정만 압축 출력한다. **이슈가 0건(깨끗한 리뷰)이거나** difit를 띄울 수 없으면(파일 모드 · 미설치 · 실패) difit를 띄우지 않고 터미널에만 결과를 출력한다.

difit를 띄운 경우, 사용자는 difit에서 직접 리뷰하며 내 코멘트에 답글을 달거나 새 코멘트를 남길 수 있다. **사용자가 리뷰를 끝냈다고 알리면**(명시적 종료 신호) `difit comment get`으로 실행 중 서버에서 코멘트를 회수해 사용자 추가분만 정리 보고하고(6-D), 회수 후 difit 잡을 종료한다. **회수는 읽기 전용**이다(코멘트를 보고만 하고 코드를 수정하지 않는다).

## 입력 형태

| 입력 형태 | 처리 |
|-----------|------|
| 인자 없음 | 현재 브랜치의 base 대비 diff (base 브랜치 자동 감지) |
| PR URL | `gh pr diff <number>` |
| 파일 경로 | 해당 파일 전체 리뷰 |

---

## 워크플로우

### 1단계: 입력 파싱 및 diff 추출

입력 파싱·base 감지·diff 추출·빈/대용량 가드를 **한 번의 호출**로 처리하는 헬퍼 스크립트를 실행한다(여러 shell 왕복을 한 번으로 접는다).

```
node ~/.claude/skills/review-by-agents/extract-diff.js [<인자>] --out <스크래치패드>/review-diff.patch
```

- `<인자>`: 사용자가 준 PR URL·PR 번호·파일 경로. 인자 없으면 생략(현재 변경사항 모드).
- `--out`: diff 본문을 저장할 경로. **세션 스크래치패드 경로**를 준다(생략 시 `os.tmpdir()`로 폴백).
- 스크립트는 **stdout에 단일 JSON**만 출력하고, diff 본문은 `diffFile`에 쓴다(거대 diff로 컨텍스트가 오염되는 것을 방지).
- base 감지는 스크립트 내부에서 처리한다: 연결된 PR의 base → `origin/HEAD` 심볼릭 참조(오프라인) → `git remote show origin`(네트워크) → 관습 기본 브랜치.

반환 JSON:

| 키 | 의미 |
|----|------|
| `mode` | `pr` \| `file` \| `diff` |
| `targetDesc` | 리뷰 대상 설명(`PR #N` / 파일 경로 / `<base>...HEAD`) |
| `base` | diff 모드의 base 브랜치 (6단계 difit `--merge-base`에 사용) |
| `prNumber` | PR 모드 번호 (2단계 PR 본문·6단계 difit에 사용) |
| `changedFiles` | 변경 파일 경로 배열 (3단계 Workflow args) |
| `diffLines` | diff/파일 라인 수 |
| `empty` | `true`면 리뷰 대상 없음 |
| `oversized` | `true`면 diff가 3000행 초과 |
| `diffFile` | 전체 diff/파일 내용을 담은 파일 경로 |
| `error` | 실패 사유(있으면 폴백 판단) |

JSON을 파싱해 분기한다:

- `error`가 비어 있지 않으면(PR 조회 실패·base 미감지·인자 해석 불가 등) 사유를 보고하고 중단하거나, 판단에 따라 수동 폴백으로 전환한다.
- `empty === true` → "리뷰할 변경사항이 없습니다"를 출력하고 종료한다.
- `oversized === true` → 사용자에게 파일 단위 분할 리뷰를 `AskUserQuestion`으로 제안하고 진행 여부를 확인한다.
- 정상이면 `diffFile`을 Read해 diff 텍스트를 확보한다. 이 텍스트가 3단계 Workflow의 `diff` args가 되고, `changedFiles`·`targetDesc`·`base`·`prNumber`는 이후 단계로 그대로 전달한다.

### 2단계: 외부 링크 컨텍스트 수집 (PR 모드만)

`gh pr view --json body`로 PR 본문을 가져온다.

본문에서 외부 링크를 추출하고, `~/.claude/rules/external-links.md` 규칙에 따라 각 링크에서 관련 정보를 수집한다.

수집된 정보를 요약하여 에이전트 프롬프트의 CONTEXT에 전달한다.

Figma 링크(`figma.com/design/`)가 포함되어 있으면 Designer 에이전트를 스폰할 대상으로 표시한다.

**디자인 변경 감지 시 Figma 링크 확보**: diff가 있는 모드(PR·현재 변경사항)에서 diff에 **디자인 관련 변경**(색상·간격·크기·레이아웃·타이포·컴포넌트 등 시각 요소의 신규·변경)이 있는데 PR 본문에서 Figma 링크를 확보하지 못했으면, fallback 체인으로 확보한다: **0** 이슈정보·epic_key → **1** feature-memory frame 좁히기(최우선) → **2** Jira 페이지 링크 → **3** 사용자 요청. **frame 단위 링크를 페이지 단위보다 우선**하고, 하나라도 확정하면 즉시 중단한다. 순수 로직·데이터 변경만이면 "디자인 변경 없음"으로 보고 건너뛴다. **상세 절차·MCP 호출은 `~/.claude/skills/review-by-agents/figma-fallback.md`를 Read한다.**

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

### 3단계: 코드 리뷰(Workflow) + 디자인 리뷰(메인) 병렬 실행

코드 리뷰는 `Workflow` 도구로 실행하고, 디자인 리뷰(Designer)는 메인 스레드에서 동시에 실행한 뒤 4단계에서 병합한다.

> **Workflow opt-in**: 이 스킬은 코드 리뷰 fan-out을 `Workflow` 도구로 실행하도록 명시한다. 사용자가 이 스킬을 호출한 것이 Workflow 도구 사용에 대한 opt-in이다.

**3-0. 저위험 변경 fast-path 판정 (3-A 진입 전 게이트)**

**기본은 3-A Workflow fan-out이다.** 변경이 **Track A(기계적 제거/리네임)** 또는 **Track B(additive DTO/매퍼)** 중 하나의 **공통 조건 + 트랙 조건 + 강제 게이트를 전부** 충족할 때만 fan-out을 생략하고 오케스트레이터가 직접 검증으로 대체할 수 있다. 어느 트랙에도 깔끔히 맞지 않거나 판단이 흔들리면 정규 Workflow(3-A). **트랙별 조건·게이트·출력 형태 상세는 `~/.claude/skills/review-by-agents/fast-path.md`를 Read한다.**

**fast-path가 대체하는 것은 3-A fan-out뿐이다.** 2단계 외부 링크/컨텍스트 수집(Slack API 스펙·Notion API 명세 등 서버-클라 계약의 원천)은 **생략 대상이 아니며 반드시 수행한다**(Track B는 이 계약이 검증의 1차 기준). 3-B 디자인 리뷰도 Figma 링크 확보 시 그대로 진행한다.

**3-A. 코드 리뷰 — Workflow 호출**

`Workflow({ scriptPath, args })`로 실행한다.

- `scriptPath`: `~/.claude/skills/review-by-agents/review-code-workflow.js` (절대 경로로 전달)
- `args`:
  - `diff`: 1단계에서 추출한 diff(파일 모드면 파일 내용)
  - `changedFiles`: 변경 파일 경로 배열
  - `contextSummary`: 2단계에서 수집한 외부 링크/Jira 컨텍스트 요약
  - `followupContext`: 2단계에서 정리한 TODO/후속/시리즈/production mock 블록
  - `targetDesc`: 리뷰 대상 설명(PR #N / 파일 경로 / `base...HEAD`)

스크립트 내부 finders(관점별 에이전트):

| finder | 관점 | 스폰 방식 |
|--------|------|----------|
| Code Reviewer | Logic + Convention + Security | `agent({schema})` sonnet (기본) |
| Architecture | Architecture | `agent({schema, agentType: 'Oracle'})` |

Workflow는 `{ targetDesc, codeIssues, verifyStats }`를 반환한다. `codeIssues`는 Critical 전량 + non-critical 최대 5건으로 이미 선별·정렬된 상태이며, Critical·머지차단 finding은 검증자 2명으로 교차검증을 거쳐 `verifyNote`가 부착돼 있다(상세: 4·5단계, `review-code-workflow.js`).

**3-B. 디자인 리뷰 — 메인 스레드 Designer 스폰**

Figma 링크가 확보됐을 때(출처: PR 본문 / Jira 이슈 / feature-memory / 사용자 제공)만 `subagent_type: "Designer"`로 메인 스레드에서 Agent를 스폰한다. Designer는 Figma MCP가 필요하며, 이는 Workflow 백그라운드 런에서 누락될 수 있으므로 **Workflow 밖 메인 스레드에서** 실행한다. 디자인 변경이 감지됐으나 사용자가 "링크 없이 진행"을 택한 경우는 스폰하지 않는다.

Designer에 전달하는 프롬프트는 아래 4섹션 구조를 따른다.

```
## REVIEW SCOPE
[diff 내용 또는 파일 내용]

## PERSPECTIVE
Figma 디자인과 구현의 시각적 일치 여부 (컴포넌트, 레이아웃, 색상, 간격)

## CONTEXT
[외부 링크에서 수집한 정보 요약 + Figma 링크]
[변경 파일의 import, 함수 시그니처 등 주변 코드]

## OUTPUT FORMAT
아래 JSON 배열 형식으로만 출력하라. 이슈가 없으면 빈 배열 [].
[{
  "severity": "critical|warning|info",
  "perspective": "Design",
  "file": "파일 경로",
  "line": 라인번호(변경 후 파일의 절대 라인, diff 텍스트 위치 아님),
  "issue": "이슈 설명 (한 문장)",
  "problem_code": "문제가 되는 원본 코드 스니펫 (1~5줄, 코드펜스 없이 본문만, 개행은 \\n)",
  "language": "코드블록 언어 식별자 (예: ts, kt). 파일 확장자에서 추론하라.",
  "suggestion": "수정 제안 (한 문장 텍스트)",
  "suggestion_code": "선택 — 수정안 코드 스니펫 (코드펜스 없이 본문만). 불필요하면 생략/빈 문자열."
}]

Designer는 **개수 제한 없음**. Figma 디자인과 구현의 모든 시각적 불일치를 보고하라.
```

#### finder 체크리스트 (Workflow 스크립트 내부)

- **Code Reviewer**
  - Logic: 버그, null safety, 경계 조건, 에러 핸들링 누락, 레이스 컨디션
  - Convention: 네이밍 일관성, 프로젝트 패턴, 코드 중복, 매직 넘버, 재사용(표준 API·기존 유틸 대신 재구현), 단순화 여지, 효율(비효율 자료구조·알고리즘), 추상화 레벨(altitude)
  - Security: 인젝션(SQL/XSS/SSRF), 인증/인가 우회, 민감정보 노출, 안전하지 않은 API 사용
- **Architecture(Oracle)**: 의존성 방향 위반, 레이어 위반, 단일 책임 위반, 불필요한 결합 도입
- **Designer**: Figma 디자인과 구현의 시각적 일치 여부 (컴포넌트, 레이아웃, 색상, 간격)

각 finder는 `mergeBlocking`(머지 순간 빌드/보안/데이터 영향 여부)을 포함해 보고하며, 개수 하드캡 없이 중요한 이슈만 severity를 정확히 태깅한다. 선별은 4단계(합성)에서 수행한다.

### 4단계: 결과 병합

두 출처의 결과를 병합한다.

- **코드 이슈**: Workflow가 반환한 `codeIssues`. 이미 중복 제거·선별·정렬이 끝난 상태다. 추가 가공하지 않는다.
  - Workflow 내부 처리(참고): ① 같은 `file:line`은 높은 severity 유지 ② **Critical 전량 보존(cap 없음)** + warning/info만 최대 5건 ③ severity 내림차순 → `file` → `line` 오름차순 정렬. Critical·머지차단 finding은 교차검증으로 `verifyNote`가 부착되며, 강등된 finding은 삭제하지 않고 낮춰진 severity로 남는다.
- **디자인 이슈**: 메인 스레드 Designer가 반환한 JSON 배열. **개수 제한 없음**. 같은 `file:line` 중복만 높은 severity로 정리하고 severity → `file` → `line` 순 정렬한다. 별도 섹션으로 출력한다.

### 5단계: 오케스트레이터 판정

병합된 결과를 종합해 오케스트레이터(스킬 호출자)가 **OKAY** 또는 **REJECT**를 결정한다. 판정 입력은 Workflow가 **교차검증을 거친** findings다 — 강등되어 게이트에서 빠진 finding은 판정 사유가 되지 않는다.

**판정 규칙**:

- **❌ REJECT** — 다음 중 하나라도 해당:
  - 검증된 Critical 이슈가 1건 이상 존재 (관점 무관: Logic/Convention/Security/Architecture/Design)
  - 검증된 머지차단(`mergeBlocking`) Warning 이슈가 존재 (노출된 시크릿, 깨진 빌드, 데이터 유실 등)
- **✅ OKAY** — 위에 해당하지 않음.

판정 근거를 한~두 문장으로 정리해 출력에 포함한다. 어떤 이슈가 판정을 좌우했는지(또는 차단 이슈가 없었다는 점)를 구체적으로 적고, **검증 통계**(예: `검증: Critical 3건 중 2건 확인·1건 강등`)를 한 줄 덧붙인다. `verifyStats`의 `criticalConfirmed`·`verified`·`downgraded`를 활용한다.

### 6단계: difit 프리로드 + 최종 출력

**difit 런치 게이트 (이 단계 진입 시 먼저 판정)**: difit는 **diff 모드 + 병합된 이슈(코드+디자인)가 1건 이상**일 때만 띄운다. 아래 중 하나라도 해당하면 difit를 띄우지 않고 6-C(터미널 출력)로 간다:

- **이슈 0건** (깨끗한 리뷰 — 프리로드할 코멘트가 없어 difit를 띄우지 않는다)
- **파일 모드** (diff 없음)
- **difit 미설치 · 런치 실패**

게이트를 통과하면(이슈 ≥1 & diff 모드 & difit 사용 가능) 리뷰 결과를 difit 인라인 코멘트로 프리로드하고(6-A), 터미널에는 게이트용 요약만 출력한다(6-B).

**이모지 매핑** (6-A·6-B·6-C 공통):

- 심각도: Critical = 🔴, Warning = 🟡, Info = 🔵
- 관점: Logic = 🧠, Convention = 📏, Security = 🛡️, Architecture = 🏛️, Design = 🎨

#### 6-A. difit 프리로드 및 런치 (diff 모드: PR / 현재 변경사항)

병합된 코드 이슈(`codeIssues`)와 디자인 이슈를 difit `--comment`로 변환해 difit를 띄운다. **이 단계는 6단계 게이트를 통과한 경우(이슈 ≥1 & diff 모드)에만 진입한다. 이슈 0건·파일 모드는 difit를 띄우지 않고 6-C로 간다.**

> **difit 실행·수명·회수·회수 후 종료는 `~/.claude/skills/review-by-self/difit-contract.md` 계약을 따른다** (6-A/6-D 진입 시 Read). 아래는 이 스킬 고유 부분(프리로드 · 게이트 · 프리로드 대조)만 정의한다.

이 스킬이 계약 위에 얹는 런치 옵션:

- `--no-open`(계약)이라 브라우저가 자동으로 열리지 않으므로, 터미널 게이트(6-B)를 먼저 보여주고 **사용자가 URL을 클릭해 연다.**
- 포트는 `--port <N>`으로 명시해 URL을 확정하고 다른 세션 difit와의 충돌을 피한다(점유 시 difit가 자동으로 다음 포트로 이동하므로 실제 바인딩 포트를 런치 후 확인한다).
- **`--clean`을 반드시 붙인다** — difit는 코멘트를 브라우저 localStorage(origin=`localhost:<port>`)에 영속하고 로드 시 이전 세션·타 PR 코멘트를 복원하므로, 없으면 잔존 코멘트가 이번 리뷰의 게이트(6-B)와 6-D 회수를 오염시킨다. `--clean`을 붙이면 클라이언트가 로드 시 localStorage를 비워 **회수가 프리로드 + 사용자 추가분만** 담게 된다(상세: 계약의 "코멘트 영속과 세션 격리").

**모드별 diff 소스**:

| 모드 | difit diff 소스 |
|------|--------------|
| PR 모드 | `gh pr diff <PR-URL> \| <difit-command>` — PR diff를 **stdin으로 파이프**한다. **`--pr`를 쓰지 않는다**: `--pr`는 diff와 함께 GitHub PR 리뷰 코멘트를 무조건 가져와(difit `getPrCommentImports`, 끄는 플래그 없음) 내 프리로드 코멘트 앞에 prepend하고, 그 코멘트들이 6-D 회수 덤프에 섞여 baseline 대조를 오염시킨다. `gh pr diff`는 `--pr`가 내부적으로 쓰는 것과 같은 명령이므로, stdin 파이프로 같은 diff를 **PR 코멘트 import 없이** 얻는다 |
| 현재 변경사항 모드 | `<difit-command> HEAD <base> --merge-base` — merge-base(`<base>`, HEAD)부터의 diff(three-dot). `<base>`는 1단계에서 감지한 base 브랜치 |

> **`--merge-base` 필수(현재 변경사항 모드)**: 없이 `difit HEAD <base>`는 **two-dot 직접 비교**(`git diff <base> HEAD`)라, base 브랜치가 fork 이후 앞으로 이동하면 그 사이 base에 병합된 커밋들이 diff에 전부 섞여 나온다. 1단계 에이전트 입력은 `git diff <base>...HEAD`(three-dot)이므로 `--merge-base`를 붙여 difit도 fork point 기준으로 맞춰야 **에이전트가 검토한 diff와 difit 렌더가 일치**한다. base가 빠르게 움직이는 레포(예: PRND develop)에서 특히 중요하다. `--merge-base`는 Git revision 모드 전용이며 **stdin 파이프(PR 모드)에서는 difit가 거부**하므로 PR 모드에는 붙이지 않는다(`gh pr diff`가 이미 PR의 병합 기준 diff를 준다).

PR 모드의 `gh pr diff`나 `npx difit`는 네트워크가 필요하므로 샌드박스에서는 계약의 네트워크 권한 규칙을 따른다.

**finding → `--comment` 조립 (헬퍼 스크립트)**:

병합된 코드·디자인 이슈를 하나의 findings 배열로 스크래치패드에 쓰고, `build-difit-comments.js`로 difit 주입용 JSON을 생성한다. **손으로 `--comment` JSON을 조립하지 않는다**(JSON 이스케이프·개행 오류 방지).

1. 병합된 이슈 배열을 `<스크래치패드>/review-findings.json`에 Write한다. 각 항목:
   - `severity`·`perspective`·`file`·`line`·`issue`, 선택 `suggestion`·`suggestion_code`·`language`·`verifyNote`.
   - `line`은 **변경 후 파일의 절대 라인**이어야 한다. 에이전트가 diff 상대 위치를 반환했으면 보정한 뒤 넣는다.
   - **삭제된 코드**를 지적하는 이슈만 `"side":"old"`를 넣는다(기본 `"new"`).
   - **`problem_code`·시크릿은 넣지 않는다** — `problem_code`는 body에서 제외되고(코멘트가 해당 라인에 부착돼 diff에서 바로 보임), 자격증명류는 계약의 "시크릿 금지"를 따른다.
2. `node ~/.claude/skills/review-by-agents/build-difit-comments.js --findings <스크래치패드>/review-findings.json --out <스크래치패드>` 를 실행한다.
3. 스크립트는 `{count, commentsFile, baselineFile}`을 stdout JSON으로 반환한다:
   - `commentsFile`: difit `--comment` 주입용 thread 배열(아래 런치에서 `"$(cat <commentsFile>)"`로 사용).
   - `baselineFile`: 6-D 대조용 `[{file,line,body}]` 프리로드 baseline.

스크립트의 body 조립 규칙(참고): `[<심각도 이모지> <심각도> · <관점 이모지> <관점>] <issue>` → (suggestion 있으면) 빈 줄 + `제안: …` → (suggestion_code 있으면) 빈 줄 + 코드펜스(언어 `language`) → (verifyNote 있으면) 빈 줄 + `> …`. `problem_code`는 넣지 않는다.

**런치**:

- 모드별 런치 형태로 **하니스 백그라운드(run_in_background)로 실행**한다 (계약의 "실행" — `--no-open`·`--keep-alive`·`--clean`. `--keep-alive`라 브라우저 닫힘으로 자가 종료하지 않고, 6-D 회수 트리거는 **사용자의 명시적 종료 신호**다):
  - **현재 변경사항 모드**: `<difit-command> HEAD <base> --merge-base --comment "$(cat <commentsFile>)" --clean --no-open --keep-alive --port <N>`
  - **PR 모드**: `gh pr diff <PR-URL> | <difit-command> --comment "$(cat <commentsFile>)" --clean --no-open --keep-alive --port <N>` — diff가 stdin으로 들어오므로 target 인자·`--merge-base`를 붙이지 않는다.
- `--comment`는 JSON **배열**을 받으므로 `commentsFile`(thread 배열) 하나로 모든 프리로드 코멘트가 주입된다. 셸이 `"$(cat …)"`로 파일 내용을 넣으므로 JSON을 명령줄에 손으로 적지 않는다.
- 런치 직후 `curl -s -o /dev/null -w '%{http_code}' http://localhost:<N>/`를 폴링해 `200`을 확인하고(PR 모드는 `gh pr diff` 실행 후 바인딩까지 수 초 걸린다), 바인딩된 포트로 최종 URL을 확정한다. diff fetch·bind 로그만 보고 URL을 성급히 안내하지 않는다.
- **프리로드 baseline**: `build-difit-comments.js`가 `baselineFile`에 각 프리로드 `{file, line, body}`를 이미 기록해 뒀다. 6-D 회수(`comment get`)는 프리로드 코멘트도 함께 돌려주므로, 이 파일과 대조해 사용자 추가분(새 코멘트·답글)을 가려낸다(프리로드 0건이면 빈 배열).
- 6-A 진입 시점에 프리로드할 이슈는 항상 1건 이상이다(0건이면 6단계 게이트에서 6-C로 빠진다). 따라서 difit는 최소 1개 코멘트를 프리로드한 상태로 뜬다.
- difit 실행이 실패하면 6-C 폴백으로 전환한다.

#### 6-B. 터미널 출력 — difit 런치 성공 시 (게이트)

상세(문제 코드·제안 코드)는 difit 코멘트에 있으므로 터미널은 **인덱스 + 판정**만 압축 출력한다.

````markdown
# 코드 리뷰 결과

리뷰 대상: {설명 — PR #N, `base...HEAD`} · 변경 파일 N개 · difit 프리로드 (코멘트 M건)

## 📌 핵심 이슈 (N건)

- [🔴 Critical · 🧠 Logic] `src/foo.ts:42` — 세션 null 미체크
- [🔴 Critical · 🛡️ Security] `src/auth.ts:18` — SQL 인젝션
- [🟡 Warning · 🎨 Design] `src/Btn.tsx:30` — 버튼 높이 불일치

상세 코드·제안은 difit 코멘트에서 확인.

## ✅ 이상 없음

🏛️ Architecture

## 🧑‍⚖️ 판정: ❌ REJECT

Critical Logic(`src/foo.ts:42` 세션 null 미체크)이 머지 시 로그인 흐름을 깨뜨려 차단한다.
검증: Critical 2건 중 2건 확인.

difit: http://localhost:4966

리뷰가 끝나면 브라우저를 닫고 알려주세요 — 알려주시면 코멘트를 회수해 정리합니다.
````

- **요약 라인**: `리뷰 대상: {설명} · 변경 파일 N개 · difit 프리로드 (코멘트 M건)`. (폴백의 `에이전트: …` 목록은 difit 런치 시 생략한다.)
- **핵심 이슈**: 선별된 코드 이슈(검증된 Critical 전량 + non-critical 최대 5건)와 디자인 이슈(개수 제한 없음)를 **한 목록**에 컴팩트 한 줄씩 출력한다. 형식: `- [<심각도 이모지> <심각도> · <관점 이모지> <관점>] \`file:line\` — <issue 한 문장>`. 정렬은 severity 내림차순 → file → line. 이슈가 0건이면 이 섹션을 생략한다.
- **이상 없음 · 판정**: 6-C와 동일 규칙을 따른다. 판정은 이슈가 0건이어도 항상 출력한다.
- **디자인 미검토 경고**: 디자인 변경이 감지됐으나 Figma 링크가 없어 Designer를 스폰하지 못한 경우, 판정 섹션 바로 위에 `⚠️ 디자인 변경이 감지됐으나 Figma 링크가 없어 디자인 정합성은 검토하지 못했습니다` 한 줄을 둔다.
- 마지막 줄에 `difit: {URL}`을 둔다. (6-B는 이슈 ≥1일 때만 도달하므로 프리로드 코멘트는 항상 1건 이상이다.)
- **readback 진입 안내**: `difit: {URL}` 다음 줄에 사용자에게 **URL을 열어 리뷰하고, 끝나면 브라우저를 닫고 알려달라**는 안내를 한 줄 둔다. 안내 후 **턴을 종료한다**. 사용자가 리뷰 완료를 알리면 그때 회수한다(6-D). `--keep-alive`라 브라우저를 닫아도 서버는 유지되므로, 브라우저 닫힘을 폴링하거나 잡 완료를 기다리지 않는다.

#### 6-C. 터미널 출력 — difit 미런치 시 (전체 상세)

**이슈 0건(깨끗한 리뷰) · 파일 모드 · difit 미설치 · 런치 실패** 중 하나면 difit 없이 터미널에 결과를 출력한다. **이슈 0건이면** 핵심 이슈·디자인 섹션이 모두 생략되어 `이상 없음` + `✅ OKAY` 판정만 남는다(이 경우가 "깨끗한 리뷰" 출력이다). 형식·규칙은 아래와 같다.

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
- **핵심 이슈 섹션**: Code Reviewer + Oracle 결과만 포함한다 (Logic/Convention/Security/Architecture). 검증된 Critical 전량 + non-critical 최대 5건. 이슈가 0개면 섹션 전체를 생략한다.
- **디자인 검토 섹션**: Designer 결과만 포함한다. Figma 링크가 없고 디자인 변경도 없어 Designer를 스폰하지 않은 경우 섹션 전체를 생략한다. Designer가 스폰됐지만 이슈가 0건이면 섹션 대신 "이상 없음"에 `🎨 Design`만 표시한다. **디자인 변경은 감지됐으나 사용자가 "링크 없이 진행"을 택해 Designer를 스폰하지 못한 경우**, 디자인 검토 섹션 대신 판정 섹션 바로 위에 `⚠️ 디자인 변경이 감지됐으나 Figma 링크가 없어 디자인 정합성은 검토하지 못했습니다` 한 줄을 남긴다.
- 각 이슈는 표 없이 헤딩 한 줄 + 본문 형식으로 구성한다 (위 마크다운 예시 참고). 헤딩은 다음 순서로 구성한다: 순번 `N.`, 공백, 대괄호로 묶은 메타 `[심각도 이모지+이름 · 관점 이모지+이름]`, 공백, 백틱으로 감싼 `파일:라인`, ` — `, 한 문장 요약.
  - 디자인 검토에서도 동일 헤딩 형식을 쓴다. 관점은 항상 `🎨 Design`이다.
- 헤딩 다음 줄에 빈 줄 1개, 그 아래에 이슈 설명을 한~두 문장으로 풀어 쓴다.
- 그 다음 줄에 빈 줄 1개, 그 아래에 `**문제 코드**:` 한 줄, 빈 줄 1개, 언어 지정 코드블록(1~5줄)을 배치한다. JSON의 `problem_code`를 그대로 코드블록에 넣고 언어는 `language` 필드를 사용한다. 코드는 이슈 핵심 라인을 컴팩트하게 잘라낸다.
- 그 다음 줄에 빈 줄 1개, 그 아래에 `**제안**: {수정 제안 한 문장}.` 형태로 작성한다.
- 제안 코드 예시가 필요한 경우 (JSON의 `suggestion_code`가 비어 있지 않을 때) 제안 줄 다음에 빈 줄 1개를 두고 언어 지정 코드블록을 배치한다. `suggestion_code`가 없거나 빈 문자열이면 코드블록을 두지 않는다.
- **검증 노트**: 코드 이슈가 Workflow 교차검증을 거친 경우(`verifyNote` 존재), 제안/제안 코드 다음에 빈 줄 1개를 두고 인용문 한 줄로 노트를 표시한다. 예: `> 검증: 정확성·머지영향 2/2 확인`, `> 검증: 1/2 refute → Warning 강등`. 디자인 이슈에는 검증 노트가 없다.
- 이슈 사이에는 빈 줄 1개만 둔다. 각 섹션 헤딩 바로 위에는 Unicode 구분선 `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━` 한 줄을 둔다 (첫 섹션 포함, 단 `# 코드 리뷰 결과` 상단에는 두지 않는다).
- **섹션 헤딩 prefix 이모지**: `## 📌 핵심 이슈`, `## 🎨 디자인 검토`, `## ✅ 이상 없음`, `## 🧑‍⚖️ 판정`.
- **이모지 매핑**: 6단계 상단 공통 표를 따른다.
- **"이상 없음" 섹션**: 이슈가 없었던 관점만 `{이모지} {이름}` 형태로 한 줄에 ` · `로 구분해 나열한다 (예: `🛡️ Security · 🎨 Design`). 모든 관점에 이슈가 있으면 이 섹션은 생략한다.
- **"판정" 섹션** (항상 출력, 가장 마지막):
  - 헤딩은 `## 🧑‍⚖️ 판정: ✅ OKAY` 또는 `## 🧑‍⚖️ 판정: ❌ REJECT` 형태로 결과를 한 줄에 표시한다.
  - 헤딩 다음 줄에 빈 줄 1개, 그 아래에 판정 근거를 한~두 문장으로 적는다. 판정에 결정적이었던 이슈가 있다면 `파일:라인`을 백틱으로 인용한다. 판정 근거 마지막에 검증 통계 한 줄(`검증: Critical N건 중 M건 확인·K건 강등`)을 포함한다.
  - 이슈가 0건이어도 이 섹션은 생략하지 않고 `✅ OKAY`로 출력한다.

#### 6-D. difit 답변 readback (difit 런치 성공 시 항상)

6-A에서 difit를 띄운 모든 경우(PR · 현재 변경사항 모드)에 **항상** 적용한다. 6-C 폴백(difit 미런치)은 회수할 잡이 없으므로 적용하지 않는다.

difit 수명·회수는 계약을 따른다: readback 트리거는 **사용자의 명시적 종료 신호**(리뷰 완료 알림)이고, 신호를 받으면 `difit comment get`으로 실행 중 서버에서 코멘트를 회수한 뒤 difit 잡을 종료한다. 아래는 이 스킬 고유의 **프리로드 대조**를 더한 절차다.

**절차**:

1. **종료 신호 대기** — 6-B에서 "URL을 열어 리뷰하고, 끝나면 브라우저를 닫고 알려달라"고 안내한 뒤 **턴을 종료한다**. 사용자가 리뷰 완료를 알릴 때까지 기다린다. `--keep-alive`라 브라우저 닫힘으로 서버가 죽지 않으므로, 잡 완료를 기다리거나 먼저 kill하지 않는다.
2. **회수 + 파싱** — 신호를 받으면 `difit comment get --port <N> --format text`로 실행 중 서버에서 코멘트를 회수하고, 출력의 `📝 Comments from review session:` 블록을 계약의 "회수" 포맷대로 파싱한다(thread별 `file:Lline` + 첫 메시지 + `Reply N` 답글, 끝에 `Total comments: N`). 블록이 없거나 `Total comments: 0`이면 남긴 코멘트 없음으로 본다.
3. **사용자 추가분 식별 (content 대조 — id 없음)** — 6-A의 `baselineFile`(`build-difit-comments.js`가 쓴 `[{file,line,body}]`)을 Read해 프리로드 본문과 대조한다. `comment get`은 프리로드 코멘트도 함께 돌려주므로 대조가 필요하다:
   - **답글(`Reply N (author)`)**: 프리로드는 답글을 달지 않으므로 **모든 답글은 사용자 추가분**이다.
   - **새 코멘트**: 첫 메시지 본문이 baseline의 어떤 프리로드 본문과도 매칭되지 않는 thread → **사용자가 새로 남긴 코멘트**.
   - 첫 메시지 본문이 프리로드 본문과 매칭되고 답글도 없는 thread → 내가 넣은 것 그대로이므로 **보고에서 제외**한다.
4. **보고** — 사용자 추가분을 `file:line`별로 정리해 출력한다(아래 형식). **읽기 전용**: 코멘트 내용을 보고만 하고 코드를 수정하지 않는다. 후속 반영이 필요하면 사용자가 별도로 지시한다(예: `apply-pr-feedback`).
5. **회수 후 종료** — 계약의 "회수 후 종료"를 따른다. `comment get`으로 회수를 끝낸 뒤 **우리가 이번에 띄운 그 difit 잡만** 종료한다. 무관한 difit 서버까지 광범위하게 죽이지 않는다.

**회수 보고 형식**:

````markdown
## 💬 difit 답변 회수 (N건)

- `a.txt:2` (답글) — "확인함, 의도된 변경 맞음"
- `b.kt:40` (신규 코멘트) — "여기 네이밍 BarViewModel로 바꿔주세요"

difit 잡은 회수 후 종료됨.
````

- 사용자 추가분이 0건이면 `## 💬 difit 답변 회수` 아래 `남긴 답변 없음` 한 줄만 출력한다(회수 후 difit 잡은 종료).
- `(답글)`/`(신규 코멘트)` 구분은 3단계 식별 결과를 따른다. 내 원본 코멘트 맥락이 필요하면 같은 thread의 프리로드 본문(첫 메시지)을 함께 인용한다.
- 회수 트리거는 사용자의 명시적 종료 신호다. `comment get`은 실행 중 서버에서 조회하므로, 신호를 받은 뒤 회수하고 곧바로 우리가 띄운 잡을 종료한다.

---

## 주의사항

- **읽기 전용**: 코드를 수정하지 않는다
- **어드바이저리**: 결과는 제안이며 자동 수정하지 않는다
- **저위험 fast-path (2트랙)**: **Track A**(기계적 제거/리네임 — 새 로직 없음 + PR head grep 잔존 참조 0건 + 동작 지점 ≤3 각각 직접 Read) 또는 **Track B**(additive DTO/매퍼 — 계약 1:1 대조 + 매퍼 왕복 대칭 확인 + 새 sealed subtype의 exhaustive `when` 커버 grep)의 공통 조건(보안 표면 0 등)+트랙 조건+게이트를 **전부** 충족할 때만 3-A Workflow fan-out을 생략할 수 있다. 미충족·모호하면 정규 Workflow. 상세는 3-0·`fast-path.md`.
- **이슈 제한**:
  - Code Reviewer + Oracle(코드 이슈): **검증된 Critical은 전량 보존**하고, warning/info는 합쳐서 최대 5개만 남긴다. 순수 포매팅·취향 수준의 사소한 지적은 제외하되, 재사용/단순화/효율/추상화 레벨(altitude) 개선은 info/warning으로 보고한다
  - Designer: **개수 제한 없음**. 발견된 모든 시각적 불일치를 보고하며, 코드 이슈 선별 제한과 완전히 별개 섹션으로 출력한다
- **판정은 오케스트레이터의 책임**: OKAY/REJECT 결정은 에이전트가 아닌 오케스트레이터가 직접 내린다. 에이전트 프롬프트에는 판정을 요청하지 않으며, 에이전트는 이슈 보고까지만 담당한다. 판정 규칙은 5단계를 따른다.
- **difit 출력**: diff 모드(PR · 현재 변경사항)에서 **이슈가 1건 이상일 때만** finding을 difit 인라인 코멘트로 프리로드한다(6단계). **이슈 0건(깨끗한 리뷰)이면 difit를 띄우지 않고 터미널 출력(6-C)만 한다.** difit는 로컬 뷰어이며 **PR 모드라도 원격 GitHub에 코멘트를 달지 않는다**. 시크릿·토큰·키·PII는 difit 코멘트 본문·명령줄 인자에 복사하지 않는다.
- **difit 수명·회수·종료**: `~/.claude/skills/review-by-self/difit-contract.md` 계약을 따른다(`--no-open`·`--keep-alive` → 브라우저 닫혀도 서버 유지, **사용자 종료 신호** = 6-D 트리거, `comment get`으로 회수 후 우리가 띄운 잡만 종료).

---

## Workflow 실패 시 폴백

`Workflow` 도구를 사용할 수 없거나, 호출이 실패하거나, **빈 결과(`targetDesc`가 빈 문자열이거나 스크립트가 `args.diff 비어 있음` 오류로 throw — args 미전달 신호)를 반환하면** 수동 `Agent` 병렬 스폰 경로로 전환한다. 빈 결과를 정상 "이슈 없음"으로 오인해 보고하지 않는다.

- 메인 스레드에서 Code Reviewer(Logic+Convention+Security, sonnet)·Oracle(Architecture)·Designer(Figma 확보 시)를 직접 병렬 스폰한다. **Security는 별도 에이전트로 두지 않고 Code Reviewer가 함께 검토**한다.
- 선별은 **검증된 Critical 전량 보존 + non-critical 최대 5건** 규칙을 그대로 적용한다.
- 검증(item 1)·schema 강제(item 4)는 best-effort:
  - 검증: 오케스트레이터가 각 Critical·머지차단 finding의 `file:line`을 직접 Read해 확인한 뒤 판정한다(검증자 에이전트 없이).
  - schema: 에이전트 프롬프트에 출력 JSON 계약을 명시하고, 결과가 malformed면 해당 에이전트를 1회 재프롬프트한다. 계약에 "`line`은 변경 후 파일의 절대 라인 번호(diff 텍스트 위치 아님)"를 반드시 포함한다 — diff를 파일로 Read시키면 diff 줄 번호와 혼동되므로 명시적으로 못 박는다.
- 폴백으로 처리했음을 최종 출력 요약 라인에 `(폴백: 수동 스폰)`으로 표시한다.
- difit 프리로드/런치(6-A)는 Workflow 성공 여부와 무관하게 **6단계 게이트를 따른다**(이슈 ≥1일 때만 런치). 수동 스폰 폴백에서 이슈가 1건 이상이면 병합된 이슈를 difit 코멘트로 띄우고 6-B 게이트 형식으로 출력하되 요약 라인에 `(폴백: 수동 스폰)`을 함께 표기한다. 이슈 0건이면 difit를 띄우지 않고 6-C로 출력하며, 마찬가지로 `(폴백: 수동 스폰)`을 표기한다.
