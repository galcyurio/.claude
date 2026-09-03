---
name: start-feature
effort: low
description: 에픽의 feature-base 브랜치를 만들어 원격에 올리고 base worktree와 하위 작업용 worktree를 준비하는 스킬. 사용자가 'start-feature', '피처 시작', '피처 브랜치 만들어', 'feature-base 만들어', '에픽 브랜치 준비해줘' 등을 에픽 키와 함께 요청할 때 이 스킬을 사용해야 한다. 에픽 자체를 만드는 일은 `~/.prnd-cli/create_jira_epic.mjs`가 맡고, 이슈 하나를 착수하는 요청에는 `start-worktree`를 사용한다.
argument-hint: "<에픽키 또는 feature-base 브랜치명> [--children <n>]"
allowed-tools: Bash, AskUserQuestion
---

# start-feature

에픽의 `feature-base` 브랜치를 만들어 원격에 올리고, 그 브랜치를 물 base worktree와 하위 작업용 worktree 2개를 준비한다.

## 절차

1. 인자가 에픽 키(예: `HDA-99999`)면 `mcp__claude_ai_Atlassian__getJiraIssue`로 summary를 얻고 `copy-new-branch-name` 규칙에 따라 `feature-base/<키>-<명사구 slug>`를 만든다. 인자가 이미 `feature-base/`로 시작하면 그대로 사용한다.
2. **원격에 올리는 명령이므로 실행 전에 만들어질 base 브랜치 이름을 사용자에게 보여 확인받는다.** `rules/git.md`의 push 게이트가 적용된다.
3. 확인을 받으면 `bash ~/.claude/skills/start-feature/start-feature.sh <base-branch>`를 호출하고, 만들어진 worktree 경로 목록을 사용자에게 보고한다.
