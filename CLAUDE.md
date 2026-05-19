# 전역 응답 언어 규칙

- 모든 답변은 한국어로 작성한다.
- 사용자가 다른 언어를 명시적으로 요청한 경우에만 해당 응답에서 그 언어를 따른다.
- 코드, 파일 경로, 명령어, 오류 메시지는 필요 시 원문을 유지하되 설명은 한국어로 제공한다.

# 세션 이름 규칙
- Jira 이슈가 확인되면 Jira ID와 Title을 이용해 세션 이름을 작성한다.
- 세션 이름을 지을 때는 설명 없이 아래 2줄을 단독 출력한다.
  1. `/rename ${JiraId} ${JiraFullTitle}` — Jira 원본 제목 그대로 (대괄호 prefix 포함)
  2. `/rename ${JiraId} ${JiraShortTitle}` — 대괄호 prefix(`[고객]`, `[마켓 추천 매물 강화]` 등)를 모두 제거한 핵심 제목만
- 예시 (Jira 제목이 `[고객][마켓 추천 매물 강화] 모델 퀵링크 - MarketCarList`인 경우):
  ```
  /rename HDA-21304 [고객][마켓 추천 매물 강화] 모델 퀵링크 - MarketCarList
  /rename HDA-21304 모델 퀵링크 - MarketCarList
  ```

# 코드 수정 검증 절차

## 범위 이탈 방지 절차 (필수)

- 수정 시작 전 `git status --short`로 대상 파일을 명시한다.
- 수정 직후 `git diff -- <대상파일>`로 확인하고, 요청과 무관한 변경은 즉시 원복한다.
- 파일 단위 원복은 `git restore --source=HEAD -- <파일경로>`를 사용한다.
- 여러 파일 수정 시 마지막 응답 전 `git status --short`로 대상 외 변경이 없는지 재확인한다.

# PR 제목 규칙
- PR 제목은 Jira issue 제목과 동일하게 작성한다.

# gstack

- 모든 웹 브라우징은 gstack의 `/browse` skill을 사용한다.
- `mcp__claude-in-chrome__*` 도구는 절대 사용하지 않는다.
- 사용 가능한 gstack skill 목록:
  - `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`
  - `/design-consultation`, `/design-shotgun`, `/design-html`
  - `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`
  - `/browse`, `/connect-chrome`
  - `/qa`, `/qa-only`, `/design-review`
  - `/setup-browser-cookies`, `/setup-deploy`, `/setup-gbrain`
  - `/retro`, `/investigate`, `/document-release`
  - `/codex`, `/cso`, `/autoplan`
  - `/plan-devex-review`, `/devex-review`
  - `/careful`, `/freeze`, `/guard`, `/unfreeze`
  - `/gstack-upgrade`, `/learn`

## gstack — 새 머신 셋업

gstack은 git submodule (`skills/gstack` -> `garrytan/gstack`)로 관리한다. clone 후 prep + setup을 1회 실행한다.

```bash
git clone --recurse-submodules git@github-galcyurio:galcyurio/.claude.git ~/.claude
~/.claude/.bin/gstack-submodule-prep.sh   # .git gitfile -> symlink 변환 (멱등)
~/.claude/skills/gstack/setup              # browse binary + wrapper 등록
```

> 모든 머신은 동일한 홈 경로(`/Users/olaf/`)를 가정한다. wrapper symlink가 절대경로 기반.
> prep 스크립트는 `[ -d ".git" ]` detection을 통과시켜 `/gstack-upgrade`가 `vendored` 분기 대신 `global-git` 분기로 진입하도록 한다.

## gstack 업데이트

```bash
# 방식 1: /gstack-upgrade skill (권장)
# Claude Code에서 /gstack-upgrade 실행 -> global-git 분기로 git fetch + reset --hard origin/main + setup
cd ~/.claude
~/.claude/.bin/gstack-gitignore-sync.sh    # wrapper 변경 반영
git add skills/gstack .gitignore
git commit -m "chore: gstack vX.Y.Z 업데이트"

# 방식 2: 수동 submodule update
cd ~/.claude
git submodule update --remote skills/gstack
~/.claude/skills/gstack/setup
~/.claude/.bin/gstack-gitignore-sync.sh
git add skills/gstack .gitignore
git commit -m "chore: gstack vX.Y.Z 업데이트"
```
# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, invoke the Skill tool with `skill: "graphify"` before doing anything else.
