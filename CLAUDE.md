# 전역 응답 언어 규칙

- 모든 답변은 한국어로 작성한다.
- 사용자가 다른 언어를 명시적으로 요청한 경우에만 해당 응답에서 그 언어를 따른다.
- 코드, 파일 경로, 명령어, 오류 메시지는 필요 시 원문을 유지하되 설명은 한국어로 제공한다.

# 세션 이름 규칙
- Jira 이슈가 확인되면 Jira ID와 Title을 이용해 세션 이름을 작성한다.
- 규칙: ${JiraId} ${JiraTitle}
- 예시: HDA-10000 [고객] 로그인 기능 추가
- 세션 이름을 지을 때는 설명 없이 `/rename ${JiraId} ${JiraTitle}` 한 줄만 단독 출력한다.

# 코드 수정 검증 절차

## Kotlin/Java 파일 수정 규칙

- Kotlin(`.kt`), Java(`.java`) 파일은 `bash` heredoc(`cat > file << 'EOF'`)으로 수정한다. (IDE MCP 도구의 자동 포맷터 회피)
- 포맷 변경이 섞여 있으면 `git restore --source=HEAD -- <파일>`로 원복 후 재작성한다.

## 범위 이탈 방지 절차 (필수)

- 수정 시작 전 `git status --short`로 대상 파일을 명시한다.
- 수정 직후 `git diff -- <대상파일>`로 확인하고, 요청과 무관한 변경은 즉시 원복한다.
- 파일 단위 원복은 `git restore --source=HEAD -- <파일경로>`를 사용한다.
- 여러 파일 수정 시 마지막 응답 전 `git status --short`로 대상 외 변경이 없는지 재확인한다.

# PR 제목 규칙
- PR 제목은 Jira issue 제목과 동일하게 작성한다.
