# difit 공유 계약

`review-by-self` · `review-by-agents`가 공통으로 따르는 difit 뷰어 실행·수명·회수 계약이다. 각 스킬은 difit를 다루는 단계에서 이 파일을 Read해 아래를 따르고, 스킬 고유 부분(브라우저 오픈 여부·`--comment` 프리로드·게이트·회수 해석)은 각 SKILL.md가 정의한다.

## `<difit-command>` 선택

- `command -v difit` 성공 → `difit`
- 실패 → `npx difit`
- 샌드박스에서 네트워크 권한이 없어 `npx difit` 실행이 막히면, 권한 상승을 요청하고 사용자 승인 후 실행한다.

## 실행 — 하니스 백그라운드 잡

- 평범한 `<difit-command> <target> …`를 **하니스 백그라운드(run_in_background)로 실행**한다.
- difit 자체 `--background` 플래그는 **쓰지 않는다** — 하니스 백그라운드 잡으로 띄워야 서버가 턴을 넘어 유지된다.
- **`--keep-alive`는 붙이지 않는다.** 이게 없어야 사용자가 브라우저를 닫을 때 difit가 스스로 종료된다(client disconnect → shutdown). 이 **잡 완료가 "리뷰 끝" 신호**이자 회수 트리거다 — 사용자의 완료 메시지를 기다리지 않는다.

## 코멘트 영속과 세션 격리 — `--clean`

difit는 리뷰 코멘트를 **브라우저 localStorage에 영속**하며, 이 저장소는 **origin(`localhost:<port>`) 단위**다. 클라이언트는 로드 시 그 origin에 쌓인 이전 코멘트를 모두 복원하므로, 같은 포트로 difit를 다시 띄우면 **이전 세션·다른 PR의 코멘트가 이번 diff에 섞여** 나타난다(종료 시 stdout 덤프에도 그대로 포함된다).

- 매 리뷰를 깨끗한 상태로 시작하려면 **`--clean`을 붙인다.** 서버가 `/api/diff` 응답에 `clearComments:true`를 실어 보내고, 클라이언트가 로드 시 `clearAllComments()`로 localStorage를 비운다.
- `--clean` 없이 세션을 열면 leak이 발생한다. **프리로드·회수를 쓰는 스킬은 `--clean`을 기본으로 한다.**
- `--clean`은 해당 origin의 **모든** 저장 코멘트를 지운다(현재 diff/PR 한정 아님). 의도적으로 이전 코멘트를 이어서 볼 때만 생략한다.

## 절대 kill하지 않는다

difit에 `kill`·`pkill`·`lsof … | xargs kill`을 **절대 실행하지 않는다.** difit는 브라우저를 자식 프로세스로 띄우므로, difit(또는 그 프로세스 그룹)를 kill하면 사용자 브라우저가 함께 종료될 수 있다. difit는 브라우저가 닫히면 스스로 깨끗이 종료된다 — 항상 자가 종료하게 둔다.

## 회수 — 종료 시 stdout 덤프

difit는 종료 직전 세션의 모든 코멘트를 stdout에 덤프한다. 하니스 백그라운드 잡이 완료되면 그 출력을 읽어 회수한다. 별도 `difit comment get` 호출이나 서버 kill이 필요 없다.

```
📝 Comments from review session:
==================================================
<file>:L<line>
<첫 메시지 본문>
Reply <N> (<author>)
<답글 본문>
==================================================
Total comments: <N>
```

- thread는 `==================================================` 구분선 사이에 `<file>:L<line>`(범위면 `L<start>-L<end>`) + 첫 메시지 본문으로 나온다.
- 사용자 답글은 그 아래 `Reply <N> (<author>)` 라벨 + 본문으로 붙는다.
- 마지막 줄은 `Total comments: <N>`. 블록이 없거나 `Total comments: 0`이면 남긴 코멘트 없음이다.

## 시크릿 금지

토큰·비밀번호·API 키·개인키·PII 등 자격증명류를 `--comment` 본문이나 명령줄 인자에 **절대 복사하지 않는다.**
