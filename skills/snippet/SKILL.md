---
name: snippet
description: "오늘의 GitHub 활동(PR 생성, PR 리뷰)을 Notion snippet 문서에 자동 추가하는 스킬. `--weekly`를 주면 이번 주 PR과 배포 공지로 Notion weekly snippet을 작성한다. 사용자가 'snippet', '스니펫', '오늘 업무 정리', 'snippet 업데이트', 'snippet 추가', '오늘 뭐했지', '업무 기록', '주간 스니펫', 'weekly snippet', '이번 주 업무 정리' 등을 언급할 때 이 스킬을 사용해야 한다."
---

# Snippet - Notion 일일 업무 기록 자동화

GitHub 활동(PR 생성 + PR 리뷰)을 Notion의 daily snippet 문서에 자동으로 추가한다.

인자에 `--weekly`가 있으면 아래 daily 워크플로우를 건너뛰고 [weekly 모드](#weekly-모드---weekly)만 실행한다.

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
- `# 코드리뷰` 섹션은 항상 코드블록 **가장 마지막**에 위치, 리뷰한 PR은 `- ` prefix

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
4. `# 코드리뷰` 섹션 없으면 코드블록 끝에 새로 생성
5. `old_str`은 `notion-fetch` 결과를 **한 글자도 바꾸지 않고** 그대로 사용

### 6단계: 결과 보고

```
snippet 업데이트 완료:
- PR 생성: N건 추가
- 코드리뷰: N건 추가
- 중복 제외: N건
```

Notion 페이지 URL도 함께 제공한다.

---

## weekly 모드 (`--weekly`)

이번 주(월요일 ~ 오늘)에 내가 만든 PR과 내가 올린 배포 공지를 모아 Notion weekly snippet 문서를 작성한다.

### 기본 정보

- **Notion weekly DB**: `https://app.notion.com/p/75918a70ca7e4b47969b98ddabf7dba0`
- **data source ID**: `19b78dae-1391-4a9b-8053-d6acb5141734` (속성은 `Name` title 하나만 쓴다)
- **문서 제목**: `YYYY-MM N주차` (예: `2026-11 3주차`)
- 매주 금요일 01:00에 제목 없는 빈 페이지가 자동으로 생기지만 쓰지 않는다. 손대지 않고 제목으로 찾은 페이지만 다룬다.

### 주차 계산

이번 주(월~일)의 **수요일**이 속한 달과 `ceil(수요일 일자 / 7)`로 정한다. 평일 다수가 속한 달로 묶는 규칙과 같고, 기존 문서 제목(`2026-10-02` → `2026-09 5주차`, `2026-09-04` → `2026-09 1주차`)이 모두 이 규칙을 따른다.

```bash
monday=$(date -v-mon +%F)
today=$(date +%F)
wed_day=$(date -v-mon -v+2d +%d)
title="$(date -v-mon -v+2d +%Y-%m) $(( (10#$wed_day + 6) / 7 ))주차"
```

### 문서 구조

코드블록 ` ```markdown ``` ` 1개에 아래 순서로 쓴다.

```markdown
# [공통][헤이딜러 로딩 심볼 변경] - 개발 중
- HDA-23929 [공통][헤이딜러 로딩 심볼 변경] 로딩 심볼 크기를 시안에 맞게 수정
- HDA-23876 [공통][헤이딜러 로딩 심볼 변경] 헤이딜러 로딩 심볼 Lottie 교체

# 버그 수정
- HDA-23912 [테크베이-공업사] 첨부파일 선택 시 영상이 노출되지 않는 문제 수정

# 기능 개선
- HDA-23829 [리볼트] 차량상세 옵션 - '선택 옵션' Tag 추가

# 코드 개선
- HDA-23752 [라이브러리][Lint 개선] 커스텀 룰 detekt 설정에 활성화
- HDA-23899 [AI] Atlassian MCP v2 커스텀 필드 응답 구조 대응

========================================

# 고객 7.144.0
- #ftr-사기-고객-마켓-결심낮추기ver2-ab
- 마켓 B안 보험이력에 '완전무사고 차량인데, 왜 보험 이력이 있나요?' 배너 노출

# 딜러 5.118.0
- 일부 기기에서 포토피커가 열리지 않는 문제 수정
```

- 피처 섹션(`# [앱][에픽명] - 상태`)이 먼저 오고, 그 뒤에 `버그 수정` → `기능 개선` → `코드 개선` 순서로 둔다. 항목이 없는 섹션은 만들지 않는다.
- 섹션 사이는 빈 줄 1개, 항목에는 설명을 붙이지 않는다 (`- {PR 제목}` 한 줄).
- 섹션 안에서는 PR 생성 시각이 늦은 것부터 쓴다.
- 배포 공지가 없으면 구분선과 배포 섹션을 생략한다.

### 1단계: 이번 주 PR 수집

```bash
gh search prs --author=olaf-prnd --owner=PRNDcompany --created=${monday}..${today} --json title,number,url,repository,createdAt --limit 100
```

- **제외**: 제목에 `HDA-` 키가 없는 PR(`QA 전달용 PR` 등), `develop 브랜치 최신화`, `release X.Y.Z`, `merge/` 브랜치 PR
- **중복 제거**: 같은 HDA 키는 저장소가 달라도 1건으로 합친다 (라이브러리 + 앱 PR, 여러 앱에 같은 커밋을 올린 PR).

수집 결과가 0건이면 "이번 주에는 기록할 PR이 없습니다." 출력 후 종료한다.

### 2단계: 섹션 분류

PR 제목의 두 번째 대괄호(`[고객][에픽명]`의 `에픽명`)를 기준으로 판단한다.

| 분류 | 기준 | 제목 처리 |
|---|---|---|
| 피처 섹션 | 사용자 기능을 만드는 피처 에픽 (`-ab`, 기획 피처명) | 그대로 |
| 코드 개선 | `[라이브러리]`, `[AI]`, `[workflow]`, `[Lint 개선]`·`[AbTest 통합]`처럼 기술 개선 에픽, 리팩토링·코드 제거 | 그대로 |
| 버그 수정 | 피처에 속하지 않는 오류·크래시 수정 | 그대로 |
| 기능 개선 | 피처에 속하지 않는 사용자 화면 변경·문구 수정 | 그대로 |

- 지난주에 끝난 피처의 후속 PR이 이번 주에 1건만 남았다면 피처 섹션을 만들지 않고 `기능 개선`·`버그 수정`으로 보내며, 제목에서 에픽 대괄호를 뺀다 (예: `[리볼트][사기-마켓-이 차, 사도 괜찮나요-ab] 차량상세 옵션…` → `[리볼트] 차량상세 옵션…`).
- 피처 섹션 헤더는 섹션 안 PR 제목들의 공통 대괄호 prefix를 쓴다 (`[공통][헤이딜러 로딩 심볼 변경]`).

### 3단계: 피처 상태 조회

피처 섹션마다 PR 1건의 HDA 이슈를 `getJiraIssue`로 조회해 parent(에픽)의 상태를 읽는다 (cloudId: `prndcompany.atlassian.net`).

- 에픽이 완료 계열(Done·Deployed·Released 등) → `완료`
- 그 외 → `개발 중`
- `배포 보류` 같은 판단은 사용자가 직접 고친다. 추정해서 쓰지 않는다.

### 4단계: 배포 공지 수집

이번 주 #work-qa에 내가 올린 배포 공지를 Slack에서 찾는다.

```
slack_search_public_and_private(query: "in:#work-qa from:<@U02433C1U69> after:{monday 전날}", sort: "timestamp")
```

- `고객 7.144.0`처럼 `{앱} {버전}` 줄로 시작하는 공지만 쓴다. 같은 버전 공지가 여러 번이면 마지막 것만 쓴다.
- 앱마다 `# {앱} {버전}` 섹션을 만들고, 공지의 bullet을 `- ` 항목으로 옮긴다.
- 링크는 텍스트만 남긴다: `<url|텍스트>` → `텍스트`, 채널 멘션 `<#C…|ftr-xxx>` → `#ftr-xxx`.
- 공지가 없으면 배포 섹션을 생략한다.

### 5단계: 문서 찾기 또는 생성

```
notion-query-data-sources(sql: SELECT url, "Name" FROM "collection://19b78dae-1391-4a9b-8053-d6acb5141734" WHERE "Name" = ?, params: [title])
```

- **없으면**: `notion-create-pages`로 생성한다. parent는 `data_source_id: 19b78dae-1391-4a9b-8053-d6acb5141734`, properties는 `{"Name": title}`, content는 문서 구조의 코드블록이다.
- **있으면**: `notion-fetch`로 코드블록을 읽고, HDA 키 기준으로 **아직 없는 항목만** 해당 섹션 끝에 추가한다 (섹션이 없으면 규칙 순서에 맞는 자리에 만든다). 배포 섹션은 없는 앱 버전만 추가한다. 기존 내용·사용자가 고친 상태 표기는 보존하고, `notion-update-page`의 `update_content`로 코드블록 전체를 교체하되 `old_str`은 fetch 결과를 그대로 쓴다. 추가할 항목이 없으면 "이미 모든 항목이 기록되어 있습니다." 출력 후 종료한다.

### 6단계: 결과 보고

```
weekly snippet 작성 완료: {title}
- 피처 섹션: N개 (항목 N건)
- 버그 수정 / 기능 개선 / 코드 개선: N / N / N건
- 배포: {앱 버전 나열 또는 "없음"}
```

Notion 페이지 URL과 함께, 분류를 판단으로 정한 항목(피처 섹션 vs 기능 개선 등)과 `개발 중`으로 둔 피처 상태를 확인해 달라고 덧붙인다. #snippet-android-weekly 채널 전송은 하지 않는다.
