# 조건부 규칙

아래 규칙은 자동으로 로드되지 않는다. 상황이 맞으면 해당 파일을 Read해서 적용한다.

| 언제 | 무엇을 읽는다 |
|---|---|
| **커밋을 만들기 전 (필수)** | `~/.claude/references/commit-rules.md` |
| plan·계획 문서를 작성할 때 | `~/.claude/references/plan-rules.md` |
| Notion·Figma·Jira·Slack·사내 API 문서 URL이 등장할 때 | `~/.claude/references/external-links.md` |
| Jira 키가 등장하는 작업을 착수할 때 | `~/.claude/references/feature-memory-read.md`, `~/.claude/references/jira-start-work.md` |

커밋 규칙은 **읽지 않은 채 커밋 메시지를 작성하지 않는다.** 형식 위반은 커밋 실행 전에 훅이 차단한다.
