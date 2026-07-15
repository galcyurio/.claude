# Figma 링크 확보 fallback 체인 (review-by-agents 2단계)

`SKILL.md` 2단계에서 참조하는 상세 절차다. **디자인 변경이 감지됐는데 PR 본문에서 Figma 링크를 확보하지 못한 경우에만** 이 파일을 Read해 링크를 확보한다. 디자인 변경이 없으면 건너뛴다.

적용 모드는 **diff가 존재하는 모드(PR 모드 + 현재 변경사항 모드)**다. 파일 모드는 diff가 없어 디자인 변경 판정이 어려우므로 건너뛴다.

먼저 diff가 **디자인 관련 변경**(화면에 드러나는 색상·간격·크기·레이아웃·타이포·컴포넌트 등 시각 요소의 신규·변경)을 포함하는지 판단한다. 순수 로직·데이터 변경만 있으면 "디자인 변경 없음"으로 본다.

디자인 변경이 **없으면** 이 fallback을 건너뛴다. 디자인 변경이 **있는데 PR 본문에서 Figma 링크를 확보하지 못했으면**, 먼저 0번으로 이슈 정보를 확보한 뒤 1~3번을 **순서대로** 시도하고 **링크를 하나라도 확정하면 즉시 중단**한다. **frame 단위로 좁혀진 링크를 페이지 단위 링크보다 항상 우선**한다.

## 0. 사전 — 이슈 ID·epic_key·폴백 링크 확보 (공통 전제)

이슈 ID는 PR 제목·본문 → 브랜치명(`git rev-parse --abbrev-ref HEAD`) → 최근 커밋 메시지에서 `{PROJECT}-{번호}`(예 `HDA-21304`) 패턴으로 추출한다. `mcp__claude_ai_Atlassian__getJiraIssue(issueIdOrKey, fields=["summary","description","comment","parent","issuetype"], responseContentFormat="markdown")`와 `mcp__claude_ai_Atlassian__getJiraIssueRemoteIssueLinks`를 호출해 다음을 동시에 확보한다:

- **epic_key**: 이슈타입이 Epic이면 그 이슈 ID, subtask·story면 `parent` 이슈 ID (1번 feature-memory 조회 키)
- **이슈 컨텍스트**: `summary`(제목)·description — 1번 frame 자동 매칭의 신호로 사용
- **Jira 페이지 링크(폴백용)**: description·comment·웹 링크의 `figma.com/design/`·`figma.com/board/` URL. 보통 Epic 페이지 단위라 범위가 넓다 → 2번 폴백에서만 사용

## 1. feature-memory frame 좁히기 (최우선)

feature-memory는 Epic의 Figma 페이지를 직계 자식 frame 단위로 라벨링해 `## 📚 Reference`의 `Figma frame 목록` 표에 저장해 둔다. 0번의 epic_key로 `mcp__claude_ai_Notion__notion-search` → 페이지가 있으면 `mcp__claude_ai_Notion__notion-fetch(page_id)`로 본문을 받아 그 표를 찾는다.

- **`Figma frame 목록` 표가 있으면**: 표의 각 행(`이름` · `크기` · `[Figma](node-id 링크)`)을 파싱한 뒤, 리뷰 대상 이슈와 연관된 frame을 **자동 매칭**한다. 매칭 신호는 ① frame 이름 키워드 ↔ 이슈 `summary`·description, ② frame 이름 ↔ 변경된 화면/컴포넌트 파일명, ③ frame 이름 ↔ diff에 등장하는 UI 텍스트·컴포넌트명이다.
  - **정확히 1개로 좁혀지면** → 그 frame 링크를 Figma 링크로 확정한다 (페이지 전체가 아닌 frame 단위로 Designer에 전달). 즉시 중단.
  - **0개거나 2개 이상이면** → `AskUserQuestion`으로 후보 frame 이름들을 옵션으로 제시(2개 이상이면 매칭된 후보 우선, 0개면 표 전체에서)하고 사용자가 리뷰할 frame을 고르게 한다. 선택된 frame 링크를 확정하고 중단한다. 사용자 응답 전에는 2번으로 넘어가지 않는다.
- **`Figma frame 목록` 표가 없으면**(feature-memory 미등록이거나 frame 목록 미생성) → 좁히기를 적용하지 않고 2번으로 폴백한다. feature-memory의 `## 한눈에 보기` 페이지 링크는 2번 Jira 링크와 동일한 Epic Figma를 가리키므로 따로 쓰지 않는다.

## 2. Jira 페이지 링크 (폴백)

0번에서 확보한 Jira Figma 링크가 있으면 그대로 채택한다. frame 좁히기는 적용되지 않으며 Designer가 Epic 페이지 전체를 검토하게 된다. 링크가 없으면 3번으로.

## 3. 사용자에게 요청

1·2 모두 실패하면 `AskUserQuestion`으로 묻는다. 질문은 "디자인 변경이 감지됐지만 Figma 링크를 찾지 못했습니다. 어떻게 진행할까요?", 옵션은 ① `Figma 링크 제공`(링크는 Other 또는 후속 메시지로 받음) ② `링크 없이 리뷰 진행`. **사용자 응답을 받기 전에는 3단계 에이전트 스폰으로 넘어가지 않는다.**
