---
name: start-feature
effort: low
description: 에픽의 feature-base 브랜치를 만들어 원격에 올리고 base worktree와 하위 작업용 worktree를 준비하는 스킬. 사용자가 'start-feature', '피처 시작', '피처 브랜치 만들어', 'feature-base 만들어', '에픽 브랜치 준비해줘' 등을 에픽 키와 함께 요청할 때 이 스킬을 사용해야 한다. 에픽 자체를 만드는 일은 `~/.prnd-cli/create_jira_epic.mjs`가 맡고, 이슈 하나를 착수하는 요청에는 `start-worktree`를 사용한다.
argument-hint: "<에픽키 또는 feature-base 브랜치명> [--children <n>] [--display-name <에픽 제목>]"
allowed-tools: Bash, AskUserQuestion, mcp__claude_ai_Atlassian__getJiraIssue
---

# start-feature

에픽의 `feature-base` 브랜치를 만들어 원격에 올리고, 그 브랜치를 물 base worktree와 하위 작업용 worktree 2개를 준비한다.

## 절차

1. **에픽 정보를 얻는다.** 인자가 에픽 키(예: `HDA-99999`)면 `mcp__claude_ai_Atlassian__getJiraIssue`로 summary를 가져와, `copy-new-branch-name` 규칙에 따라 `feature-base/<키>-<명사구 slug>`를 만든다. 인자가 이미 `feature-base/`로 시작하면 브랜치 이름은 그대로 쓰되, 이름에서 뽑은 키로 summary를 조회한다.
2. **실행 전에 확인받는다.** 이 스킬은 base 브랜치를 원격에 올린다. 만들어질 브랜치 이름과 에픽 제목을 보여 주고 사용자 확인을 받는다. `rules/git.md`의 push 게이트는 이 확인으로 충족된다 — 스크립트 안에서 업로드가 일어나므로 별도 지시를 다시 받지 않는다.
3. **스크립트를 호출한다.**

   ```bash
   bash ~/.claude/skills/start-feature/start-feature.sh <base-branch> --display-name "<에픽 제목>"
   ```

   `--display-name`에는 Jira 에픽의 summary를 그대로 넘긴다. base worktree의 orca 카드 이름이 브랜치명 대신 그 제목이 되어 보드에서 어떤 피처인지 바로 읽힌다. 대괄호 prefix(`[고객]` 등)는 제거하지 않고 원문을 쓴다.

4. **결과를 보고한다.** 만들어진 worktree 경로 세 자리와 각각의 브랜치를 나열한다.

## 스크립트가 하는 일

1. `develop`을 최신화하고 `feature-base/...` 브랜치를 끊는다.
2. 그 브랜치를 원격에 올린다. 하위 worktree가 `origin/<base>`를 upstream으로 따라가야 하므로 이 단계가 빠지면 뒤가 전부 실패한다.
3. `git worktree add`로 메인 옆 `<repo>-<에픽키>` 자리에 base worktree를 만들고, orca 카드 이름을 에픽 제목으로 바꾼다.
4. 하위 worktree를 `<repo>-<에픽키>-<N>` 자리에 만들어 upstream을 걸고, base worktree를 부모로 연결한다.

## 주의

- 부모 연결에 쓰는 selector는 `path:<경로>`다. `orca worktree set`은 `worktree:<id>` 형식을 받지 않아 `selector_not_found`로 실패한다. `orca worktree create`의 selector 목록과 다르다는 점에 유의한다.
- 하위 worktree 개수는 기본 2개이며 `--children <n>`으로 바꾼다.
