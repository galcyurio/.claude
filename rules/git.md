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
- 단순한 이름 변경은 `A -> B` 형태로 작성한다. (예: HDA-124 refactor: UserService -> AuthService)
- 가능한 한 기획자, 유저의 관점에서 커밋 메시지를 작성한다.
  - Good: `HDA-123 feat: 로그인 실패 시 재시도 버튼을 노출한다`
  - Bad: `HDA-123 feat: LoginViewModel에 retry 함수를 추가한다`
  - Good: `HDA-124 fix: 빈 카드 번호로 결제 시 에러 메시지를 표시한다`
  - Bad: `HDA-124 fix: PaymentValidator에 null 체크를 추가한다`
  - Good: `HDA-125 feat: 홈 화면 상단에 추천 차량 캐러셀을 노출한다`
  - Bad: `HDA-125 feat: HomeRecommendCarouselComposable을 구현한다`
- Claude Code 기본 Co-Authored-By trailer를 추가한다.

# 브랜치 생성 규칙

- 브랜치는 base 브랜치(develop 등)로 **먼저 이동한 뒤** `git checkout -b feature/X`만 사용한다.
- start-point로 `origin/develop` 같은 원격 ref를 **붙이지 않는다.** (`git checkout -b feature/X origin/develop` 금지)
  - 이유: git 기본값 `branch.autoSetupMerge=true`가 원격 ref를 upstream으로 자동 설정해 develop이 upstream으로 걸린다. 이 상태는 원치 않는다.
- 다른 브랜치에 체크아웃돼 있어서 develop 기준이 필요하면, "한 방에" 하려고 원격 ref를 붙이지 말고 먼저 `git switch develop`(또는 `git checkout develop`)으로 이동한 뒤 `git checkout -b feature/X` 한다.
- git config(`branch.autoSetupMerge` 등)는 변경하지 않는다.
- 이미 upstream이 걸렸으면 `git branch --unset-upstream`으로 해제한다.
