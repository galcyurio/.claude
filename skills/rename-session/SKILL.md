---
name: rename-session
effort: low
description: Jira 이슈 제목에 맞춰 Orca 탭·카드 이름을 바꾸고 Claude 세션 /rename 명령을 출력하는 스킬. 사용자가 'rename-session', '세션명', '세션 이름', 'orca 세션명 변경', 'orca 탭 이름 변경', 'Jira 제목 바뀌었어 세션명도 바꿔' 등을 요청할 때 이 스킬을 사용해야 한다. worktree를 새로 잡는 요청에는 `start-worktree`, 피처를 여는 요청에는 `start-feature`를 사용한다.
argument-hint: "[이슈키]"
allowed-tools: Bash, mcp__claude_ai_Atlassian__getJiraIssue
---

# rename-session

Jira 제목을 기준으로 Orca 이름과 Claude 세션 이름을 한 번에 맞춘다.

## 절차

1. **이슈 키를 정한다.** 인자로 받은 키를 쓰고, 없으면 현재 브랜치명(`feature/HDA-12345-...`, `feature-base/HDA-12345-...`)에서 읽는다. 그래도 없으면 대화 맥락의 Jira 키를 쓴다.
2. **Jira 제목을 새로 조회한다.** 사용자가 제목을 바꿨다고 말하는 경우가 많으므로 대화에 남은 옛 제목을 재사용하지 않는다. `mcp__claude_ai_Atlassian__getJiraIssue`를 `cloudId: "prndcompany.atlassian.net"`, `fields: ["summary", "issuetype"]`로 호출한다.
3. **에픽인지 판별한다.** `issuetype.hierarchyLevel`이 1이면 에픽이다. 이름(`에픽`)으로 비교하지 않는다.
4. **스크립트를 호출한다.** `--summary`에는 Jira 원본 제목을 그대로 넘긴다. 대괄호 prefix는 스크립트가 뗀다.

```
bash ~/.claude/skills/rename-session/rename-session.sh <키> --summary "<Jira 원본 제목>" [--epic]
```

| 구분 | Orca에서 바뀌는 것 | 형식 |
|---|---|---|
| 이슈 | 현재 터미널 탭 제목 | `<키> <핵심 제목>` (start-worktree와 같음) |
| 에픽 (`--epic`) | 현재 worktree 카드 표시 이름 | Jira 원본 제목 (start-feature와 같음) |

5. **출력한다.** 스크립트가 stdout으로 낸 `/rename` 2줄을 `~/.claude/CLAUDE.md`의 세션 이름 규칙대로 설명 없이 단독 출력한다. Claude 세션 이름은 사용자가 이 명령을 직접 입력해야 바뀐다.

스크립트가 `[오류]`로 끝나도 `/rename` 2줄은 위 규칙대로 직접 만들어 출력하고, Orca 이름을 바꾸지 못한 이유를 한 줄로 덧붙인다.
