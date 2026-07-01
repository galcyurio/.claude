---
name: review-by-self
description: "변경사항을 difit(diff 뷰어)로 띄워 사용자가 직접 리뷰하게 하는 스킬. 사용자가 'review-by-self', 'difit', 'difit으로 띄워', 'difit으로 리뷰', '뷰어로 보여줘' 등을 지칭할 때만 사용한다. 일반 '리뷰해줘'·'코드 리뷰'·다관점 병렬 리뷰는 review-by-agents를 사용한다."
model: sonnet
effort: low
---

# review-by-self — difit 뷰어로 변경사항 직접 리뷰

## 개요

사용자의 diff를 difit으로 띄워 **사용자가 직접 리뷰**하게 하고, 남긴 코멘트를 회수하는 스킬이다. **세션을 막지 않는다.**

> **difit 공유 계약**: difit 실행(`<difit-command>` 선택)·수명(하니스 백그라운드 · `--keep-alive` 없이 브라우저 닫힘 시 자가 종료)·**kill 금지**·회수(종료 시 stdout 덤프 포맷)는 `~/.claude/skills/review-by-self/difit-contract.md`를 따른다. 아래는 이 스킬 고유의 대상 선택·런치·회수 해석만 정의한다.

## 리뷰 대상 선택

사용자가 무엇을 리뷰하려는지에 따라 대상을 고른다:

- 커밋 전 미커밋 변경 리뷰: `<difit-command> .`
- HEAD 커밋 리뷰: `<difit-command>`
- 스테이징 영역 변경 리뷰: `<difit-command> staged`
- 미스테이징 변경만 리뷰: `<difit-command> working`

```bash
<difit-command> <target>                    # 단일 커밋 diff 보기. 예: difit 6f4a9b7
<difit-command> <target> [compare-with]     # 두 커밋/브랜치 비교. 예: difit feature main
```

미커밋 변경에서 아직 git에 추가되지 않은 파일도 diff에 보이게 하려면 `--include-untracked`를 추가한다 (`<difit-command> . --include-untracked`).

## 런치 (논블로킹)

difit를 하니스 백그라운드 잡으로 띄워 사용자가 리뷰하는 동안 세션이 막히지 않게 한다 (계약의 "실행" 참고).

- **`--comment`·`--no-open`을 쓰지 않는다.** difit가 브라우저를 자동으로 열어 사용자가 바로 리뷰하게 한다. 시작 코멘트·프리로드는 넣지 않는다(아래 "시작 코멘트를 쓰지 않는다" 참고).
- difit가 `difit server started on http://localhost:<port>`를 출력하고 브라우저를 연다. 사용자에게 뷰어가 열렸으며 **리뷰가 끝나면 브라우저를 닫으라**고 안내한 뒤 턴을 종료한다. 페이지가 떴는지 검증하거나 폴링하지 않는다.

## 코멘트 회수

difit 백그라운드 잡은 사용자가 브라우저를 닫으면 스스로 끝난다. 잡이 완료되면 stdout 덤프(계약의 "회수" 포맷)를 읽는다. 이 스킬은 `--comment` 프리로드가 없으므로 **덤프의 모든 코멘트가 사용자가 남긴 것**이다 — 별도 대조 없이 그대로 반영한다.

- 코멘트가 있으면 각 코멘트(`file`:`line` + 본문)를 반영하고 작업을 이어간다.
- `Total comments: 0`이거나 블록이 없으면 "리뷰 코멘트 없음"으로 간주한다. difit를 다시 띄울 필요 없다.

## 시작 코멘트를 쓰지 않는다

**직접 difit 요청에는 시작 코멘트를 작성하지 않는다.** 사용자가 difit를 직접 호출하면(예: `/review-by-self`, "difit으로 띄워") diff 뷰어를 원하는 것이지 AI 의견을 원하는 게 아니다. 즉시 띄운다: 런치 전에 diff를 읽어 "핵심 결정"을 찾거나, 라인 번호를 grep하거나, `--comment` 페이로드를 작성하지 **않는다**. 그 사전 분석이 difit를 느리게 만든다.

`--comment`로 리뷰 결과를 인라인 프리로드하는 것은 `review-by-agents` 스킬 전용이다 (그 스킬 6-A 참고).

## 제약

- Git으로 관리되는 디렉토리 안에서만 사용할 수 있다.
- difit 프로세스를 절대 kill하지 않는다 (계약의 "절대 kill하지 않는다" 참고).
