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

# Superpowers 문서 위치
- spec: `.agent/specs/`에 저장
- plan: `.agent/plans/`에 저장
- 저장한 spec/plan(로컬 `.md`가 원본)은 확정 후 Claude Artifact로 private 발행하고, 발행 URL을 파일 최상단 `<!-- artifact: URL -->`에 기록해 재발행 시 재사용하며, 로컬 경로와 URL을 함께 출력한다.

# 사용자가 봐야 할 파일 출력 규칙
- 사용자가 직접 열어 검토해야 하는 파일(spec, plan, skill, 임시 메모 등 모든 `.md` / 코드 파일)을 작성·수정한 경우, 응답에서 해당 파일 절대 경로를 **별도 라인**으로 단독 출력한다.
- 여러 파일이면 각 경로를 한 줄씩 분리해서 나열한다.
- 본문 설명에 inline으로만 언급하지 말고, 사용자가 한눈에 찾을 수 있도록 줄을 띄워 강조한다.
- 예:
  ```
  /Users/olaf/.claude/.agent/specs/2026-05-26-foo-design.md
  /Users/olaf/.claude/.agent/plans/2026-05-26-foo-plan.md
  ```
