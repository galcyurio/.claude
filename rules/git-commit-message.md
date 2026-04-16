# Git commit message 규칙

- 커밋 메시지는 한글로 작성한다.
- Issue ID를 가장 앞에 작성한다. (예: HDA-123)
  - Issue ID를 찾지 못한 경우에는 작성하지 않는다.
- 태그는 feat, fix, refactor, docs, style, test, chore 중 하나만 사용한다.
- 형식은 `IssueID 태그: 커밋 내용`으로 작성한다. (예: HDA-123 feat: 로그인 기능을 추가한다)
- 태그 뒤에는 콜론(:)을 붙이고, 콜론 뒤에는 한 칸 띄운다.
- 커밋 내용은 명령문 형태로 작성한다.
- 커밋 내용 끝에 마침표(.)를 붙이지 않는다.
- 커밋 메시지 본문은 첫째 줄에 1줄 요약을 작성하고, 상세 내용이 있으면 둘째 줄을 비운 뒤 셋째 줄부터 작성한다.
- 단순한 이름 변경은 `A -> B` 형태로 작성한다. (예: HDA-124 refactor: UserViewModel -> AuthViewModel)
