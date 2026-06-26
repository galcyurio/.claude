---
name: review-by-self
description: "변경사항을 difit(diff 뷰어)로 띄워 사용자가 직접 리뷰하게 하는 스킬. 사용자가 'review-by-self', 'difit', 'difit으로 띄워', 'difit으로 리뷰', '뷰어로 보여줘' 등을 지칭할 때만 사용한다. 일반 '리뷰해줘'·'코드 리뷰'·다관점 병렬 리뷰는 review-by-agents를 사용한다."
model: sonnet
effort: low
---

# review-by-self — difit 뷰어로 변경사항 직접 리뷰

## 개요

사용자의 diff를 difit으로 띄워 **사용자가 직접 리뷰**하게 하고, 남긴 코멘트를 회수하는 스킬이다. **세션을 막지 않는다.**

`<difit-command>` 선택:

- `command -v difit`가 성공하면 `difit`를 사용한다.
- 아니면 `npx difit`를 사용한다.
- 샌드박스에서 네트워크 권한이 없어 `npx difit` 실행에 네트워크가 필요하면, 권한 상승을 요청하고 사용자 승인을 받은 뒤 실행한다.

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

## 런치 (논블로킹)

difit를 **백그라운드 프로세스로** 띄워 사용자가 리뷰하는 동안 세션이 막히지 않게 한다:

- `<difit-command> <target>`를 백그라운드로 실행한다 (명령이 끝나길 기다리며 턴을 막지 않는다).
- difit 자체의 `--background` 플래그는 **쓰지 않는다** — `--no-open`을 강제해 브라우저가 열리지 않는다. 평범한 `<difit-command> <target>`를 백그라운드 잡으로 띄워야 뷰어가 열린다.
- `--keep-alive`는 **쓰지 않는다**. 이게 없으면 사용자가 브라우저를 닫을 때 difit가 스스로 종료된다. 이 자동종료가 "리뷰 끝" 신호이며 별도 정리가 필요 없다.
- `--comment`는 **작성하지 않는다** ("시작 코멘트 — review-by-agents 전용" 참고).

difit는 `difit server started on http://localhost:<port>`를 출력하고 브라우저를 연다. 사용자에게 뷰어가 열렸으며 **리뷰가 끝나면 브라우저를 닫으라**고 안내한 뒤 턴을 종료한다. 페이지가 떴는지 검증하지 않는다. 폴링하지 않는다.

## 코멘트 회수

백그라운드 difit 작업은 사용자가 브라우저를 닫으면 스스로 끝난다(client disconnect 시 서버 자동종료). 그 작업이 완료되면 출력을 읽는다. difit는 세션 중 남긴 코멘트를 종료 시 출력한다:

```
📝 Comments from review session:
==================================================
<file>:L<line>
<comment body>
==================================================
Total comments: N
```

- 코멘트 블록이 있으면 각 코멘트(`file`:`line` + 본문)를 반영하고 작업을 이어간다.
- `Total comments: 0`이거나 코멘트 블록이 없으면 "리뷰 코멘트 없음"으로 간주한다. difit를 다시 띄울 필요 없다.

## difit 프로세스를 절대 kill하지 않는다

**difit에 `kill`·`pkill`·`lsof … | xargs kill`을 절대 실행하지 않는다.** difit는 브라우저를 자식 프로세스로 띄우므로, difit(또는 그 프로세스 그룹)를 kill하면 사용자 브라우저가 함께 종료될 수 있다. difit는 브라우저가 닫히면 스스로 깨끗이 종료된다 — 항상 자가 종료하게 둔다.

## 시작 코멘트 — review-by-agents 전용

**직접 difit 요청에는 시작 코멘트를 작성하지 않는다.** 사용자가 difit를 직접 호출하면(예: `/review-by-self`, "difit으로 띄워") diff 뷰어를 원하는 것이지 AI 의견을 원하는 게 아니다. 즉시 띄운다: 런치 전에 diff를 읽어 "핵심 결정"을 찾거나, 라인 번호를 grep하거나, `--comment` 페이로드를 작성하지 **않는다**. 그 사전 분석이 difit를 느리게 만든다.

`--comment` 플래그는 `review-by-agents` 스킬 전용이다. 그 스킬이 리뷰 결과로 코멘트 페이로드를 직접 만들고 difit 명령도 직접 조립한다(review-by-agents 6-A단계 참고). 참고용 문법:

```bash
<difit-command> <target> [compare-with] \
  --comment '{"type":"thread","filePath":"src/foobar.ts","position":{"side":"old","line":102},"body":"line 1\nline 2"}' \
  --comment '{"type":"thread","filePath":"src/example.ts","position":{"side":"new","line":{"start":36,"end":39}},"body":"Range comment for L36-L39"}'
```

review-by-agents가 이 코멘트를 만들 때:

- 각 코멘트에 `type: "thread"`를 쓴다.
- 코멘트 본문은 사용자가 쓰는 언어로 작성한다.
- diff의 target 쪽에 존재하는 라인은 `position.side: "new"`, 삭제된 쪽에만 있는 라인은 `"old"`를 쓴다.
- 여러 줄에 걸친 이슈는 range 코멘트를 쓴다.
- 토큰·비밀번호·API 키·개인키 등 자격증명류를 `--comment` 본문이나 명령줄 인자에 절대 복사하지 않는다.

## 미추적 파일 포함

미커밋 변경에서, 아직 git에 추가되지 않은 파일도 diff에 보이게 하려면 `--include-untracked`를 추가한다.

```bash
<difit-command> . --include-untracked
```

## 제약

- Git으로 관리되는 디렉토리 안에서만 사용할 수 있다.
- difit 프로세스를 절대 kill하지 않는다 ("difit 프로세스를 절대 kill하지 않는다" 참고).
