---
name: feature-memory
description: 피처(Jira Epic 단위) 진행 현황을 Jira·Slack·Notion·GitHub에서 자동 수집해 Notion 페이지에 markdown 보고서로 갱신하는 스킬. 사용자가 'feature-memory', '피처 현황', '피처 진행 상황', '피처 상태', '진행 현황 갱신', '진행 상황 업데이트', '피처 보고서', '피처 트래킹', '피처 추적' 등 피처 진행 현황 보고서 생성/갱신/조회를 요청할 때 이 스킬을 사용해야 한다. 매일 새벽 Claude Code의 /schedule routine으로 자동 호출되며, 수동 호출도 동일하게 동작한다. 단순 Jira 이슈 작업(create-jira-issue)이나 일일 업무 기록(snippet)에는 사용하지 않는다.
argument-hint: "[bootstrap | register <epic-key> | <epic-key> | batch | list [--all] | unregister <epic-key> | reactivate <epic-key>]"
model: sonnet
---

# feature-memory — 피처 진행 현황 자동 추적

피처(Jira Epic) 단위로 Jira·Slack·Notion·GitHub의 정보를 한 페이지로 모아 Notion에 markdown 보고서로 갱신한다. Claude Code의 `/schedule` routine과 결합하면 매일 새벽 무인으로 돌아가서, 출근 전에 모든 피처의 최신 진행이 정리되어 있다.

## 기본 정보

> 처음 사용 시 한 번만 채워 넣는다. 모든 값이 비어 있어도 `bootstrap` 서브커맨드로 자동 생성된다. **사용자 본인 정보는 여기 하드코딩하지 않는다 — 갱신 시점에 자동 fetch한다 (아래 "본인 식별" 섹션).**

- **Notion DB data source ID**: `314333d2-57ac-4f15-8fa2-12cee61130e1`
- **Notion DB URL**: `https://www.notion.so/prnd/2a8082b2a37548b6bd5ccae62a402f51?v=393bc3f64a1e4bb8b429064ba09534a0`
- **Notion DB 부모**: workspace root (다른 페이지 아래에 있지 않음)
- **Jira project key (필터링 보조)**: `HDA`
- **Atlassian cloudId**: `4e8e1a3d-2b6f-40df-820b-43c476f41656` (prndcompany.atlassian.net)
- **Atlassian site URL**: `https://prndcompany.atlassian.net`
- **GitHub org**: `PRNDcompany`

## 본인 식별 (런타임 자동 fetch)

> 본인 정보(Slack user_id, Jira accountId, GitHub login, 표시명)는 SKILL.md에 하드코딩하지 않는다. 매 갱신 시작 시 아래 3개 호출로 자동 추출하여 메모리에 캐싱한다. 다른 사용자가 이 skill을 가져다 써도 수정 없이 동작해야 한다.

매 갱신 STEP 2.1 시작 시 다음을 병렬 호출하여 본인 정보를 확보한다:

1. **Jira 본인**: `mcp__claude_ai_Atlassian__atlassianUserInfo()` → `accountId`, `displayName`, `email`
2. **Slack 본인**: `mcp__claude_ai_Slack__slack_search_users(query=email_from_jira)` → `user_id`, `display_name`, real_name 매핑
3. **GitHub 본인**: `gh api user --jq '.login'` (또는 git config `user.email` 매칭) → `login`

캐싱: 한 세션 내 같은 정보는 재사용한다. 캐시 키 = `(jira_account_id, slack_user_id, github_login)`.

**알림 채널**: 본인 Slack user_id를 그대로 channel_id로 사용하여 DM 전송 (`slack_send_message(channel_id=<self_slack_user_id>, text=...)`).

**역할 추론**: Jira 이슈의 본인 assignee/comment 패턴이나 GitHub 리포 이름 컨벤션 등으로 역할(예: "Android 개발자", "iOS 개발자", "서버 개발자")을 추론한다. 명시적으로 모르면 "개발자" 정도로 두고 영향 판단 시 보수적으로 처리 (모든 API 변경을 FYI 후보로 본다).

## 동작 개요

```
┌──────────────────────────────────────────────────────────────┐
│ /schedule routine  (매일 06:00 KST)                          │
│   prompt: "/feature-memory batch"                            │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ batch (STEP 6)                                                │
│   Notion DB의 모든 페이지 조회 → 각 epic_key 추출            │
│   각 피처에 대해 STEP 2~5 순차 실행 (cascade-free)            │
│   완료 후 결과 요약을 Slack 알림 1회 송신                     │
└────────────────┬─────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────┐
│ <epic-key>  (per-feature, STEP 2~5)                          │
│  STEP 2: 5 소스 병렬 수집  ┌─ Jira (Epic + 하위 + 코멘트)    │
│          since last_run_at  ├─ Slack (각 스레드)             │
│                             ├─ Notion (기획/회의록/API)      │
│                             ├─ GitHub PR                     │
│                             └─ Figma (디자인 파일/프레임)    │
│          Fail-soft: 한 소스 실패해도 나머지로 진행            │
│  STEP 3: markdown 본문 조합 (9 섹션)                          │
│  STEP 4: 체크박스 sweep + 섹션별 부분 패치                    │
│  STEP 5: page property 갱신 + 실패 시 Slack 알림              │
└──────────────────────────────────────────────────────────────┘
```

## 서브커맨드

| 커맨드 | 동작 |
|---|---|
| `bootstrap` | Notion DB와 알림 채널을 처음 셋업한다 (1회만 호출) |
| `register <epic-key>` | 새 피처를 등록한다 (Notion DB에 빈 페이지 생성, `status = active`) |
| `<epic-key>` | 단일 피처의 보고서를 갱신한다 (보관된 피처는 자동 skip) |
| `batch` | `status = active`인 모든 피처의 보고서를 순차 갱신한다 (routine 진입점) |
| `list [--all]` | 등록된 피처 목록을 표시한다. 기본은 `status = active`만, `--all`이면 보관 포함 |
| `unregister <epic-key>` | 피처를 보관 처리한다 (`status = archived`, 페이지는 그대로 유지·batch 대상 제외) |
| `reactivate <epic-key>` | 보관된 피처를 다시 활성화한다 (`status = active`) |

사용자 입력: `$ARGUMENTS`

## STEP 0: 인자 파싱 및 라우팅

`$ARGUMENTS`를 공백으로 분리해 첫 토큰을 서브커맨드로 판정한다.

| 첫 토큰 | 라우트 |
|---|---|
| `bootstrap` | STEP 1 |
| `register` | STEP 1B (두 번째 토큰을 epic_key로 사용) |
| `list` | STEP 7 (두 번째 토큰이 `--all`이면 보관 포함) |
| `unregister` | STEP 8 (두 번째 토큰을 epic_key로 사용) |
| `reactivate` | STEP 9 (두 번째 토큰을 epic_key로 사용) |
| `batch` | STEP 6 |
| 그 외 `[A-Z]+-\d+` 패턴 | STEP 2 (단일 피처 갱신) |
| 그 외 | "사용법" 표시 후 중단 |

서브커맨드 식별 실패 시 아래 사용법을 그대로 출력한다.

```
사용법:
  /feature-memory bootstrap                                       1회 셋업
  /feature-memory register HDA-12345                              새 피처 등록
  /feature-memory HDA-12345                                       단일 피처 갱신
  /feature-memory batch                                           활성 피처 일괄 갱신
  /feature-memory list [--all]                                    등록 피처 조회 (--all: 보관 포함)
  /feature-memory unregister HDA-12345                            피처 보관 (batch 제외)
  /feature-memory reactivate HDA-12345                            보관된 피처 재활성화
```

## STEP 1: bootstrap (최초 1회)

1. 본 SKILL.md의 "기본 정보" 섹션을 직접 읽어 두 값의 빈/채워짐을 확인한다.
2. **Notion DB data source ID가 비어 있으면**:
   - `mcp__claude_ai_Notion__notion-create-database`로 "Feature Status DB" 생성
   - properties는 아래 "Notion DB 스키마" 표 그대로
   - 응답에서 `data_source_id`(또는 동등 ID 필드)를 추출해 사용자에게 표시
   - **자동 갱신 안내**: 본 SKILL.md의 `{TODO: bootstrap이 채움}`을 추출된 ID로 직접 교체하도록 사용자에게 안내. (자동 self-edit이 가능하면 수행, 안 되면 사용자에게 직접 채우라고 한다.)
3. **알림 Slack 대상**:
   - 기본 동작은 본인 DM (런타임 fetch한 `self.slack_user_id`를 그대로 channel_id로 사용). bootstrap에서 별도 채널 지정이 필요 없으면 이 단계는 skip.
   - 다른 채널로 알림을 보내고 싶으면 사용자에게 채널명을 묻고 `mcp__claude_ai_Slack__slack_search_channels`로 ID 조회 후 SKILL.md "기본 정보"에 `알림 Slack 채널 override`로 추가.
4. Notion DB ID가 채워졌으면 `register`로 첫 피처를 등록하라는 다음 단계를 안내하고 종료한다.

## STEP 1B: register

`/feature-memory register HDA-12345`

> **SSOT 원칙**: 외부 링크(Notion 기획서, Slack 스레드, Figma 디자인 등)는 **Jira 이슈가 유일한 출처(Single Source of Truth)**다. register는 URL을 받지 않는다. URL이 누락됐다면 **Jira 이슈 본문/코멘트/웹 링크에 추가**하면 다음 갱신부터 자동 반영된다.

1. "기본 정보"의 Notion DB ID가 비어 있으면 "bootstrap을 먼저 실행하라" 안내 후 중단.
2. `epic_key` 중복 확인: Notion DB의 `epic_key` property로 검색.
   - `status = active`로 이미 있으면 → "이미 등록된 피처입니다. 갱신하려면 `/feature-memory {epic_key}`" 안내 후 중단
   - `status = archived`로 이미 있으면 → "보관된 피처입니다. 활성화하려면 `/feature-memory reactivate {epic_key}`" 안내 후 중단
3. Jira에서 Epic 정보 조회 (`mcp__claude_ai_Atlassian__getJiraIssue`, fields: `summary,status,priority,issuetype`):
   - `issuetype.name`이 Epic이 아니면 경고 후 진행 (Story/Task도 허용)
   - `summary` → 페이지 제목 후보
4. Notion DB에 새 페이지 생성 (`mcp__claude_ai_Notion__notion-create-pages`):
   - 제목: `{epic_key} - {summary}`
   - properties:
     - `epic_key` = `HDA-12345`
     - `status` = `active` (보관/활성 구분 — STEP 6/7/8/9에서 사용)
     - `registered_at` = 현재 시각
     - `last_run_at` = empty
     - `last_error` = ""
     - `figma_frame_hashes` = "" (첫 갱신 시 `{}`로 초기화됨)
   - 본문 블록은 비워둠 (첫 갱신 시 채워짐)
5. 생성된 페이지 URL을 표시하고 첫 갱신 안내: "`/feature-memory {epic_key}`로 첫 갱신을 실행하세요. URL은 Jira 이슈에서 자동 추출됩니다."

## STEP 2: 단일 피처 갱신 `<epic-key>`

> **핵심 원칙**: 외부 링크(Notion 기획서, Slack 스레드, Figma 디자인 등)는 **Jira 이슈 자체에서 자동 추출**한다. 사용자가 직접 URL을 입력하는 경우는 거의 없다. page property의 URL 필드들은 *Jira에 안 적힌 URL을 보강하고 싶을 때만 쓰는 폴백*이다.

### 2.1 페이지 lookup + 1차 Jira fetch (병렬)

> **⛔ 강제 게이트 — 본문 fetch는 반드시 첫 단계에서 수행**
>
> 매 갱신 시작 시 **Notion 페이지 lookup + 본문 fetch를 항상 한 번에**(`mcp__claude_ai_Notion__notion-fetch(page_id)`) 호출한다. 본문을 못 가져온 상태에서는 절대 `replace_content`를 호출하지 않는다 — 사용자가 페이지에서 체크한 `- [x]` 상태가 사라진다.
>
> **체크는 소스 변경과 별개 신호다.** 사용자가 `- [x]`로 체크한 항목은 다음 갱신에서 `## ✅ 완료된 항목`으로 옮기고 상단(🎯/⚠️)에서 제거해야 한다. **처리 알고리즘 상세는 STEP 4.1 체크박스 sweep 참조** — 여기 중복 기술하지 않는다 (한 곳에만 둔다).
>
> **이 게이트를 어기면 사용자가 페이지에서 한 체크가 매 갱신마다 초기화된다.** 갱신 첫 응답에 본문 fetch tool_use가 보이지 않으면 즉시 중단하고 추가한다.
>
> **⛔ last_run_at-only 종료 금지.** 5 소스 신규 0건이어도 STEP 4 체크박스 sweep은 **항상 실행**한다. 사용자 체크(`- [x]`)는 소스 변경과 무관한 별도 신호다. "멱등이니 last_run_at만 갱신" 하고 본문 처리를 건너뛰면, 사용자가 체크한 항목이 ✅로 이동되지 않고 상단(🎯/⚠️)에 영원히 잔존한다.

1. Notion DB에서 `epic_key` property로 페이지 lookup (`mcp__claude_ai_Notion__notion-search` 또는 동등 조회).
   - 없으면 "등록되지 않은 피처입니다. `/feature-memory register {epic_key}`로 먼저 등록하세요." 안내 후 중단.
   - `status = archived`이면 "보관된 피처입니다. 갱신하려면 `/feature-memory reactivate {epic_key}`로 먼저 활성화하세요." 안내 후 중단. (보관된 페이지를 갱신해 본문이 바뀌면 보관 의도가 흐려지므로 명시적 활성화를 강제.)
2. **page_id가 확인되면 즉시** `mcp__claude_ai_Notion__notion-fetch(page_id)`로 **전체 본문**을 가져온다. (page property + 본문 markdown 모두 포함) — 위 강제 게이트 적용 대상.
3. **본인 식별 fetch** — 상단 `## 본인 식별` 절차(3-call 병렬)를 수행해 `self.jira_account_id`·`self.display_name`·`self.email`·`self.slack_user_id`·`self.slack_display_name`·`self.github_login`를 확보한다 (한 세션 1회 캐싱). 호출 상세는 그 섹션 참조 — 여기 중복 기술하지 않는다.
4. **동시에** Jira에서 Epic 정보 fetch: `mcp__claude_ai_Atlassian__getJiraIssue(issueIdOrKey=epic_key, fields=["summary","status","priority","description","comment","subtasks","parent","labels","components","updated","assignee","issuetype"], responseContentFormat="markdown")` 1회
   - markdown 포맷이면 description/comment 본문 안의 hyperlinks가 `[text](url)` 형태로 그대로 보존됨 → URL 추출이 쉬움
5. 추가로 remote issue links 조회: `mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks(epic_key)` — Jira의 "웹 링크" 필드에 등록된 URL들 (Notion 페이지 등이 종종 여기에 붙어 있음)
6. page property에서 `last_run_at` 추출. 없으면 `since = now - 30일`.

### 2.2 URL 자동 추출 + 도메인별 분류

Jira 응답(description + 모든 comment + remote links + subtasks의 description)에서 모든 hyperlinks를 정규식 또는 markdown 파싱으로 추출한다. 추출 대상은 `https?://` 시작 URL 전체.

도메인별로 분류:

| 도메인 패턴 | 분류 | 처리 |
|---|---|---|
| `*.notion.so`, `*.notion.site` | **Notion** | `notion-fetch`로 last_edited_time 비교 + 본문 요약 |
| `*.slack.com/archives/...` | **Slack** | `slack_read_thread`로 스레드 읽기 |
| `figma.com/design/...`, `figma.com/board/...` | **Figma** | `get_design_context` 우선 → 실패 시 `get_screenshot` 폴백. **페이지 단위 노드면 추가로 `get_metadata` 호출 → 임시 파일에서 직계 자식 frame 목록 추출** (jq + grep, token-cheap) |
| `github.com/PRNDcompany/...` | **GitHub** (PR/issue) | URL로 직접 fetch 또는 search 결과와 dedup |
| 그 외 | **Extra** | 본문 "참고 링크"에 단순 링크 표시 (fetch 안 함) |

**SSOT 원칙**: URL은 모두 Jira 이슈에서 추출한다. page property에 별도 URL 필드는 두지 않는다. 누락된 URL이 있으면 Jira 이슈 본문/코멘트/웹 링크에 추가하여 다음 갱신에 자동 반영.

### 2.3 5 소스 병렬 dispatch — **반드시 한 번의 응답 메시지에 모든 tool_use 호출을 함께 보낸다**

- **Jira 활동 (이미 fetch된 응답 재사용)**: `comment.comments`에서 `created >= since` 필터. subtask 상태는 응답에 포함됨
- **Slack**: 분류된 Slack URL 각각을 `~/.claude/rules/external-links.md` 규칙으로 `channelId`+`threadTs` 추출 → `slack_read_thread` (스레드 ts 있을 때) 또는 `slack_read_channel` (채널 전체) 병렬 호출. **`response_format="detailed"` 필수** — 각 메시지의 `ts` 필드를 보존해야 본문에 영구 링크(`https://prnd.slack.com/archives/{channel_id}/p{ts_without_dot}` — `ts`에서 `.` 제거)를 부착할 수 있다. `ts >= since`만 채택.

  > **`oldest` 파라미터는 반드시 Python으로 계산한 Unix timestamp를 넣는다.** LLM이 직접 ISO → Unix 변환 시 약 23시간 오차가 재현된 바 있어 LLM 직접 계산 금지. `slack_read_channel` 호출 직전에 아래 명령으로 계산하고, 그 값을 `oldest`에 그대로 넘긴다:
  >
  > ```bash
  > python3 -c "
  > from datetime import datetime, timezone
  > import sys
  > dt = datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))
  > print(dt.timestamp())
  > " "<last_run_at_ISO>"
  > ```
  >
  > 응답 `ts` 값은 여전히 `>= since_ts` 조건으로 한 번 더 검증한다 (API 경계 반올림 여유).
  >
  > **⛔ top-level만 보지 말고 thread 내부까지 전개한다.** `slack_read_channel`은 top-level 메시지만 반환한다 — thread reply 안의 본인 발화는 보이지 않는다. reply ≥1인 스레드 중 **(a) parent author가 본인, (b) parent에 본인 멘션, (c) 최신 reply ts ≥ since** 중 하나라도 해당하면 `slack_read_thread`로 전개해 내부 reply까지 검사한다. 특히 **본인 발화(author=self)가 스레드 마지막이고 멘션을 포함하는데 이후 reply 0 + reaction에 타인 없음 → 미응답 TODO 후보**(STEP 2.5). top-level만 보면 이 케이스를 통째로 놓친다 (실제 누락 사례 있었음).
- **Notion 기획/API 문서**: 분류된 Notion URL 각각에 `notion-fetch` 병렬 호출. `last_edited_time >= since`만 채택, 변경됐으면 본문 요약 추출
- **GitHub PR**: `gh search prs "{epic_key} in:title" --owner PRNDcompany --json title,number,url,state,updatedAt,author,createdAt,repository --limit 30` + Jira에서 추출된 GitHub URL과 합치기. `updatedAt >= since`만 채택
- **Figma**: 페이지 단위 nodeId는 `get_design_context`가 항상 실패(`선택된 레이어 없음`)하므로 **frame 단위로 우회**한다.
  - **① frame 목록 추출** — `get_metadata`(페이지) → 임시 파일에서 `jq`+`grep`+`sed`로 직계 자식 frame 추출. `__skip__` 여부 무관 **항상 수행**, 매 갱신 전량 재생성, 유령 frame 제거. `화면`/`부품·에셋` 2그룹 분리, name 원문 유지.
  - **② frame별 hash diff** — frame마다 `get_design_context(excludeScreenshot=true)` 병렬 호출 → `data-node-id`·asset URL 제거 후 SHA-256 → `figma_frame_hashes` property와 비교해 신규/변경 감지. `__skip__`이면 ②만 생략.
  - **③ 변경 기록** — 신규/변경/삭제 frame은 `## 변경 이력`에 prepend(🔄 마커), 변경 frame 코드는 Reference `Figma 디자인 컨텍스트` toggle에 보존.
  - **상세 절차(`jq`/`sed`/`shasum` 전체 명령, 화면/부품 분류 가이드, 비용 제어, 실패 처리)는 → [`figma-tracking.md`](figma-tracking.md) 참조.**

### 2.4 Fail-soft 처리
- 각 소스의 응답을 개별 try-catch. 실패한 소스는 `source_status[<source>] = {ok: false, error: "..."}`로 기록
- 한 소스 실패해도 STEP 3 진행
- **추출된 URL이 0개인 소스**는 실패가 아니라 "관련 링크 없음"으로 표시 (✅ 회색 또는 ⚪)

### 2.5 사용자 작업 / 영향 추출 (보고서 우선순위 필터링)

> **본 보고서는 본인 시점**이다. "본인"은 위 "본인 식별" 섹션에서 런타임 fetch한 (Jira accountId, Slack user_id, GitHub login, display_name)를 사용한다. SKILL.md에 특정 사용자 ID를 하드코딩하지 않는다.

수집된 데이터에서 다음을 별도 리스트로 분류:

**A. 내가 해야 할 일 (TODO)**

> **⛔ Jira assignee 이슈는 TODO에 올리지 않는다.** 사용자는 Jira를 직접 관리하므로 이미 인지하고 있다. Jira에서 본인이 assignee인 Epic·subtask를 feature-memory에서 다시 나열하는 것은 중복 소음이다. Jira 상태 변경(예: Backlog → In Progress, Ready to Deploy)은 변경 이력에만 기재한다.

- Jira 코멘트에서 본인 멘션(displayName 매칭 또는 accountId 매칭) + 응답 필요한 질문 (단, 아래 "Slack/멘션 책임 게이트" 동일 적용)
- **Slack에서 본인 명시 멘션**(`<@{self.slack_user_id}|{self.slack_display_name}>` 또는 `<@{self.slack_user_id}>` 패턴)된 메시지 중 **아래 책임 게이트를 통과한** 항목
- 본인이 질문자(Slack/기획서 Q&A)인 항목 중 답변 안 받은 것
- 마감 있는 작업 (예: QA 공유 예정일이 본인 담당) — Slack/Notion/기획서에서 확인된 것
- 본인이 결정/실행해야 할 미해결 항목 (Slack 스레드, 기획서 Q&A 등 Jira 외 소스)
- **본인 구현 영향 결정인데 본인 액션(구현·응답) 미완**인 항목 — 예: API 필드 추가가 결정됐으나 클라 반영 전, 본인 질문이 답변받았으나 후속 작업 안 한 것. (단 책임 게이트로 "타인 처리"로 판정되면 제외)

**B. 나에게 영향 주는 변경 (FYI)** — **결정 vs 논의 분리**

> **확정 결정은 게이트·멘션·참여 여부와 무관하게 올린다.** 책임 게이트와 본인 명시 멘션 요건은 아래 **B-2(논의/질문)**에만 적용한다. 누가 어디서(주로 Slack) 결정했든, 출처가 Slack이고 olaf가 멘션·참여 안 했어도, **olaf 역할(클라 개발자)에 영향 가는 확정 결정이면 ⚠️에 올린다.** (지난 운영에서 결정사항이 olaf 참여 스레드라는 이유로 "단순 논의"로 묶여 최근 활동에만 강등된 게 상단이 비던 핵심 원인.)

**B-1. 확정 결정 (게이트 무관 — 무조건 ⚠️ 후보)**
- API 명세 변경 (필드 추가/변경/삭제, 응답 구조, enum 값)
- 로그/트래킹 변경 (referrer·이벤트·파라미터 추가)
- 분기/조건 키 결정 (예: `car_list_banners` 유무로 타입 분기)
- UI 규칙 확정 (배너 비율·정렬, 컴포넌트 스펙)
- QA·릴리스 일정 변경/확정
- A/B 노출 범위, 새 의존성·외부 요구사항
- **휴리스틱**: "이 결정 때문에 olaf가 코드를 고쳐야 하나?" → 예면 ⚠️.

**B-2. 논의/질문 (게이트 적용 — 통과 시에만 ⚠️)**
- 아직 **미확정**인 Slack 논의/질문은 본인 명시 멘션 + 책임 게이트 통과 시에만 포함.
- 멘션 없는 미확정 논의는 Reference/최근 활동으로.

**C. 그 외 일반 컨텍스트** (Reference로 강등)
- 기획서 본문, API 명세 전체, Q&A 전체, 회의록 — 평소엔 안 봐도 되고 필요 시 펼쳐 보는 정보
- **본인 멘션이 없는 Slack 논의** (다른 사람들끼리의 결정 과정) — 정보로만 남기되 TODO/FYI 최상단엔 띄우지 않음

**추출 시 멘션 인식 규칙**
- Slack: `<@{self.slack_user_id}|{self.slack_display_name}>` 또는 `<@{self.slack_user_id}>` 패턴 (런타임 fetch한 본인 정보 사용)
- Jira: `accountId` 비교 (런타임 fetch한 `self.jira_account_id`와 매칭)

**Slack/멘션 책임 게이트 (핵심 분류 룰)**

> 사용자 시점에서 *진짜로 본인이 해야 할 것*만 TODO에 올리기 위한 필터. 멘션 자체보다 "현재 처리 책임이 본인에게 있는가"를 본다.

본인이 명시적으로 멘션된 Slack 메시지(또는 Jira 코멘트)라도, 아래 조건 중 하나라도 만족하면 **TODO/FYI 최상단에서 제외**한다. 출처는 `최근 활동`/`변경 이력`/`Reference`에만 남긴다.

1. **본인이 이미 응답한 경우** — 본인 user_id의 reply 메시지가 같은 스레드에 있거나, 본인이 메시지에 emoji reaction을 단 경우 (`reactions[].users`에 본인 user_id 포함)
2. **다른 사람이 본인 대신 처리한 경우** — 멘션된 메시지가 결정·답변·구현 응답을 이미 받은 상태:
	- 같은 스레드에 결정자(@allen, @jenna, @johnny 등)의 명시적 답변이 있음
	- 후속 PR/커밋/Jira 이슈가 이미 만들어진 경우 (예: HDA-XXXXX로 후속 작업 분리)
	- 메시지에 결정자의 reaction(예: `:check:`, `:ok_hand:`, `:thumbsup:`)이 달림 — 다른 사람이 confirm한 신호
3. **메시지가 본인 외 멘션 + 본인은 cc/관전 위치**인 경우 (예: `<@allen> cc. <@brandan>` — 본인 멘션 아님)

본인 멘션 + 위 게이트를 **통과한** 메시지만 (= 아무도 처리 안 했고 본인이 응답 안 한 것) TODO/FYI 후보가 된다.

**구현 메모**
- `slack_read_thread`/`slack_read_channel` 응답에서 `reactions` 필드와 thread `replies`를 함께 확인한다. `response_format="detailed"`면 reactions의 user 목록이 포함된다.
- 본인 user_id(`self.slack_user_id`)가 reactions[].users에 한 번이라도 등장하면 "본인 응답함"으로 간주.
- 같은 스레드의 reply 중 본인 user_id가 author인 메시지가 있으면 "본인 응답함".
- **thread 내부 본인 발화도 검사한다** (top-level만 보면 누락): 본인이 reply 단 스레드를 `slack_read_thread`로 전개해, 본인의 **마지막 발화**가 질문·요청·멘션인데 이후 타인 reply·reaction이 없으면 "답변 못 받음" → TODO 후보. `slack_read_channel`은 top-level만 반환하므로 전개가 필수다.
- 본인 멘션이 없거나 게이트 통과 못 하는 항목은 `## 최근 활동`/`## 변경 이력`에는 기록하되 TODO/FYI 섹션엔 띄우지 않는다.
- API/기획 문서의 **공식 결정 변경**(Notion 문서 변경, 명세 갱신 등)은 Slack 룰과 별개로 B(FYI)에 포함된다. Slack 룰은 "Slack 대화" 자체에만 적용.
- Notion 기획서: 본인 표시명 (display_name) 또는 `<mention-user url="user://{notion_user_id}"/>` 패턴으로 매칭. Notion user_id ↔ Slack/Jira 매핑이 불확실하면 표시명으로 텍스트 매칭으로 폴백.

## STEP 3: markdown 본문 조합

> **본문 철학**: 이 페이지는 피처의 **메모리/지식 베이스**다. 한 페이지를 열어 모든 기획 결정·논의·합의를 볼 수 있도록, **기획서/API 문서/회의록의 본문을 거의 통째로 인용**한다. 압축보다 포함이 우선이며 **기획·결정·변경은 절대 생략 금지**, 구현 상세(세부 컴포넌트 구조, 로그 필드 풀 리스트 등)는 길어지면 요약 가능.
>
> **출처 추적성 규칙**: 모든 기획 결정·Q&A 답변·변경 이력 항목에는 **원본 출처**가 추적 가능해야 한다. "어디서 그 결정이 나왔는지"를 클릭 한 번에 볼 수 있어야 메모리의 가치가 산다.
>
> **출처 표기 방식 — 도메인 라벨 인라인 링크로 통일**:
>
> 모든 섹션(TODO·FYI·최근 활동·변경 이력)의 모든 항목에 인라인 markdown 링크로 출처 표기. **라벨은 도메인 기반**으로 통일:
> - Slack 출처 → `[Slack](url)`
> - Notion 기획서/API 문서/회의록 → `[Notion](url)`
> - Jira 이슈/코멘트 → `[Jira](url)`
> - Figma 디자인 → `[Figma](url)`
> - GitHub PR/이슈 → `[GitHub](url)` (또는 `[#PR번호](url)`)
>
> `[근거]`, `[원본]`, `[Slack 근거]` 같은 일반 라벨은 사용하지 않는다. 한 항목에 여러 출처가 있으면 `[Slack](url) · [Notion](url)`처럼 가운뎃점으로 나열.
>
> **URL 형식**
> - Slack → `https://prnd.slack.com/archives/{channel_id}/p{ts_without_dot}` (`ts`에서 `.` 제거)
>   - **⛔ thread reply에 `?thread_ts=...&cid=...`를 붙이지 않는다.** Notion이 Slack URL을 `slackMessage://` 앱 딥링크로 자동 변환하면서 쿼리스트링을 버린다 → reply가 채널 최상위에서 안 찾아져 **이동 실패**. thread 안 발화는 **그 스레드 부모 메시지의 top-level 링크**(`p{parent_ts}`)를 쓰고 라벨을 `[Slack 스레드]`로 표기한다. reply 정확 위치 점프는 Notion 한계로 불가.
>   - **⛔ `ts`는 반드시 수집한 메시지의 실제 값(`slack_read_*` 응답의 `Message TS`)만 쓴다. 추측·생성 금지** — 잘못된 ts는 죽은 링크가 된다.
> - Notion → `https://www.notion.so/{page_id}` (블록 anchor 가능하면 부착)
> - Jira 코멘트 → `{jira_url}?focusedCommentId={comment_id}`
> - GitHub PR/이슈 → PR URL 그대로
> - Figma → `https://figma.com/design/{fileKey}/...?node-id={nodeId}`
>
> **inline comment는 더 이상 사용하지 않는다** (이전 명세에서 폐기). 본문에서 출처를 한눈에 확인하는 게 댓글 마커 클릭보다 빠르다.
>
> **markdown 링크 규칙**: `[텍스트](url)` 표준만 사용. `[[텍스트]]` wiki-style 대괄호 2개는 Notion이 inline link로 못 잡아 URL이 노출되므로 금지.

**섹션 순서 (사용자 시점 우선)**: 본인 작업과 영향을 최상단에, 일반 기획·API 명세는 reference로 강등.

1. `## 🎯 내가 해야 할 일` (TODO, 1순위, 체크박스)
2. `## ⚠️ 영향 주는 변경 / 알아야 할 결정` (FYI, 2순위, 체크박스)
3. `## ✅ 완료된 항목 (자동 보관)` (체크된 TODO/FYI 누적, dedup 기준)
4. `## 한눈에 보기` (메타·링크)
5. `## 현재 상태` (Jira 상태, 진척, 진행 중 작업)
6. `## 최근 활동` (시간 역순)
7. `## 변경 이력` (누적 prepend)
8. `## 데이터 소스 상태`
9. `## 📚 Reference` (Notion `<details>` toggle 또는 명시 구분선 아래, 평소엔 안 봄)
   - 기획 내용 (Notion 기획서 인용)
   - API 명세 (Notion API 문서 인용)
   - Q&A 전체 (기획서 질문 남기기 모든 항목)
   - 회의록 핵심 결정

각 섹션 상세:

### `## 🎯 내가 해야 할 일`

STEP 2.5의 A 리스트를 **체크박스**로 출력. 우선순위 순으로.

**항목 형식 — 하위 bullet으로 분리** (한 줄에 메타+본문+링크를 모두 우겨넣지 않는다):

```markdown
- [ ] 🔥 **작업 제목**
    - 본문 설명 1~2 문장 (필요 시 여러 줄)
    - 마감/요청자/관련 시안 등 추가 컨텍스트
    - [Slack](url) · [PR](url)
```

본문이 짧고(한 문장 이하) 링크도 1개 이하인 항목은 한 줄로 둬도 된다. 본문이 두 문장 이상이거나 링크가 2개 이상이면 반드시 하위 bullet으로 분리한다.

우선순위 마커:
- 🔥 **블로커**: 다른 작업·다른 사람을 막고 있음, 마감 임박
- ⚡ **이번 주**: QA 일정, 의존 작업 시작 전 끝나야
- 📌 **있음**: 일반 TODO, 마감 없음

체크박스 규칙:
- 새로 추출된 항목은 모두 미체크(`- [ ]`)
- 사용자가 페이지에서 체크(`- [x]`)한 항목은 **이 섹션에서 제거**하고 `## ✅ 완료된 항목 (자동 보관)` 섹션으로 이동 (아래 STEP 4 룰)
- 이전 갱신에서 미체크였던 항목은 그대로 보존 (체크 상태 절대 임의 변경 금지)

빈 리스트면 "현재 본인 TODO 없음" 1줄 표시.

### `## ⚠️ 영향 주는 변경 / 알아야 할 결정`

STEP 2.5의 B 리스트를 **체크박스**로 출력. 시간 역순. 도메인 라벨 자체가 클릭 가능한 링크.

**항목 형식 — 하위 bullet으로 분리** (위 "내가 해야 할 일"과 동일한 가독성 룰):

```markdown
- [ ] (2026-05-12 16:11) [Notion] **변경 요약**
    - 본인 영향 1~2 문장
    - 세부 변경점 (필요 시 nested bullet)
    - [Notion](url)
```

본문이 짧고 링크가 1개 이하면 한 줄로 둬도 된다. 본문이 두 문장 이상이거나 링크가 2개 이상이면 반드시 하위 bullet으로 분리한다.

체크박스 규칙은 위 "내가 해야 할 일"과 동일. 체크된 항목은 다음 갱신 시 완료 섹션으로 이동.

빈 리스트면 "최근 변경 중 본인 작업에 영향 주는 항목 없음" 1줄 표시.

### `## ✅ 완료된 항목 (자동 보관)`

지난 갱신까지 사용자가 체크한 TODO/영향 항목이 모이는 섹션. 이번 갱신에서 새로 체크된 항목은 여기로 이동. **dedup 기준** — 새 후보 추출 시 항목명이 여기 있으면 중복으로 간주하고 다시 추가하지 않음.

```markdown
## ✅ 완료된 항목 (자동 보관)

- ✅ (YYYY-MM-DD에 체크됨) [TODO] **작업명** — 원본 설명. [근거](url)
- ✅ (YYYY-MM-DD에 체크됨) [FYI] **변경 요약** — 원본 설명. [근거](url)
```

200건 초과 시 가장 오래된 100건은 `<details>` toggle로 접어둠.

### `## 한눈에 보기`

```markdown
## 한눈에 보기

- **피처**: {epic_key} {Epic 제목} (parent: [{parent_key} {parent_summary}]({parent_url}))
- **Jira 상태**: {status} (이슈타입: {issuetype}, 우선순위: {priority}, label: {labels})
- **담당**: @{assignee}
- **하위 이슈 진척**: {done}/{total} ({percent}%) — subtask 0건이면 "0건 (parent 산하 분산)" 표기
- **A/B 테스트 키**: `{ab_test_key}` (API 문서에 명시되어 있으면)
- **링크**: [Jira Epic]({jira_url}) · [기획서]({notion_plan_url}) · [API 문서]({notion_api_url}) · [Slack 채널]({slack_url}) · [Figma]({figma_url})
```


### `## 현재 상태`

- Jira Epic `description`을 markdown 변환 (보통 외부 링크만 정리되어 있어 짧음)
- 하위 이슈 표 (subtask 있을 때):
  ```markdown
  | 키 | 제목 | 상태 | 담당 |
  |---|---|---|---|
  | HDA-12346 | 로그인 UI | In Progress | @olaf |
  ```
- 개발 소요 시간 — Jira 코멘트에서 추출 ("개발 소요" 키워드 매칭)
- 진행 중 작업 — 최근 1주 Slack 활동에서 추정한 unblocked/blocked 상태

### `## 최근 활동`

- 5 소스의 `since` 이후 활동을 **시간 역순**으로 최대 N=20개
- 항목 형식 (1줄):

```markdown
- (YYYY-MM-DD HH:MM) [Jira](url) @작성자 — 코멘트 1줄 요약
- (YYYY-MM-DD HH:MM) [Slack](url) @작성자 — 메시지 1줄 요약
- (YYYY-MM-DD HH:MM) [Notion](url) @편집자 — "{문서 제목}" 갱신
- (YYYY-MM-DD HH:MM) [GitHub](url) @작성자 — PR #1234 {제목} [{state}]
- (YYYY-MM-DD HH:MM) [Figma](url) @편집자 — "{프레임/파일명}" 변경
```

도메인 라벨 자체가 링크. `[원본]` `[근거]` 같은 별도 라벨은 사용하지 않음.

### `## 변경 이력` (누적, 신규만 prepend)

- **기존 페이지의 이 섹션을 먼저 fetch** → 신규 항목을 위에 prepend
- 항목 형식: `- (YYYY-MM-DD) · [Slack](url) · 1줄 요약` — 도메인 라벨 자체가 클릭 가능한 링크. `[Slack]`, `[Notion]`, `[Jira]`, `[Figma]`, `[GitHub]` 중 출처에 맞는 라벨 사용. `[근거]` `[원본]` 같은 일반 라벨 금지
- `[[텍스트]]` 같은 wiki-style 대괄호 2개는 Notion이 inline link로 못 잡아 URL이 노출되므로 절대 쓰지 말 것
- **기획적 변화에 가중치**: 단순 채팅보다 "기획 변경", "API 변경", "Q&A 답변 추가", "회의록 결정" 같은 의미 있는 변경을 우선 기록
- 200건 초과 시 가장 오래된 100건은 `<details>` 블록으로 접어둠

### `## 데이터 소스 상태`

```markdown
## 데이터 소스 상태

- ✅ Jira (코멘트 3건, 하위 이슈 5건, Epic updated YYYY-MM-DD)
- ✅ Slack (메시지 30건, 채널 {channel_id})
- ✅ Notion (기획서 + API 문서, 최근 last_edited YYYY-MM-DD)
- ⚪ GitHub PR (0건 — 검색 결과 없음)
- 🟥 Figma — `MCP server "claude.ai Figma" session expired`

마지막 갱신: YYYY-MM-DD HH:MM KST
```

### `## 📚 Reference` (toggle, 평소엔 접어둠)

평소 보고서에서는 위 6개 섹션만 본다. Reference는 깊이 들어가야 할 때만 펼침. Notion `<details>` toggle을 적극 활용 (또는 `---` 구분선으로 시각 분리).

다음 하위 섹션 포함 (해당 데이터가 있을 때만):

```markdown
## 📚 Reference

<details>
<summary>기획 내용 (Notion 기획서 인용)</summary>

- **목적 (Why)**
- **해결 방향** (모든 항목, 들여쓰기 구조 유지)
- **필요한 데이터 기록 / 트래킹**
- **A/B 테스트** (키, 조건, B안 노출 기능)
</details>

<details>
<summary>Q&A 전체 (기획서 질문 남기기 + Slack 보강 결정 모두)</summary>

질문자별 그룹 → 모든 Q+A 빠짐없이 포함. 답변은 굵게. 출처는 inline comment로 분리.
</details>

<details>
<summary>API 명세 전체</summary>

각 엔드포인트별 query_params·response·시나리오. 공통 파라미터, 로그 수집 명세 포함.
</details>

<details>
<summary>회의록 핵심 결정</summary>

기획서 "회의록" 섹션 + 회의록 페이지 링크. 구두 결정과 번복 사항 모두.
</details>

<details>
<summary>Figma frame 목록 (페이지 단위 직계 자식)</summary>

페이지 단위 nodeId를 받았을 때 STEP 2.3의 `get_metadata` + 임시 파일 추출로 만들어진 표. 화면과 부품·에셋을 분리해 화면을 우선 노출한다.

**화면**

| Frame 이름 | nodeId | 크기 | 링크 |
|---|---|---|---|
| 관심 차 가격 변동 | 488:2586 | 393×812 | [Figma](https://www.figma.com/design/{fileKey}/?node-id=488-2586) |
| (... 표준 디바이스 폭 + 세로로 긴 화면 시안만. Figma name 원문, 동명이면 nodeId로 구별) | ... | ... | ... |

**부품·에셋**

| Frame 이름 | nodeId | 크기 | 링크 |
|---|---|---|---|
| 리스트 끝에 전체보기 | 716:4589 | 132×180 | [Figma](https://www.figma.com/design/{fileKey}/?node-id=716-4589) |
| (... 카드·버튼·이미지 등 부분 요소. 너비<320·가로형·정사각 frame) | ... | ... | ... |

각 frame은 `https://www.figma.com/design/{fileKey}/?node-id={nodeId_with_dash}` (nodeId의 `:`를 `-`로 변환) 형식.
</details>
```

**중요**: Reference 안의 결정·Q&A 항목은 위 "내가 해야 할 일" / "영향 주는 변경" 섹션과 **중복 표시되지 않는다**. 본인 영향 항목은 최상단에만 두고, Reference는 일반 컨텍스트만.

## STEP 4: Notion 페이지 본문 업데이트 (체크박스 sweep + 섹션 패치)

> **사전 조건**: STEP 2.1에서 본문 fetch가 끝나 있어야 한다. fetch 결과 없이 본문 수정 호출 금지. 사용자 체크가 사라지는 근본 원인이 이 단계 누락이다.
> **항상 실행**: 5 소스 신규 0건이어도 이 단계는 건너뛰지 않는다 (체크박스 sweep 때문). `last_run_at`만 갱신하고 종료 금지.

### 4.1 체크박스 sweep (최우선 — 결정적)

> 사용자가 `- [x]`로 체크한 항목을 `## ✅ 완료된 항목`으로 옮기고 상단(🎯/⚠️)에서 제거한다. 과거 누락으로 생긴 중복(상단 `[x]` + ✅ 양쪽 잔존)도 자가 치유한다.

STEP 2.1 본문에서 `## 🎯 내가 해야 할 일`·`## ⚠️ 영향 주는 변경` 섹션의 각 **항목 블록**을 파싱한다. 한 블록 = 체크박스 라인(`- [ ]`/`- [x]`) + 그 아래 들여쓰기 하위 bullet 전부. 블록 경계 = 다음 `- [ ]`/`- [x]` 라인 또는 다음 `## ` 헤더 직전.

각 `- [x]` 블록마다:

1. **✅ 중복 검사.** 항목 제목 정규화 키가 `## ✅ 완료된 항목` 섹션에 이미 있는가?
   - 없음 → ✅ 맨 위에 `- ✅ (YYYY-MM-DD에 체크됨) [TODO|FYI] **{제목}** — {요약}. [출처](url)` 한 줄 추가.
   - 있음 → ✅ 추가 **건너뜀** (과거 누락으로 생긴 중복 케이스).
2. **상단 제거.** 🎯/⚠️에서 그 `- [x]` 블록(제목 + 하위 bullet 전체)을 삭제한다.

> **⛔ 원자성**: 한 항목의 (1)✅ 추가 + (2)상단 제거는 **같은 `update_content` 호출에 두 edit를 함께** 넣는다. 분리하면 한쪽(보통 제거)이 누락돼 상단·✅ 양쪽에 남는 중복이 생긴다 — 이게 기존 버그의 근본 원인이었다.
> ✅에 이미 있어 추가를 건너뛴 경우에도 (2)상단 제거는 **반드시** 수행한다.

미체크(`- [ ]`) 블록은 손대지 않는다 (체크 상태·본문 불변).

### 4.2 sweep 검증 (필수 게이트)

sweep 직후 본문을 재확인해 **🎯/⚠️에 `- [x]` 잔존 = 0**인지 센다. 0이 아니면 잔존 블록을 다시 제거한다. 로그: `체크 N건 → ✅ 이동 M / 중복정리 K / 상단잔존 0`.

### 4.3 신규 후보 추가 + 상단 재평가 (dedup)

STEP 2.5 신규 후보를 기존 미체크 + ✅ 완료 항목과 비교 (정규화 키).
- 미체크에 이미 있음 → 유지 (본문 정보 갱신 가능, 체크 상태 불변)
- ✅에 이미 있음 → 추가 안 함
- 둘 다 없음 → 새 미체크(`- [ ]`)로 추가

**상단 재평가 (필수)** — 추출이 매 실행 `since` 윈도에 갇혀 누락되는 걸 보정한다:

1. **승격.** 이번 수집 데이터(최근 활동·변경 이력에 기록된 것 포함) 중 **olaf 영향 확정 결정**(STEP 2.5 B-1 기준)이 `## ⚠️`에도 `## ✅`에도 없으면 → `## ⚠️`로 **승격**(새 미체크). 즉 "최근 활동/변경 이력에만 있고 ⚠️엔 없는 본인 영향 결정"을 끌어올린다. 같은 항목이 ✅(이미 처리)면 승격 안 함.
2. **기존 미체크 유지.** 상단 기존 미체크 항목은 사용자가 체크 안 했으면 **유지**한다 (자동 제거 금지). 단 **명백 해결**(후속 PR 머지·Jira Done·결정자 종결 코멘트)이 이번 수집에서 확인되면 ✅로 이동.
3. 빈 섹션이면 placeholder("현재 본인 TODO 없음" / "최근 변경 중 본인 작업에 영향 주는 항목 없음") 유지.

### 4.4 나머지 섹션 갱신

- `## 변경 이력`: STEP 3 신규 항목을 위에 prepend (기존 보존, 날짜+소스+요약 키로 dedup).
- `## 한눈에 보기`·`## 현재 상태`·`## 최근 활동`·`## 데이터 소스 상태`: 매번 재생성.

### 4.5 본문 수정 방식 — 부분 패치 기본

`notion-update-page`는 **`update_content`(섹션별 부분 패치)를 기본**으로 쓴다. `replace_content`(전체 재생성)는 본문이 길면 타임아웃·rate limit 위험이 크므로 첫 갱신 등 본문이 거의 빈 경우에만 쓴다.

- 부분 패치는 변경된 섹션만 `old_str`→`new_str`로 교체.
- 단 4.1 sweep의 (✅ 추가 + 상단 제거) 2-edit는 항목당 **동일 `update_content` 호출**에 묶는다 (원자성).
- 체크박스는 `- [ ]`/`- [x]` 형식 그대로 유지.

### 4.6 Rate limit / 타임아웃
- 429 → `Retry-After` 후 1회 재시도.
- `update_content`가 타임아웃나면 더 작은 단위(섹션 1개씩)로 쪼개 재호출.

## STEP 5: page property 갱신 + 알림

1. `mcp__claude_ai_Notion__notion-update-page` command `update_properties`로 page property 갱신:
   - 모든 소스 정상: `last_run_at = now`, `last_error = ""`
   - 일부 소스 실패: `last_run_at = now` (부분 성공도 갱신), `last_error = "Slack: token expired"` 같은 1줄 사유 (여러 실패 시 ` | `로 합침)
2. **일부 소스 실패가 있었다면** 알림 채널로 1줄 메시지 송신:
   ```
   ⚠️ feature-memory {epic_key}: 일부 소스 실패 — {failed sources}
   상세: {Notion 페이지 URL}
   ```
   호출: `mcp__claude_ai_Slack__slack_send_message(channel_id=<self.slack_user_id 또는 알림 채널 override>, text=...)`
3. 콘솔 결과 보고:
   - 성공: `✅ {epic_key} 갱신 완료 (변경 이력 N건 추가)`
   - 부분 성공: `⚠️ {epic_key} 갱신 (실패 소스: {sources})`

## STEP 6: batch (routine 진입점)

0. **1회성 backfill (멱등)**:
   - DB 스키마에 `status` property 자체가 없으면 1회 안내 후 batch 중단: "Notion DB에 `status` select property (`active` · `archived`)를 추가하세요. DB 상단의 `+ Add a property` → `Select` → 옵션 `active`, `archived` 등록. 이후 batch 재실행." (Notion API `notion-update-data-source`로 자동 추가는 시도하지 않는다 — 사용자가 직접 옵션 색상까지 결정할 수 있게 둠.)
   - 스키마는 있지만 페이지의 `status` 값이 비어 있으면 `mcp__claude_ai_Notion__notion-update-page` `update_properties`로 `status = active`로 채운다. 이미 채워진 페이지는 건드리지 않는다.
1. Notion DB에서 `status = active`인 페이지만 조회: `mcp__claude_ai_Notion__notion-search` 또는 DB query (data_source_id 기준 + `status = active` 필터). `status = archived`인 페이지는 batch 대상에서 제외한다.
2. 각 페이지의 `epic_key` property 추출 → list로 정렬 (등록일 순).
3. list 길이가 0이면 알림 채널에 "활성 피처가 없어 batch 종료" 1줄 송신 후 종료.
4. list를 **순차 순회** (병렬 X, Notion API rate limit 보호)하면서 각 epic_key에 대해 STEP 2~5 실행.
5. **Cascade 방지**: 각 피처는 독립 try-catch. 한 피처에서 예외가 던져져도 다음 피처는 계속 실행.
6. 처리 결과를 누적: `success_count`, `partial_count`, `failed_count`, `failed_keys`.
7. 모든 피처 처리 완료 후 batch 요약 알림:
   ```
   📊 feature-memory batch 완료 (2026-05-12 06:03 KST)
   ✅ 성공: 4건
   ⚠️ 부분 성공: 1건 (HDA-12345)
   🟥 실패: 0건
   ```
8. **routine timeout 대비**: 등록 피처가 8개 이상이고 누적 실행 시간이 길어지면 (예: 5분 초과 예상), 미처리 피처를 다음 routine 실행에 위임할지 사용자가 결정. 1차에는 모두 순차 처리.

## STEP 7: list

1. `$ARGUMENTS`의 두 번째 토큰이 `--all`이면 모든 페이지, 아니면 `status = active`인 페이지만 조회. archived 페이지는 기본 숨김.
2. Notion DB에서 해당 페이지들 조회 → page properties 추출.
3. 표 형식으로 출력 (`status` 컬럼 포함, `--all`일 때만 의미 있음):

```markdown
| epic_key | 제목 | status | last_run_at | last_error |
|---|---|---|---|---|
| HDA-12345 | 로그인 화면 개선 | active | 2026-05-12 06:00 | — |
| HDA-12678 | 채팅 SDK 통합 | active | 2026-05-12 06:00 | Slack: token expired |
| HDA-12000 | 구버전 마이그레이션 | archived | 2026-04-20 06:00 | — |
```

4. 합계: `활성 N건 · 보관 M건 (정상 X건 · 실패 Y건)` — `--all`이 아니면 활성만, 합계 끝에 "(보관 K건은 --all로 표시)" 안내.

## STEP 8: unregister (보관)

> **삭제 아님**: Notion API의 `archive`(=휴지통 이동)는 사용하지 않는다. 페이지는 그대로 활성 상태로 두고, page property `status`만 `archived`로 바꿔 batch/list 대상에서 제외한다. 본문·체크박스·변경 이력은 보존되며 언제든 `reactivate`로 되돌릴 수 있다.

1. epic_key로 Notion DB 페이지 lookup. 없으면 "등록되지 않은 피처" 안내 후 중단.
2. 이미 `status = archived`이면 "이미 보관된 피처입니다" 안내 후 중단 (멱등).
3. `mcp__claude_ai_Notion__notion-update-page` `update_properties`로 `status = archived` 변경. 다른 property는 건드리지 않는다 (`last_run_at`, `last_error` 등 보존).
4. 확인 메시지: `🗄️ {epic_key} 보관 완료. batch 대상에서 제외됩니다. 복구는 /feature-memory reactivate {epic_key}`.

## STEP 9: reactivate

1. epic_key로 Notion DB 페이지 lookup. 없으면 "등록되지 않은 피처입니다. `/feature-memory register {epic_key}`로 먼저 등록하세요." 안내 후 중단.
2. 이미 `status = active`이면 "이미 활성 상태입니다" 안내 후 중단 (멱등).
3. `mcp__claude_ai_Notion__notion-update-page` `update_properties`로 `status = active` 변경.
4. 확인 메시지: `🔄 {epic_key} 재활성화 완료. 다음 batch부터 갱신됩니다. 즉시 갱신하려면 /feature-memory {epic_key}`.

## Notion DB 스키마 (page properties)

bootstrap이 자동 생성한다. 수동 생성 시 아래 스키마 그대로 사용.

> **SSOT 원칙**: URL은 page property에 두지 않는다. 모든 외부 링크는 Jira 이슈가 유일한 출처. 메타 운영 필드만 남긴다.

| Property | 타입 | 설명 |
|---|---|---|
| 이름 | title | `{epic_key} - {Epic 제목}` |
| `epic_key` | rich text | 예: `HDA-12345` (검색 키) |
| `status` | select (`active` \| `archived`) | 보관/활성 구분. `active`만 batch 대상. unregister는 `archived`, reactivate는 `active`로 변경 |
| `last_run_at` | date(시간 포함) | 변경 감지 기준 |
| `last_error` | rich text | 마지막 실행 실패 사유 (없으면 빈 값) |
| `registered_at` | date | 등록일 |
| `figma_frame_hashes` | rich text | Figma frame별 디자인 컨텍스트 hash JSON. `{"488:2586": "sha256...", ...}` 형식. STEP 2.3 Figma ②단계의 incremental 변경 감지용. `__skip__`으로 설정하면 ②단계(frame별 `get_design_context`+hash)만 skip(①frame 목록 추출은 항상 수행). 빈 값(`""`)이면 첫 갱신 시 `{}`로 초기화 |

## URL 파싱 규칙

`~/.claude/rules/external-links.md`를 그대로 따른다.

- **Slack 스레드 URL**: `https://prnd.slack.com/archives/{channelId}/p{timestamp}` → `channelId`, `threadTs` (timestamp의 10번째 자리에 `.` 삽입)
- **Notion 페이지 URL**: 마지막 세그먼트에서 `-` 기준 마지막 32자리 hex가 page ID
- **Jira 이슈 URL**: `/browse/{KEY}` 또는 쿼리 `selectedIssue={KEY}`
- **Figma URL**: `https://figma.com/design/{fileKey}/{fileName}?node-id={nodeId}` → `fileKey`는 경로 세 번째 세그먼트, `nodeId`는 쿼리에서 `-`를 `:`로 변환. branch URL(`/design/{fileKey}/branch/{branchKey}/...`)은 `branchKey`를 fileKey로 사용. FigJam 보드(`/board/...`)는 `get_figjam`으로 분기 가능 (1차에선 `/design/` 만 지원)

## 에러 처리 (Fail-soft 정책)

| 소스 | 실패 사유 예 | 처리 |
|---|---|---|
| Jira | 인증 만료, 이슈 삭제, 5xx | `## 데이터 소스 상태`에 🟥 + `last_error` 기록 + Slack 알림 |
| Slack | 채널 권한 만료, 스레드 삭제, 잘못된 URL | 동일 |
| Notion | 페이지 삭제, integration 권한 만료, rate limit | 동일 (rate limit는 1회 재시도 후 실패 처리) |
| GitHub | repo 삭제, gh CLI 미인증, search 한도 초과 | 동일 |
| Figma | 파일 삭제, 권한 만료, 잘못된 fileKey/nodeId, 토큰 초과 | 1단계 `get_metadata`(페이지) 응답의 토큰 초과는 **정상 동작** — 도구가 만든 임시 파일에서 jq + grep으로 frame 목록 추출. 2단계 `get_design_context`(frame 단위) 일부 실패는 해당 frame만 직전 hash 유지하고 continue. 모든 단계 실패 시 ⚠️ + `last_error` 기록 + Slack 알림. 페이지 단위 nodeId로는 `get_design_context`를 **절대 호출하지 않는다** (항상 실패) |

**Cascade 방지**: STEP 6 batch에서 한 피처 실패가 다음 피처를 막지 않는다.

**Retry**: Notion API 429는 `Retry-After` 후 1회 재시도. 다른 소스는 즉시 fail.

## 멱등성 보장 포인트

- `since = last_run_at` 기반으로 신규 활동만 수집 → 같은 입력이면 같은 결과
- `## 변경 이력`은 항목별 (날짜+소스+요약) 키로 dedup. 이미 있는 항목은 다시 prepend하지 않음
- 본문 4개 섹션(한눈/현재/최근/소스 상태)은 매번 100% 재생성 (멱등)

## 사용 예시

```bash
# 1회 셋업
/feature-memory bootstrap

# 새 피처 등록
/feature-memory register HDA-12345

# 단일 피처 갱신 (수동)
/feature-memory HDA-12345

# 모든 피처 갱신 (routine이 호출)
/feature-memory batch

# 활성 피처 조회
/feature-memory list

# 보관 포함 전체 조회
/feature-memory list --all

# 피처 보관 (페이지·이력 보존, batch 대상에서만 제외)
/feature-memory unregister HDA-12345

# 보관된 피처 재활성화
/feature-memory reactivate HDA-12345
```

## 원격 자동 실행 (`/schedule` routine)

bootstrap + 첫 register + 첫 수동 갱신을 검증한 후 등록한다.

```
/schedule create
  name: feature-memory-daily
  cron: 0 21 * * *           # UTC 21:00 = KST 06:00 익일
  prompt: /feature-memory batch
```

- routine prompt는 **단일 줄**. LLM에 iteration·dispatch를 맡기지 않는다 — 결정적 동작은 `batch` 서브커맨드 내부 명세된 단계에서 처리.
- 사용자 머신이 꺼져 있어도 동작한다.
- 매 실행마다 batch 완료 요약이 알림 채널로 송신되므로, 사용자는 알림만 봐도 어제 batch가 정상 돌았는지 알 수 있다.

## 검증 체크리스트 (첫 dry-run)

스킬 작성 직후 한 번씩 손으로 돌려서 동작을 확인한다.

- [ ] `bootstrap` → Notion DB가 생성되고 ID가 표시된다 + 본 SKILL.md "기본 정보"의 `{TODO}`가 채워진다
- [ ] `register HDA-XXX --slack ... --notion-docs ...` → Notion DB에 새 페이지가 만들어진다 (page properties 확인)
- [ ] `HDA-XXX` 첫 호출 → 5 소스(Jira·Slack·Notion·GitHub·Figma)에서 데이터 수집 + 본문 5 섹션 생성 + page property `last_run_at` 갱신
- [ ] `HDA-XXX` 둘째 연속 호출 → 본문 동일 + `변경 이력` 추가 0건 (멱등성 확인)
- [ ] Slack 스레드에 메시지 1개 추가 후 호출 → `최근 활동`/`변경 이력`에 그 메시지 1건만 추가
- [ ] 한 소스의 토큰을 일부러 끊고 호출 → 보고서는 생성됨 + `## 데이터 소스 상태`에 🟥 + `last_error` 기록 + Slack 알림 수신
- [ ] Figma frame이 1개라도 있는 피처 첫 갱신 → `figma_frame_hashes`가 JSON `{...}`으로 채워지고 Reference의 `Figma 디자인 컨텍스트` toggle에 신규 frame 코드 노출
- [ ] Figma frame 코드가 변경되지 않은 상태로 다시 갱신 → `## 변경 이력`에 Figma 항목 0건 추가 (멱등성)
- [ ] Figma에서 frame 하나 수정 후 갱신 → 해당 frame만 `## 변경 이력`에 prepend, `figma_frame_hashes` 해당 키만 갱신
- [ ] `figma_frame_hashes = "__skip__"` 설정 후 갱신 → frame 목록만 갱신되고 `get_design_context` 호출 0건
- [ ] `list` → 활성 피처만 표로 표시 (보관 페이지는 숨김)
- [ ] `list --all` → 활성 + 보관 페이지 모두 `status` 컬럼과 함께 표시
- [ ] `unregister HDA-XXX` → page property `status = archived` (페이지는 Notion에서 계속 열람 가능, 휴지통에 들어가지 않음)
- [ ] `unregister`한 epic_key를 `/feature-memory {epic_key}`로 갱신 시도 → "보관된 피처" 안내 후 중단
- [ ] `unregister`한 epic_key가 `batch` 대상에서 제외되는지 확인 (요약에 카운트되지 않음)
- [ ] `reactivate HDA-XXX` → `status = active`로 복귀 + 다음 갱신부터 다시 batch 대상
- [ ] `/schedule run feature-memory-daily` → batch 1회 즉시 실행 + 알림 채널에 batch 요약 도착

## 주의사항

- **`## 한눈에 보기`~`## 데이터 소스 상태` 4개 섹션은 매 실행 재생성**된다 (STEP 4.5 부분 패치로 해당 섹션만 교체). 사람이 이 섹션들을 손으로 편집해도 덮어써진다. 단 🎯/⚠️·✅ 완료·변경 이력은 sweep·prepend로 **보존·누적**되므로 덮어쓰지 않는다. 자유 메모가 필요하면 child page를 직접 만들어 사용한다.
- **URL이 잘못되어 fetch 실패하면** `last_error`에 기록된다. SSOT 원칙상 수정은 **Jira 이슈에서** 한다 (page property에 URL 필드는 없음).
- **routine은 사용자 Claude 계정에 묶여 있다**. 휴가/퇴사 등 장기 부재 시 service account + GitHub Actions로 마이그레이션 (디자인 문서 Open Question 8).
- **변경 이력 누적이 길어지면** 200개 초과분이 `<details>` 블록으로 접힌다. 이 동작이 마음에 안 들면 STEP 3의 "변경 이력" 섹션 로직을 조정.
- **READ-ONLY 데이터 소스**: Jira/Slack/Notion 소스 자체의 상태(이슈 상태 전환, 메시지 추가 등)는 절대 수정하지 않는다. 보고서만 갱신한다.
