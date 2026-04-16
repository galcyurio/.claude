# 외부 링크 수집 규칙

텍스트에서 외부 링크를 추출하고 MCP 도구로 내용을 가져오는 범용 규칙이다.

## 도메인 필터링

아래 도메인의 링크만 처리한다. 그 외 도메인은 무시한다.

| 도메인 패턴 | 유형 |
|------------|------|
| `*.notion.so`, `*.notion.site` | Notion |
| `figma.com` | Figma |
| `*.atlassian.net`, `*.jira.com` | Jira |
| `*.slack.com` | Slack |

## 링크 유형별 수집 방법

| 링크 유형 | 도메인 패턴 | MCP 도구 | 수집 내용 |
|-----------|------------|----------|----------|
| Notion | `*.notion.so`, `*.notion.site` | `mcp__claude_ai_Notion__notion-fetch` | 페이지 내용 |
| Figma | `figma.com` | `mcp__claude_ai_Figma__get_design_context`, `mcp__claude_ai_Figma__get_screenshot` | 디자인 컨텍스트, 스크린샷 |
| Jira | `*.atlassian.net`, `*.jira.com` | `mcp__claude_ai_Atlassian__getJiraIssue` | 이슈 제목, 설명, AC |
| Slack | `*.slack.com` | `mcp__plugin_slack_slack__slack_read_thread`, `mcp__plugin_slack_slack__slack_read_channel` | 메시지/스레드 내용 |

## URL 파싱 규칙

### Notion

```
https://*.notion.so/{page_slug}-{pageId}
https://*.notion.site/{page_slug}-{pageId}
```

- page ID: URL 마지막 세그먼트에서 `-` 기준 마지막 32자리 16진수 추출
- 예: `https://myworkspace.notion.so/My-Page-abc123def456...` → pageId = `abc123def456...`
- `mcp__claude_ai_Notion__notion-fetch`에 URL 또는 pageId 전달

### Figma

```
https://figma.com/design/{fileKey}/{fileName}?node-id={nodeId}
```

- `fileKey`: URL 경로의 세 번째 세그먼트
- `nodeId`: 쿼리 파라미터 `node-id` 값. `-`는 `:`로 변환하여 사용
- 예: `node-id=123-456` → `123:456`
- `mcp__claude_ai_Figma__get_design_context`에 `fileKey`, `nodeId` 전달
- `mcp__claude_ai_Figma__get_screenshot`으로 스크린샷 추가 수집

### Jira

```
https://{workspace}.atlassian.net/browse/{issueKey}
https://{workspace}.jira.com/browse/{issueKey}
```

- 이슈 키: URL 경로 마지막 세그먼트 (예: `HDA-123`)
- `mcp__claude_ai_Atlassian__getJiraIssue`에 이슈 키 전달

### Slack

```
https://{workspace}.slack.com/archives/{channelId}/p{timestamp}
https://{workspace}.slack.com/archives/{channelId}
```

- `channelId`: `/archives/` 다음 세그먼트 (예: `C01234567`)
- `threadTs`: `p` 접두어를 제거하고 10번째 자리에 `.` 삽입 (예: `p1712345678901234` → `1712345678.901234`)
- 스레드 링크(`p{timestamp}` 포함) → `mcp__plugin_slack_slack__slack_read_thread`에 `channelId`, `threadTs` 전달
- 채널 링크(timestamp 없음) → `mcp__plugin_slack_slack__slack_read_channel`에 `channelId` 전달

## 공통 규칙

- 링크는 **병렬로 수집**한다. 유형이 다르거나 독립적인 링크는 동시에 MCP 도구를 호출한다.
- MCP 도구 호출 실패 시 해당 링크를 **skip**하고 경고를 출력한다. 나머지 링크 수집과 워크플로우는 계속 진행한다.
- 같은 URL이 중복 등장하면 한 번만 수집한다.
