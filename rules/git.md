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

# push / PR 규칙

원격과 GitHub으로 나가는 액션은 사용자가 직접 통제한다. 나는 로컬 커밋까지만 하고 멈춘다.

## push

- git push·force push는 **사용자의 명시적 지시가 있을 때만** 한다. 커밋 후에는 브랜치명과 커밋 목록을 보고하고 멈춘다.
  - 이유: 사용자가 push 전에 커밋 히스토리를 직접 다듬는다(스쿼시·순서 변경·메시지 수정). 내가 먼저 push하면 force push가 필요해진다.
- "push해"라는 승인은 **그 한 번**에만 적용된다. 이후 커밋에 자동으로 확장되지 않는다.
- `AskUserQuestion` 옵션 선택("검증 후 PR" 등), 계획 승인, spec 승인은 push 승인이 아니다.
- "작업해" / "구현해" / "계속 진행해"의 종료점은 **코드 변경 + 로컬 커밋**이다. 그 다음은 멈추고 기다린다.
- 서브모듈 포인터 bump는 라이브러리 push가 선행돼야 하므로 같은 게이트에 걸린다.

## PR 생성

- PR 생성도 명시적 지시("PR 생성해", "PR 올려줘")가 있을 때만 한다. `create-pr` 스킬에 자동 진입하지 않는다.
- "PR 생성해"는 그 PR에 필요한 push를 포함한 승인으로 본다(push 없이 PR을 만들 수 없으므로). 단 그 1회에 한한다.
- 계획 문서에 "PR 생성" 태스크가 적혀 있어도 별도 지시를 기다린다.

## PR 코멘트

- 리뷰 코멘트를 반영해도 **PR에 커밋 해시 답글을 남기지 않는다.** resolve·re-request review도 먼저 보내지 않는다. PR 상의 소통은 사용자가 직접 한다.
- 대신 어느 커밋이 어느 코멘트에 대응하는지 **응답 본문에 표로 정리**해 사용자가 그대로 붙여넣을 수 있게 한다.
- 사용자가 그 턴에서 "댓글 남겨줘"라고 명시하면 그때는 남긴다.

## 스킬보다 우선

스킬 문서가 자동 push나 댓글 단계를 지시해도 이 규칙이 우선한다. 해당 단계를 건너뛰고 사용자에게 넘긴다.
