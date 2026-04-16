---
name: create-jira-issue
description: Jira 상위 이슈와 하위 이슈를 생성하고 제목/설명을 일괄 정리한다
---

## 역할

사용자가 요청한 Jira 작업 항목(단일 이슈 또는 상위 이슈 + 하위 이슈들)을 생성하고,
필수 커스텀 필드(App), 제목 prefix, 설명(대상 파일/작업 내용)을 일관된 형식으로 반영한다.

## 입력 형식

다음 정보를 받는다:

- **생성 모드**: `single` 또는 `parent-with-subtasks`
- **프로젝트 키**: 예) `HDA`
- **이슈 제목**: 예) `로그인 기능 추가`
- **App 필드 값**: 예) `고객`, `라이브러리`
- **하위 이슈 목록(선택)**: `parent-with-subtasks` 모드에서만 사용하며, 각 항목은 `제목`, `대상 파일 목록`, `작업 내용`을 포함

`제목 prefix`(`[고객]`, `[라이브러리]` 등)는 Jira Automation이 App 필드 기반으로 자동 추가하므로, 스킬에서 수동으로 붙이지 않는다.

## 실행 방법

1. **CLI/인증 상태 확인**
   - `acli --version`
   - `acli jira auth status`
   - 인증 실패 시 에러를 알리고 중단한다.

2. **브랜치 이슈 키 추출 + 코드 분석 (병렬)**

   **브랜치 이슈 키 추출:**
   `git branch --show-current`로 브랜치명에서 `HDA-XXXXX` 패턴을 추출한다.
   - `feature/HDA-20176-skeleton-ui` → `HDA-20176`
   - `feature-base/HDA-20006-underline-button` → `HDA-20006`
   - 패턴이 없으면 (main, develop 등) → 에픽 없이 진행

   **코드/파일 분석:**
   사용자가 선택한 코드나 파일이 있다면 분석하여 description을 작성한다 (파일 경로, 클래스/함수명, 작업 범위, 기술적 고려사항).
   없다면 이슈 제목 기반으로 간단히 작성한다.

3. **에픽 찾기 (브랜치 이슈 키가 있는 경우)**

   `acli jira workitem view <브랜치 이슈 키> --json`으로 브랜치 이슈를 조회하여 상위 에픽을 찾는다.

   에픽 확인 방법 (우선순위):
   1. 브랜치 이슈 자체가 에픽 타입인 경우 → 해당 이슈가 에픽
   2. `parent` 필드가 에픽 타입인 경우 → 해당 parent가 에픽
   3. `customfield_10014` (Epic Link) 필드가 있는 경우 → 해당 값이 에픽 키

   에픽을 찾았다면 에픽의 **App 필드값**과 **프로젝트 키**를 함께 확인한다.

   **에픽 없이 진행하는 경우:**
   - 브랜치에서 이슈 키를 추출하지 못한 경우
   - API 오류 또는 이슈가 Jira에 존재하지 않는 경우
   - 이슈에 `parent`도 없고 `customfield_10014`도 없는 경우
   - `parent`가 에픽이 아닌 다른 타입(Story, Task 등)인 경우

4. **프로젝트/이슈 타입 확인**
   - `acli jira project list --limit 200`
   - `acli jira workitem create --help`
   - 프로젝트별 허용 타입(예: `작업`, `하위 작업`)이 다를 수 있으므로 확인 후 진행한다.

5. **상위 이슈 생성 (App 필수 필드 포함)**
   - 에픽을 찾은 경우: 에픽의 **프로젝트 키**와 **App 필드값**을 상속하고, **Parent**를 에픽 키로 설정한다.
   - 에픽을 찾지 못한 경우: 사용자에게 프로젝트 키와 App 값을 입력받는다.
   - 프로젝트에 따라 App 필드가 필수일 수 있다.
   - 이 경우 `--from-json` + `additionalAttributes.customfield_10302` 방식으로 생성한다.
   - 예시 JSON:

```json
{
  "projectKey": "HDA",
  "type": "작업",
  "summary": "로그인 기능 추가",
  "additionalAttributes": {
    "customfield_10302": { "value": "고객" }
  }
}
```

   - 생성 명령:
   - `acli jira workitem create --from-json /tmp/jira-parent.json --json`
   - 응답에서 생성된 이슈 키(예: `HDA-20632`)를 추출한다.
   - 생성 직후 상위 이슈 담당자를 본인으로 명시한다.
   - `acli jira workitem edit --key HDA-XXXX --assignee @me --yes --json`

6. **모드 분기 처리**
    - `single` 모드:
      - 3단계에서 생성한 이슈 1개만 유지한다.
      - 하위 이슈 생성 단계는 건너뛴다.
    - `parent-with-subtasks` 모드:
      - 각 하위 이슈를 `--type "하위 작업" --parent <상위키>`로 생성한다.
      - 기본 생성 명령:
      - `acli jira workitem create --project HDA --type "하위 작업" --summary "..." --parent HDA-XXXX --json`
      - 하위 이슈 summary는 `<하위 제목>`으로만 생성한다(상위 제목 결합은 Jira Automation이 처리).

7. **설명 정리**
    - 제목 prefix(`[App]`)는 Jira Automation이 자동 추가하므로 수동으로 붙이지 않는다.
    - summary는 prefix 없이 순수 제목만 입력한다. (예: `로그인 기능 추가`)
    - `single` 모드 설명은 2단계 코드/파일 분석 결과가 있으면 이를 기반으로, 없으면 목적/범위 중심으로 간단히 작성한다.
    - `parent-with-subtasks` 모드의 하위 이슈 설명에는 최소 아래 항목을 포함한다:
      - `목표`
      - `대상 파일`
      - `작업 내용`
    - 하위 이슈 제목은 생성 시 `<하위 제목>`만 입력하고, 별도 제목 수정은 수행하지 않는다.
    - 하위 이슈의 최종 표시 제목(`<App> <상위 제목> - <하위 제목>`)은 Jira Automation 결과를 따른다.
    - 예: 입력 `UI 구현` -> 표시 `[고객] 로그인 기능 추가 - UI 구현`
    - 설명은 Atlassian Document Format(ADF) JSON으로 작성하고, `--description-file`로 반영한다.
    - Jira Cloud는 마크다운/wiki markup을 자동 변환하지 않으므로, 반드시 ADF를 사용한다.
    - ADF 예시:

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [{ "type": "text", "text": "목표" }]
    },
    {
      "type": "paragraph",
      "content": [{ "type": "text", "text": "설명 내용" }]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [{ "type": "paragraph", "content": [{ "type": "text", "text": "항목 1" }] }]
        }
      ]
    }
  ]
}
```

    - 수정 명령 예시:
    - `acli jira workitem edit --key HDA-XXXX --description-file /tmp/HDA-XXXX-desc.txt --yes --json`

8. **검증**
   - `single` 모드:
   - `acli jira workitem view <이슈키> --fields "key,summary,description" --json`
   - `parent-with-subtasks` 모드:
   - `acli jira workitem view <상위키> --fields "key,summary,subtasks" --json`
   - `acli jira workitem view <하위키> --fields "key,summary,description" --json`

## 주의사항

- `acli jira workitem edit --from-json`은 생성과 JSON 구조가 다르다.
  - `additionalAttributes`는 지원되지 않으며, 커스텀 필드는 최상위 `customfield_xxxxx` 형태만 허용될 수 있다.
  - 프로젝트/필드 설정에 따라 edit로 App 변경이 실패할 수 있으므로 실패 시 제목 prefix/설명을 우선 보정한다.
- 위 제한이 있을 때는 다음 원칙을 따른다:
  - 생성 시점에 App 값을 정확히 넣는다.
  - 제목 prefix는 Jira Automation이 처리하므로 수동으로 붙이지 않는다. 설명만 필요 시 보정한다.
- 하위 이슈는 상위 이슈 생성 후 즉시 생성하여 parent 연결 누락을 방지한다.
- 상위 이슈 담당자는 생성 직후 `@me`로 고정해 자동 할당 정책 차이를 제거한다.
- 설명은 반드시 ADF JSON으로 작성한다. 마크다운(`###`)이나 wiki markup(`h3.`)은 Jira Cloud에서 렌더링되지 않고 텍스트로 표시된다.
  - ADF JSON을 `/tmp/<이슈키>-desc.txt` 파일로 만든 뒤 `--description-file`로 반영한다.
- 하위 이슈 summary는 Jira Automation이 후처리하므로, 생성 직후 수동 제목 보정은 하지 않는다.
