---
name: review-by-self
description: "변경사항을 difit(diff 뷰어)로 띄워 사용자가 직접 리뷰하게 하는 스킬. 사용자가 'review-by-self', 'difit', 'difit으로 띄워', 'difit으로 리뷰', '뷰어로 보여줘' 등을 지칭할 때만 사용한다. 일반 '리뷰해줘'·'코드 리뷰'·다관점 병렬 리뷰는 review-by-agents를 사용한다."
model: sonnet
effort: low
---

# review-by-self — difit 뷰어로 변경사항 직접 리뷰

## 개요

사용자의 diff를 difit으로 띄워 **사용자가 직접 리뷰**하게 하고, 남긴 코멘트를 회수하는 스킬이다. **세션을 막지 않는다.**

> **difit 공유 계약**: difit 실행(`<difit-command>` 선택 · `--no-open` · `--keep-alive` · nohup detach · 지킴이 동반)·회수(**사용자의 반영 요청** + `difit comment get`)·회수 후 종료는 `~/.claude/skills/review-by-self/difit-contract.md`를 따른다. 아래는 이 스킬 고유의 대상 선택·런치·회수 해석만 정의한다.

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

difit를 nohup으로 detach해 띄워 사용자가 리뷰하는 동안 세션이 막히지 않게 하고, **끝나지 않는 하니스 태스크도 남기지 않는다** (계약의 "실행" 참고 — `run_in_background`·difit `--background` 모두 쓰지 않는다).

- `nohup <difit-command> <target> --no-open --keep-alive --clean --port <N> > <스크래치패드>/difit-<N>.log 2>&1 &` 형태로 띄운다. **`--comment` 프리로드는 넣지 않는다**(시작 코멘트를 쓰지 않음 — 아래 참고).
- **`--no-open`이라 difit가 브라우저를 자동으로 열지 않는다.** 런치 1~3초 후 로그에서 `🚀 difit server started on http://localhost:<port>` 배너를 읽어 실제 바인딩 포트로 URL을 확정하고, pid는 `lsof -ti tcp:<port> -sTCP:LISTEN`으로 얻어 기록한다.
- **포트·pid를 확정한 직후 같은 Bash 호출에서 지킴이를 띄운다** (계약의 "세션 종료 자동 정리 — 지킴이"). 이 세션의 `claude` 프로세스(`$PPID`)가 사라지면 지킴이가 difit를 대신 종료한다.

  ```bash
  DIFIT_PID=$(lsof -ti tcp:<N> -sTCP:LISTEN)
  nohup bash -c "while kill -0 $PPID 2>/dev/null && kill -0 $DIFIT_PID 2>/dev/null; do sleep 5; done
    P=\$(lsof -ti tcp:<N> -sTCP:LISTEN 2>/dev/null)
    [ \"\$P\" = \"$DIFIT_PID\" ] && kill \"\$P\"" >/dev/null 2>&1 &
  ```

- 사용자에게 **URL을 안내**하고, **직접 브라우저를 열어 리뷰한 뒤 남긴 코멘트가 있으면 알려달라**고 안내한 뒤 턴을 종료한다. **종료를 위한 신고는 요구하지 않는다** — 남길 코멘트가 없으면 그대로 닫아도 지킴이가 difit를 정리한다는 점을 함께 안내한다. `--keep-alive`라 브라우저를 닫아도 서버는 유지되므로, 브라우저 닫힘을 폴링하지 않는다(detach 실행이라 기다릴 하니스 잡도 없다).

## 코멘트 회수

사용자가 **남긴 코멘트를 반영해 달라고 요청하거나 리뷰를 끝냈다고 알리면** `difit comment get --port <N> --format text`로 실행 중 서버에서 코멘트를 회수한다(계약의 "회수" 포맷). 이 스킬은 `--comment` 프리로드가 없으므로 **회수된 모든 코멘트가 사용자가 남긴 것**이다 — 별도 대조 없이 그대로 반영한다. 신호가 오지 않고 세션이 닫히는 것도 정상 경로이며, 그때는 지킴이가 서버만 정리하고 회수는 일어나지 않는다.

- 코멘트가 있으면 각 코멘트(`file`:`line` + 본문)를 반영하고 작업을 이어간다.
- `Total comments: 0`이거나 블록이 없으면 "리뷰 코멘트 없음"으로 간주한다. difit를 다시 띄울 필요 없다.
- 회수를 끝냈으면 계약의 "회수 후 종료"에 따라 **우리가 쓴 그 포트의 difit 서버를 종료**한다(회수 → 종료 순서, `kill $(lsof -ti tcp:<port> -sTCP:LISTEN)` — `-sTCP:LISTEN`을 빼면 접속 중인 브라우저까지 종료된다).

## 시작 코멘트를 쓰지 않는다

**직접 difit 요청에는 시작 코멘트를 작성하지 않는다.** 사용자가 difit를 직접 호출하면(예: `/review-by-self`, "difit으로 띄워") diff 뷰어를 원하는 것이지 AI 의견을 원하는 게 아니다. 즉시 띄운다: 런치 전에 diff를 읽어 "핵심 결정"을 찾거나, 라인 번호를 grep하거나, `--comment` 페이로드를 작성하지 **않는다**. 그 사전 분석이 difit를 느리게 만든다.

`--comment`로 리뷰 결과를 인라인 프리로드하는 것은 `review-by-agents` 스킬 전용이다 (그 스킬 6-A 참고).

## 제약

- Git으로 관리되는 디렉토리 안에서만 사용할 수 있다.
- 회수를 끝내기 전에는 difit 서버를 종료하지 않는다. 회수 후에는 **우리가 쓴 그 포트만** 종료하고, 무관한 difit 서버까지 광범위하게 죽이지 않는다 (계약의 "회수 후 종료" 참고). detach된 프로세스는 하니스가 정리해 주지 않지만, 회수 없이 세션이 닫히는 경로는 런치 때 함께 띄운 지킴이가 받친다.
