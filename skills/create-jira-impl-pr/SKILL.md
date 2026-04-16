---
description: Jira 이슈 생성 → 구현 → PR 생성을 한 번에 처리
argument-hint: [작업 설명]
allowed-tools: mcp__atlassian__*, Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Agent
---

# Jira → 구현 → PR

Jira 이슈 생성부터 구현, PR 생성까지 한 번에 처리한다.

## Context

- Current branch: !`git branch --show-current`
- Remote URL: !`git remote get-url origin`

## 인자 파싱

사용자 입력에서 다음을 추출한다:
- **이슈 제목**: 작업을 요약한 짧은 문장 (prefix 없이)
- **작업 설명**: 구현할 내용, 참조 파일/URL 등

## Phase 1: Jira 이슈 생성

Cloud ID: `4e8e1a3d-2b6f-40df-820b-43c476f41656` (prndcompany)

### 1-1. 에픽/프로젝트 결정

현재 브랜치명에서 `HDA-XXXXX` 패턴 추출 → `mcp__atlassian__getJiraIssue`로 에픽 찾기.

에픽 확인 (우선순위):
1. 브랜치 이슈 자체가 에픽 → 해당 이슈
2. `parent`가 에픽 → 해당 parent
3. `customfield_10014` (Epic Link) 존재 → 해당 값

- 에픽 찾음 → 프로젝트 키/App 상속
- 못 찾음 → 사용자에게 App 선택 요청:

| 번호 | App | ID |
|------|-----|----|
| 1 | 고객 | 10216 |
| 2 | 딜러 | 10217 |
| 3 | 딜러-콜 | 10219 |
| 4 | 평가사 | 10218 |
| 5 | 평가사-콜 | 10248 |
| 6 | 평가사-카메라 | 10253 |
| 7 | 리볼트 | 10249 |
| 8 | 테크베이-어드민 | 10292 |
| 9 | 테크베이-공업사 | 10259 |
| 10 | 라이브러리 | 10220 |
| 11 | 공통 | 10242 |
| 12 | workflow | 10254 |
| 13 | AI | 10392 |

### 1-2. 이슈 생성

`acli jira workitem create --from-json /tmp/jira-task.json --json`으로 생성:

```json
{
  "projectKey": "<프로젝트 키>",
  "type": "작업",
  "summary": "<이슈 제목>",
  "additionalAttributes": {
    "customfield_10302": { "value": "<App 값>" }
  }
}
```

에픽이 있으면 `"parent": { "key": "<에픽 키>" }` 추가.

생성 직후:
- `acli jira workitem edit --key <이슈키> --assignee @me --yes`
- 설명은 ADF JSON으로 작성 → `--description-file`로 반영

### 1-3. 결과 확인

```
✅ <이슈 키> <이슈 제목>
   🔗 https://prndcompany.atlassian.net/browse/<이슈 키>
```

## Phase 2: 브랜치 생성

### base 브랜치 결정

| 조건 | base |
|------|------|
| 사용자 지정 | 지정 브랜치 |
| 에픽 있음 | `git branch -r \| grep "origin/feature-base/{EPIC-KEY}"` (0개→아래 기본값, 1개→해당 브랜치) |
| 그 외 | `develop` 브랜치 존재 시 `develop`, 없으면 `main` |

### 브랜치 생성

```bash
git checkout <base> && git pull && git checkout -b feature/<이슈키>-<slug>
```

slug: 이슈 제목 핵심 키워드를 영문 kebab-case로 변환 (30자 이내).

## Phase 3: 구현

사용자의 작업 설명을 기반으로 필요한 파일을 생성/수정한다.

- 참조 URL이 있으면 `gh api` 또는 WebFetch로 내용 확인
- 기존 코드 패턴을 따라 구현
- 변경 범위를 최소한으로 유지
- 구현 전후 `git status --short`로 대상 파일 확인

## Phase 4: 커밋 & 푸시

```bash
git add <변경파일>
git commit -m "<이슈키> <tag>: <내용>"
git push -u origin <브랜치>
```

커밋 메시지: 한글, 명령문, 태그(feat/fix/refactor/docs/style/test/chore).

## Phase 5: PR 생성

### 5-1. JIRA summary 재조회

`mcp__atlassian__getJiraIssue`로 이슈 조회하여 Automation이 적용된 최신 summary를 가져온다.

### 5-2. PR 내용 작성

1. `.github/PULL_REQUEST_TEMPLATE.md` 읽기 (없으면 기본 형식)
2. 템플릿 섹션 채우기:
   - **개요**: 왜 필요한지, 어떤 문제를 해결하는지
   - **작업사항**: 구현한 내용 정리
   - 비어있는 섹션은 제거
3. 본문은 마크다운 형식 (목록 `- `, 코드 `` ` ``)

### 5-3. PR 생성

```bash
gh pr create --base <base브랜치> --title "<이슈키> <JIRA summary>" --body "<본문>"
```

- title: `{이슈키} {JIRA summary}` — Automation 적용된 summary 그대로 사용
- base: Phase 2에서 결정한 브랜치

## 최종 결과

테이블 형식으로 출력:

| 항목 | 결과 |
|------|------|
| Jira 이슈 | `[이슈키](URL)` - 제목 |
| 브랜치 | 브랜치명 |
| 변경 파일 | 파일 목록 |
| PR | PR URL |
