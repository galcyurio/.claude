---
name: start-feature
effort: low
description: 피처를 할당받았을 때 기획 Jira(HD-) 하위에 HDA 에픽을 만들고, 에픽의 feature-base 브랜치를 원격에 올려 base worktree와 하위 작업용 worktree까지 준비하는 스킬. 이미 있는 에픽 키나 feature-base 브랜치를 주면 에픽 생성은 건너뛴다. `--dry-run`이면 에픽 생성부터 worktree까지 아무것도 쓰지 않고 계획만 보여 준다. 사용자가 'start-feature', '피처 시작', '에픽 만들어', '에픽 생성', '피처 브랜치 만들어', 'feature-base 만들어', '에픽 브랜치 준비해줘' 등을 기획 Jira 키나 에픽 키와 함께 요청할 때 이 스킬을 사용해야 한다. 이슈 하나를 착수하는 요청에는 `start-worktree`를 사용한다.
argument-hint: "<HD-기획키 | HDA-에픽키 | feature-base/...> [--dry-run] [--children <n>] [--with <다른 앱 저장소>...]"
allowed-tools: Bash, AskUserQuestion, mcp__claude_ai_Atlassian_MCP__getJiraIssue
---

# start-feature

기획 Jira 하위에 본인 담당 HDA 에픽을 만들고, 그 에픽의 `feature-base` 브랜치를 원격에 올린 뒤 base worktree와 하위 작업용 worktree를 준비한다. 여러 앱에 걸친 피처면 다른 앱 저장소에도 같은 브랜치를 올리고, 그 앱의 하위 worktree를 오케스트레이터 base worktree 아래에 함께 만든다.

스크립트 두 개를 쓴다. 경로는 모두 `~/.claude/skills/start-feature/`이다.

- `create-epic.mjs`: Jira 조회·에픽 생성·제목 확정. stdout은 JSON 한 줄이다.
- `start-feature.sh`: 브랜치 생성·push·worktree 준비.

## 진입 분기

- 인자가 `HD-`로 시작하면 아래 1단계부터 전부 진행한다.
- 인자가 `HDA-` 에픽 키면 `getJiraIssue`로 summary를 가져와 8단계부터 진행한다. 여러 앱이면 `--with`는 사용자가 준 값이나 대화 맥락을 따른다.
- 인자가 `feature-base/`로 시작하면 브랜치 이름은 그대로 쓰고, 이름에서 뽑은 키로 summary를 조회해 9단계부터 진행한다.
- `--dry-run`은 어느 경로든 적용된다.

## dry-run

`--dry-run`이면 아래 모든 스크립트 호출에 `--dry-run`을 붙인다. Jira 조회(GET)와 질문은 그대로 하고, 에픽 생성·담당자 지정·제목 수정·브랜치 push·worktree 생성은 출력만 한다. 에픽 키 자리에는 `create-epic.mjs`가 돌려준 `HDA-DRYRUN`을 그대로 쓴다. 5단계 확인 게이트는 건너뛰고, 보고 첫 줄에 `dry-run: 실행하지 않았다`를 쓴다.

## 절차 (HD- 키)

1. **기획 Jira를 조회한다.**

   ```bash
   node ~/.claude/skills/start-feature/create-epic.mjs info <HD-키>
   ```

   결과의 `name`이 에픽 이름(`ftr-` 제거)이고, `links`는 기획서·디자인·슬랙 링크, `apps`는 앱별 미배포 버전, `common`은 앱 접두어가 없는 버전(`미정`)이다.

2. **진행할 앱을 묻는다.** `AskUserQuestion`(multiSelect)으로 이번 피처를 진행할 앱을 고르게 한다. 선택지는 `apps`의 키다(4개를 넘으면 고객·딜러·평가사·리볼트를 보이고 나머지는 Other로 받는다). 2개 이상 고르면 대화를 이끌 앱(base worktree를 둘 저장소)을 이어서 묻는다. 고객이 포함되면 고객을 Recommended로 둔다.

3. **여러 앱 처리 방식을 묻는다**(앱이 2개 이상일 때만).
   - `[공통]` 에픽 하나: App `공통`, 수정 버전은 앱별로 하나씩 모두 넣는다.
   - 앱별 에픽: 앱마다 에픽을 따로 만든다. App은 각 앱, 제목은 모두 같은 이름이다.

4. **수정 버전을 묻는다.** 앱마다 `apps[<앱>]`에 `common`을 더한 목록에서 고른다. 4개를 넘으면 가까운 버전 3개와 `미정`을 보이고 나머지는 Other로 받는다.

5. **실행 전에 확인받는다**(dry-run이면 생략). 아래를 한 번에 보여 주고 `AskUserQuestion`으로 승인받는다. 이 승인이 에픽 생성과 `rules/git.md`의 push 게이트를 함께 충족한다.
   - 에픽 최종 제목: 단일·앱별 에픽은 `[<App>][<name>]`, `[공통]` 에픽은 `[공통][<name>]`
   - App, 수정 버전, 담당자(본인)
   - feature-base 브랜치명(8단계 규칙으로 미리 만든다)
   - worktree 트리(아래 "스크립트가 하는 일"의 그림 형식)

6. **에픽을 만든다.** 앱별 에픽이면 앱마다 한 번씩 호출한다.

   ```bash
   node ~/.claude/skills/start-feature/create-epic.mjs create \
     --parent <HD-키> --app <App> --version-id <id> [--version-id <id>...] \
     --name "<name>" --spec "<links.spec>" --design "<links.design>" --slack "<links.slack>" \
     --assign-me [--dry-run]
   ```

   `links`의 값이 `null`이면 그 플래그를 뺀다. 결과의 `key`가 에픽 키다.

7. **제목을 확정한다.** Jira automation이 생성 뒤 1~2분 안에 summary를 `[App][이름]`으로 감싼다. 반영을 기다리고, 최종형이 아니거나 3분이 지나면 직접 설정한다.

   ```bash
   node ~/.claude/skills/start-feature/create-epic.mjs wait-summary <에픽키> \
     --input "<name>" --final "<최종 제목>" [--dry-run]
   ```

8. **브랜치 이름을 정한다.** `create-new-branch-name` 규칙으로 `feature-base/<에픽키>-<명사구 slug>`를 만든다. 앱별 에픽이면 이끄는 앱의 에픽 키를 쓴다.

9. **worktree를 준비한다.** 이끄는 앱 저장소(`~/dev/<저장소>`, 앱 이름과 저장소의 대응은 `rules/prnd-projects.md` 표)에서 실행하고, 나머지 선택 앱은 `--with`로 넘긴다.

   ```bash
   cd ~/dev/<이끄는 앱 저장소> && bash ~/.claude/skills/start-feature/start-feature.sh <base-branch> \
     --display-name "<최종 제목>" [--with <저장소>...] [--children <n>] [--dry-run]
   ```

   `--display-name`에는 에픽 최종 제목을 대괄호 prefix까지 그대로 넘긴다. base worktree의 orca 카드 이름이 이 제목이 된다.

10. **결과를 보고한다.** 에픽 링크(여러 개면 모두), 브랜치, 만들어진 worktree 경로를 부모 관계가 보이는 트리로 나열한다.

## 실패했을 때

에픽을 만든 뒤 `start-feature.sh`가 실패하면(브랜치 중복, push 실패 등) 에픽을 다시 만들지 않는다. 만들어진 에픽 키와 링크를 보고하고, 원인을 해결한 뒤 `start-feature <HDA-에픽키>`로 다시 실행하도록 안내한다.

## 스크립트가 하는 일 (start-feature.sh)

1. `develop`을 최신화하고 `feature-base/...` 브랜치를 끊는다. `--with` 저장소에도 똑같이 한다.
2. 그 브랜치를 원격에 올린다. 하위 worktree가 `origin/<base>`를 upstream으로 따라가야 하므로 이 단계가 빠지면 뒤가 전부 실패한다.
3. `git worktree add`로 메인 옆 `<repo>-<에픽키>` 자리에 base worktree를 만들고, orca 카드 이름을 에픽 제목으로 바꾼다.
4. 하위 worktree를 `<repo>-<에픽키>-<N>` 자리에 만들어 upstream을 걸고, base worktree를 부모로 연결한다. 카드 이름은 `고객 2`, `딜러 3`처럼 `<앱> <번호>`로 둔다.
5. `--with` 저장소에는 base worktree를 만들지 않는다. 하위 worktree만 `<repo>-<에픽키>-2`부터 만들어, 실행한 저장소의 base worktree를 부모로 직접 연결한다. 대화는 그 base worktree 하나가 이끌고, 라이브러리 작업도 그 저장소의 `prnd-library` 서브모듈에서 한다.

```
heydealer-android-HDA-xxxx   (오케스트레이터, 카드 이름: 에픽 제목)
├─ 고객 2 / 고객 3      heydealer-android-HDA-xxxx-2, -3
├─ 딜러 2 / 딜러 3      heydealer-for-dealer-android-HDA-xxxx-2, -3
└─ 평가사 2 / 평가사 3  heydealer-inspector-android-HDA-xxxx-2, -3
```

## 주의

- 에픽 summary 입력값에는 대괄호를 넣지 않는다. automation이 `[App][입력값]`으로 감싸므로 직접 넣으면 `[고객][[고객][...]]`처럼 중복된다.
- 부모 연결에 쓰는 selector는 `path:<경로>`다. `orca worktree set`은 `worktree:<id>` 형식을 받지 않아 `selector_not_found`로 실패한다. `orca worktree create`의 selector 목록과 다르다는 점에 유의한다.
- 하위 worktree 개수는 기본 2개이며 `--children <n>`으로 바꾼다. 이 값은 `--with` 저장소에도 똑같이 적용된다.
