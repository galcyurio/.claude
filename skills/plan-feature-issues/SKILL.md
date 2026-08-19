---
name: plan-feature-issues
description: 피처(Jira 에픽) 작업을 착수할 때 Jira·Slack·Notion·Figma를 멀티소스로 파악해 본인이 구현할 작업을 도출하고 Jira 이슈로 만드는 스킬. 사용자가 'plan-feature-issues', '피처 시작', '피처 파악해서 이슈 만들어', '에픽 보고 내 작업 이슈로 쪼개줘', '내가 할 작업 찾아서 이슈 만들어', '이 피처 작업 이슈 만들어줘' 등 피처 착수 시 작업 도출+이슈화를 요청할 때 사용한다. 이슈 간 선후 관계를 정리해달라는 요청('뭐부터 해야 해', '작업 순서 정해줘', '이슈끼리 blocks 걸어줘', 'blocked by 연결해줘')에도 사용한다. 이슈 제목·목록이 이미 정해진 단순 생성에는 create-jira-issue를 사용한다.
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
- description·comment·remote link에서 URL 추출 → `~/.claude/references/external-links.md` 규칙으로 도메인 분류.
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

### 7. 착수 순서·의존성 링크 (blocks / blocked by)

생성된 이슈 사이에 **실제 블로커 관계만** Jira 링크로 건다. 목적은 "지금 착수 가능한 이슈"와 "선행 작업을 기다려야 하는 이슈"가 Jira에서 바로 보이게 하는 것이다.

**7-1. 의존성 판단**
- 기준: **선행이 끝나지 않으면 후행을 시작(또는 컴파일·동작)할 수 없다**일 때만 링크한다.
- 흔한 선행 관계 (PRND Android):
  - API/DTO 추가 → 그 데이터를 쓰는 UI
  - 화면 골격(Activity·ViewModel·UiState) → 그 화면의 UI 본문·개별 기능
  - 공통 컴포넌트 → 그 컴포넌트를 쓰는 화면
  - `prnd-library` 변경 → 그것을 쓰는 앱 이슈 (앱이 여러 개면 앱 간 링크도 검토)
- **전이 중복 금지**: A→B, B→C가 있으면 A→C는 걸지 않는다.
- **순환 금지**: 순환이 나오면 분해가 잘못된 것이다. 5단계로 돌아가 합치거나 다시 쪼갠다.
- **외부 블로커**: 서버 API 미완·기획 미결처럼 Jira 이슈가 없는 블로커는 링크 대신 해당 이슈 description에 메모로 남긴다 (3단계 미결/블로커 표시와 동일).
- ⛔ "같이 하면 편하다", "이 순서가 자연스럽다" 정도로는 링크하지 않는다. 링크가 많아지면 순서 정보가 아니라 노이즈가 된다.

**7-2. 사용자 확인 (필수)**
- 의존성 표(선행 → 후행 + 근거 1줄)와 착수 순서(Wave)를 출력한 뒤 `AskUserQuestion`으로 확정한다.
- 옵션 예: `이대로 링크 생성 (Recommended)` / `일부 수정` / `링크 생략`.
- ⛔ 확인 없이 링크를 만들지 않는다. 잘못 건 링크는 지워도 이슈 히스토리에 남는다.

**7-3. 링크 생성 (`acli`) — ① 1건 → ② 방향 검증 → ③ 나머지**

이 세 단계를 순서대로 실행한다. 전체 링크 명령을 한 번에 실행하지 않는다 — 방향이 반대면 되돌릴 링크가 그만큼 늘어난다.

**`--out`이 후행이다.** 이름과 반대이므로 외우지 말고 아래 예시를 그대로 쓴다. `--out A --in B`는 "A는 B에 막혀 있다"(B가 선행)로 걸린다. 성공 메시지는 `A Blocks B`라고 출력되지만 실제 저장은 그 반대다 — **메시지를 믿지 말고 ②로 확인한다.**

```bash
# ① 첫 1건만 생성. --out = 후행(blocked), --in = 선행(blocker)
acli jira workitem link create --out <후행> --in <선행> --type Blocks --yes

# ② 방향 검증. 후행 쪽에 "is blocked by <선행>"으로 보여야 정상
acli jira workitem link list --key <후행> --json
```

`link list`는 상대 키를 한쪽 관점에서만 주므로, 방향까지 보려면 이슈 조회가 확실하다.

```bash
acli jira workitem view <후행> --fields "key,issuelinks" --json
# inwardIssue 에 <선행>이 있으면 정상 ("<후행> is blocked by <선행>")
# outwardIssue 에 <선행>이 있으면 거꾸로 걸린 것이다

# ③ ②가 정상일 때만 나머지를 배치로 생성
acli jira workitem link create --from-json <파일> --yes
```

- ③의 배치 JSON도 플래그와 같은 규칙이다: `[{ "outwardIssue": "<후행>", "inwardIssue": "<선행>", "type": "Blocks" }, ...]`
- ②가 반대로 나오면 응답의 링크 `id`로 지우고(`acli jira workitem link delete --id <id> --yes`) `--out`/`--in`을 바꿔 ①부터 다시 한다.
- ⛔ **MCP `createIssueLink`를 쓰지 않는다.** 이 도구는 inward/outward를 반대로 매핑한 이력이 있고 도구 설명 자체가 Jira REST 스펙과 반대다 (`atlassian/atlassian-mcp-server#112`). 쓰면 링크가 전부 거꾸로 걸린다. `acli`만 쓴다.

### 8. 검증 및 착수 순서 보고
- 생성된 이슈의 parent·assignee·summary를 확인한다.
- prefix automation은 **비동기**다 (생성 후 최대 ~2분). 생성 직후 응답엔 prefix가 없고 잠시 후 붙는다 → 시간차 두고 검증.
- 링크를 만들었다면 착수 순서를 보고한다: **blocked by가 없는 이슈 = 지금 착수 가능**. Wave 단위로 정리해 어떤 이슈가 무엇을 기다리는지 함께 적는다.

## 핵심 원칙

| 원칙 | 이유 |
|---|---|
| 멀티소스 파악 없이 이슈 만들지 않는다 | Jira만 보면 Slack/Notion에서 합의된 스펙(추가 필터·확정 구간)을 놓친다 |
| 분해 단위는 사용자가 정한다 (`AskUserQuestion`) | 쪼개는 굵기는 정답이 없다. 자동 추정하면 과대/과소 분해 |
| 생성은 `create-jira-issue` 위임 | 중복 구현 = prefix·App 필드 실수 재발. 위임이 단일 경로 |
| 블로커 링크는 `acli`로, `--in`이 선행 | MCP `createIssueLink`는 방향이 반대다. `acli`도 플래그 이름과 반대이고 성공 메시지까지 거꾸로 찍히니 반드시 ②로 검증 |
| 링크는 진짜 블로커만 | 순서 취향까지 링크하면 "지금 뭘 할 수 있나"가 안 보인다 |

## Red Flags — 멈추고 점검

- "Jira description만 보고 작업 도출했다" → Slack/Notion 결정사항 누락 가능. 2단계로.
- "분해 단위를 내가 정해서 바로 만들었다" → 5단계 `AskUserQuestion` 건너뜀.
- "MCP `createJiraIssue`로 직접 만들었다" → 6단계 위임 위반. prefix·필드 실수 위험.
- "summary에 `[고객]` prefix를 넣었다" → automation이 또 붙여 중복. 순수 제목만.
- "이슈만 만들고 끝냈다" → 7단계 누락. 어떤 이슈를 먼저 해야 하는지 아무도 모른다.
- "MCP `createIssueLink`로 링크했다" → 방향이 반대다. `acli` + `--in`=선행으로 다시.
- "`acli` 성공 메시지가 `A Blocks B`로 나왔으니 맞다" → 그 메시지는 거꾸로 찍힌다. `view`의 inward/outward로만 판정한다.
- "링크 명령을 한 번에 다 실행했다" → 7-3 ①②③ 위반. 첫 1건 방향 확인 후 나머지.
- "작업 순서상 A 다음 B니까 링크했다" → 블로커가 아니면 링크하지 않는다.
