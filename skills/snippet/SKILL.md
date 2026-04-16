---
name: snippet
description: "오늘의 GitHub 활동(PR 생성, PR 리뷰)을 Notion snippet 문서에 자동 추가하는 스킬. 사용자가 'snippet', '스니펫', '오늘 업무 정리', 'snippet 업데이트', 'snippet 추가', '오늘 뭐했지', '업무 기록' 등을 언급할 때 이 스킬을 사용해야 한다."
---

# Snippet - Notion 일일 업무 기록 자동화

GitHub 활동(PR 생성 + PR 리뷰)을 Notion의 daily snippet 문서에 자동으로 추가한다.

## 기본 정보

- **GitHub 유저**: `olaf-prnd`
- **GitHub 조직**: `PRNDcompany`
- **Notion snippet DB data source ID**: `6515fb4a-e26e-4cf4-ad60-c3d5b8d04f40`
- **snippet 문서 제목**: `@YYYY년 M월 D일 ` (예: `@2026년 4월 3일 `) — 끝에 공백 1개 포함

---

## 작성 패턴

### 문서 구조

`# \[오늘 완료업무\]`와 `# \[내일 예정업무\]` 아래 각각 ` ```markdown ``` ` 코드블록 1개씩.

### 코드블록 내부 형식

```
- {작업 제목}
: 세부 사항
```

- 각 항목은 `- `로 시작, 항목 사이 빈 줄 1개
- 서브 항목: `: `(작업/세부)
- `# 코드 리뷰` 섹션은 항상 코드블록 **가장 마지막**에 위치, 리뷰한 PR은 `- ` prefix

### 예시

```markdown
- HDA-20873 [고객] 레거시 car-link 딥링크 제거

- HDA-20871 [딜러] 비로그인 상태에서도 채팅문의 가능하도록 처리
: 기존에는 로그인이 되어 있어야 Chat SDK를 사용할 수 있다는 설계였음
: 딜러앱에서 로그인전에도 채팅문의 해야하는 요건이 있어서 설계 변경

# 코드리뷰
- HDA-20861 [고객][개인정보 이용고지] 전화번호 인증 Flow 개선
- HDA-20862 [고객][개인정보 이용고지] 전화번호 인증 화면 문구 변경
```

---

## 워크플로우

### 1단계: GitHub 활동 수집 + Early Exit

아래 두 가지를 **병렬로** Bash 실행한다.

```bash
gh search prs --author=olaf-prnd --owner=PRNDcompany --created=$(date +%Y-%m-%d) --json title,number,url --limit 50
```

```bash
gh search prs --reviewed-by=olaf-prnd --owner=PRNDcompany --updated=$(date +%Y-%m-%d) --json title,number,url,author --limit 50
```

- 내가 만든 PR: 제목 기준 중복 제거
- 내가 리뷰한 PR: `author.login`이 `olaf-prnd`인 것 제외, 제목 기준 중복 제거

**Early Exit**: 둘 다 빈 배열이면 → "오늘은 새로운 GitHub 활동이 없습니다." 출력 후 **즉시 종료**. Notion 호출 안 함.

### 2단계: 오늘자 snippet 문서 찾기 또는 생성

```
notion-search(query: "M월 D일", data_source_url: "collection://6515fb4a-e26e-4cf4-ad60-c3d5b8d04f40", page_size: 25, max_highlight_length: 0)
```

**검색 규칙:**
1. `page_size: 25`로 충분히 넓게 검색한다 (오늘자 문서가 랭킹에서 밀릴 수 있음).
2. 결과에서 title이 정확히 `@YYYY년 M월 D일 `인 것만 사용한다.
3. 매칭 결과가 없으면 쿼리를 `@YYYY년 M월 D일`로 바꿔 **1회 재검색**한다.
4. 재검색에서도 없으면 `notion-create-pages`로 생성한다 (어제 문서의 [내일 예정업무] 복사).

**중복 문서 생성 방지**: 검색 결과가 0건이어도 바로 생성하지 말고 반드시 재검색까지 완료한 후 생성한다.

### 3단계: 기존 문서 읽기 + 중복 체크

`notion-fetch`로 문서 내용을 가져오고, `[오늘 완료업무]` 코드블록에서 기존 HDA 번호와 제목을 추출한다.

**중복 판단**: HDA 번호가 있으면 번호로, 없으면 제목 전체로 비교.

**Early Exit**: 1단계에서 수집한 항목이 **전부 중복**이면 → "이미 모든 항목이 기록되어 있습니다." 출력 후 **즉시 종료**. Notion update 호출 안 함.

### 4단계: 새 PR 본문 가져오기

중복이 아닌 **새 PR에 대해서만** 본문을 가져온다 (불필요한 API 호출 방지).

```bash
gh pr view {url} --json body --jq '.body'
```

PR 본문을 읽고 핵심 내용을 `: ` 또는 `- ` 마커로 **1줄 (최대 2줄)** 요약한다.
- 비슷한 작업끼리 묶인 경우는 설명 생략
- PR 본문이 비어있거나 템플릿만 있으면 설명 생략

### 5단계: 내용 추가

`notion-update-page`의 `update_content` command로 첫 번째 코드블록 전체를 교체한다.

```
notion-update-page:
  page_id: "{page_id}"
  command: "update_content"
  properties: {}
  content_updates: [{ old_str: "{기존 코드블록 전체}", new_str: "{새 항목 추가된 코드블록 전체}" }]
```

**조합 규칙:**
1. 기존 내용 모두 보존
2. 새 PR 항목: `# 코드리뷰` 섹션 **바로 위**에 추가 (`- {제목}` + 본문 요약)
3. 새 코드리뷰 항목: `# 코드리뷰` 섹션 **내부 마지막**에 추가 (`- {제목}`, 설명 없음)
4. `# 코드 리뷰` 섹션 없으면 코드블록 끝에 새로 생성
5. `old_str`은 `notion-fetch` 결과를 **한 글자도 바꾸지 않고** 그대로 사용

### 6단계: 결과 보고

```
snippet 업데이트 완료:
- PR 생성: N건 추가
- 코드리뷰: N건 추가
- 중복 제외: N건
```

Notion 페이지 URL도 함께 제공한다.
