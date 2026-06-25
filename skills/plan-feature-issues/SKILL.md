---
name: plan-feature-issues
description: 피처(Jira 에픽) 작업을 착수할 때 Jira·Slack·Notion·Figma를 멀티소스로 파악해 본인이 구현할 작업을 도출하고 Jira 이슈로 만드는 스킬. 사용자가 'plan-feature-issues', '피처 시작', '피처 파악해서 이슈 만들어', '에픽 보고 내 작업 이슈로 쪼개줘', '내가 할 작업 찾아서 이슈 만들어', '이 피처 작업 이슈 만들어줘' 등 피처 착수 시 작업 도출+이슈화를 요청할 때 사용한다. 이슈 제목·목록이 이미 정해진 단순 생성에는 create-jira-issue를 사용한다.
---

# plan-feature-issues

## 역할

피처(Jira 에픽) 착수 시점에 흩어진 정보(Jira·Slack·Notion·Figma)를 모아 전체를 파악하고, **본인이 구현할 작업**을 도출해 적정 단위로 분해한 뒤, 실제 Jira 이슈 생성은 `create-jira-issue` 스킬에 위임한다.

**create-jira-issue와의 차이**: `create-jira-issue`는 "만들 이슈 목록"을 입력으로 받는다. 이 스킬은 그 목록을 **멀티소스에서 도출**하는 앞단이다. 도출이 끝나면 생성은 위임한다.

## 절차

### 1. 입력 확정
- Jira 에픽 키 1개 이상. 앱이 여럿이면 복수 에픽 (예: 고객 `HDA-xxxx` + 리볼트 `HDA-yyyy`).
- 브랜치명에서 `[A-Z]+-\d+` 추출 가능하면 추출.

### 2. 멀티소스 파악 (병렬 fetch)
- 에픽 fetch: `getJiraIssue` (description·comment·subtasks·parent), `getJiraIssueRemoteIssueLinks` (웹 링크).
- description·comment·remote link에서 URL 추출 → `~/.claude/rules/external-links.md` 규칙으로 도메인 분류.
- Slack/Notion/Figma 병렬 fetch:
  - **Slack**: 채널·스레드에서 **결정사항·미결 질문**을 본다 (단순 채팅 아님).
  - **Notion**: 기획서 — 목적·해결방향·필요 데이터·시안.
  - **Figma**: frame 목록 (페이지 단위 nodeId면 `get_metadata`로 직계 frame 추출).
- ⛔ **Jira만 보고 끝내지 않는다.** Slack/Notion에서 합의·추가된 스펙이 작업의 핵심인 경우가 많다 (예: "eye 필터도 추가", "구간 4개로 확정"). 이걸 놓치면 이슈가 누락된다.

### 3. 본인 작업 도출
- 수집 정보에서 **본인 역할(예: Android 클라)이 구현할 것**만 추출한다.
- 포함: 클라 UI·상태·API 연동·이벤트 로그.
- 제외: 서버 API 명세, 기획·디자인 산출물, QA, 타 직군 작업.
- **미결/블로커 표시**: 답변 대기 중인 결정(예: 구간 경계, 0원 포함 여부)은 작업 description에 메모로 남긴다.
- 앱이 여럿이면 앱별로 분리한다 (각 에픽이 부모). 본인 담당 범위가 모호하면 도출 직후 `AskUserQuestion`으로 확인.

### 4. 분해 관례 조사
- 같은 프로젝트의 **유사·인접 에픽 하위 이슈**를 JQL 조회 (`parent = HDA-xxxx`).
- 그 프로젝트가 실제로 어떤 단위로 쪼개는지 패턴을 본다 (골격→UI→API/DTO→이벤트 등).
- 대상 에픽의 기존 하위 이슈도 조회해 **중복 생성을 방지**한다.

### 5. 분해 단위 확정 (필수 — 자동 결정 금지)
- 도출한 작업 + **2~3개 분해 옵션**(필터별/기능별/레이어별 + 이슈 개수)을 `AskUserQuestion`으로 제시한다.
- option `preview`로 실제 생성될 이슈 목록 mock을 보여주면 비교가 쉽다.
- ⛔ **분해 단위를 임의로 정하지 않는다.** 같은 작업도 사람·프로젝트마다 쪼개는 굵기가 다르다 (커밋 단위처럼 잘게 vs 기능 단위로 굵게). 사용자가 정하게 한다.

### 6. 이슈 생성 위임
- 확정된 작업 목록을 **`create-jira-issue` 스킬에 넘긴다** (`parent-with-subtasks` 모드, 에픽별로).
- ⛔ **직접 MCP/`acli`로 이슈를 만들지 않는다.** `create-jira-issue`가 App 필드·prefix automation·ADF 설명을 일관되게 처리한다. 직접 만들면 prefix 중복·필드 누락이 재발한다.
- summary는 **prefix 없이 순수 제목**을 넘긴다 (에픽 prefix는 automation이 부착 — [[reference_prnd_jira_epic_prefix_automation]]).

### 7. 검증
- 생성된 이슈의 parent·assignee·summary를 확인한다.
- prefix automation은 **비동기**다 (생성 후 최대 ~2분). 생성 직후 응답엔 prefix가 없고 잠시 후 붙는다 → 시간차 두고 검증.

## 핵심 원칙

| 원칙 | 이유 |
|---|---|
| 멀티소스 파악 없이 이슈 만들지 않는다 | Jira만 보면 Slack/Notion에서 합의된 스펙(추가 필터·확정 구간)을 놓친다 |
| 분해 단위는 사용자가 정한다 (`AskUserQuestion`) | 쪼개는 굵기는 정답이 없다. 자동 추정하면 과대/과소 분해 |
| 생성은 `create-jira-issue` 위임 | 중복 구현 = prefix·App 필드 실수 재발. 위임이 단일 경로 |

## Red Flags — 멈추고 점검

- "Jira description만 보고 작업 도출했다" → Slack/Notion 결정사항 누락 가능. 2단계로.
- "분해 단위를 내가 정해서 바로 만들었다" → 5단계 `AskUserQuestion` 건너뜀.
- "MCP `createJiraIssue`로 직접 만들었다" → 6단계 위임 위반. prefix·필드 실수 위험.
- "summary에 `[고객]` prefix를 넣었다" → automation이 또 붙여 중복. 순수 제목만.
