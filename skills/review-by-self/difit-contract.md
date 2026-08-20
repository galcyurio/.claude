# difit 공유 계약

`review-by-self` · `review-by-agents`가 공통으로 따르는 difit 뷰어 실행·수명·회수 계약이다. 각 스킬은 difit를 다루는 단계에서 이 파일을 Read해 아래를 따르고, 스킬 고유 부분(`--comment` 프리로드·게이트·회수 해석)은 각 SKILL.md가 정의한다.

## `<difit-command>` 선택

- `command -v difit` 성공 → `difit`
- 실패 → `npx difit`
- 샌드박스에서 네트워크 권한이 없어 `npx difit` 실행이 막히면, 권한 상승을 요청하고 사용자 승인 후 실행한다.

## 실행 — `launch-difit.py` (새 세션 detach)

difit은 **런처 스크립트로 띄운다.** 평범한 포그라운드 Bash 호출로 실행하며, 하니스 백그라운드(`run_in_background`)를 쓰지 않는다.

```bash
python3 ~/.claude/skills/review-by-self/launch-difit.py \
  --log <스크래치패드>/difit.log [--stdin <스크래치패드>/pr.patch] -- \
  <difit-command> <difit 인자…>
```

- 런처는 성공 시 stdout에 **JSON 한 줄** `{"port": N, "url": "http://localhost:N", "pid": P}`을 출력한다. **URL·pid를 이 JSON에서 확정한다** — 배너 대기와 HTTP 200 확인까지 런처가 이미 끝냈으므로 따로 폴링하지 않는다. `pid`는 "회수 후 종료"에 쓴다.
- 희망 포트는 difit 인자로 `--port <N>`을 준다. 점유되면 difit이 다음 포트로 옮기므로 **JSON의 `port`가 사실**이다(실측: 5010 점유 → `{"port": 5012}`).
- 기동에 실패하면(잘못된 target 등) 런처가 로그 tail을 stderr에 남기고 **exit 1**로 끝난다. 이때는 difit 없이 진행한다.
- `--stdin`은 **diff를 stdin으로 넣는 모드(PR 등)에만** 준다. detach된 프로세스에 파이프를 물릴 수 없으므로 diff를 먼저 파일로 받고 그 경로를 넘긴다. Git revision 모드에서는 생략한다.
- **`--no-open`을 붙인다.** difit이 브라우저를 직접 열지 않고 **사용자가 URL을 열게** 한다. 이렇게 하면 브라우저가 difit의 자식 프로세스가 아니므로, 회수 후 서버를 안전하게 종료할 수 있다(아래 "회수 후 종료" 참고).
- **`--keep-alive`를 붙인다.** 사용자가 브라우저를 닫아도 difit이 자가 종료하지 않고 서버·코멘트를 메모리에 유지한다. 회수 트리거는 브라우저 닫힘이 아니라 **사용자의 명시적 종료 신호**다(아래 "회수" 참고).

### 왜 런처인가 — 직접 띄우면 안 되는 세 방식

세 방식 모두 실측으로 탈락했다. 런처는 `start_new_session=True`로 **새 세션**을 만들면서 stdin을 그대로 물려주어 세 결함을 동시에 피한다.

| 방식 | 결함 |
|---|---|
| `run_in_background: true` | `--keep-alive`와 합쳐지면 **끝나지 않는 하니스 태스크**가 된다. 잡이 exit하는 순간은 회수 후 kill할 때뿐이라, 리뷰가 준비된 뒤에도 `/tasks`·Tasks 패인에 계속 `running`으로 남아 **사용자가 완료를 인지할 수 없다.** |
| `nohup … &` | `PPID=1`로 재부모화되지만 **PGID가 호출 셸 그룹에 그대로 남아**(실측: 셸 pgid 19649 = difit pgid) 턴이 끝날 때 프로세스 그룹째 정리된다. 같은 턴 안에서는 살아 있어 멀쩡해 보이지만 **다음 턴에는 죽어 있다**(실측: 다음 턴 HTTP 000). |
| difit `--background` | 자식을 `stdio: ['ignore', …]`로 spawn하고 부모가 stdin을 읽기 전에 넘겨 **stdin diff가 조용히 무시되고 `HEAD^..HEAD`로 대체된다**(실측: 6파일 stdin diff를 파이프했으나 2파일 리비전 diff를 렌더). PR 모드가 **엉뚱한 diff를 리뷰하게 되므로 치명적**이다. 포트 점유 시 JSON 대신 busy 한 줄만 출력해 URL·pid도 확정할 수 없다. |

## 코멘트 영속과 세션 격리 — `--clean`

difit는 리뷰 코멘트를 **브라우저 localStorage에 영속**하며, 이 저장소는 **origin(`localhost:<port>`) 단위**다. 클라이언트는 로드 시 그 origin에 쌓인 이전 코멘트를 모두 복원하므로, 같은 포트로 difit를 다시 띄우면 **이전 세션·다른 PR의 코멘트가 이번 diff에 섞여** 나타난다(회수 시에도 그대로 포함된다).

- 매 리뷰를 깨끗한 상태로 시작하려면 **`--clean`을 붙인다.** 서버가 `/api/diff` 응답에 `clearComments:true`를 실어 보내고, 클라이언트가 로드 시 `clearAllComments()`로 localStorage를 비운다.
- `--clean` 없이 세션을 열면 leak이 발생한다. **프리로드·회수를 쓰는 스킬은 `--clean`을 기본으로 한다.**
- `--clean`은 해당 origin의 **모든** 저장 코멘트를 지운다(현재 diff/PR 한정 아님). 의도적으로 이전 코멘트를 이어서 볼 때만 생략한다.

## 회수 — 사용자 종료 신호 + `comment get`

difit는 코멘트를 **서버 메모리에 보관**한다(브라우저가 코멘트를 실시간으로 서버에 저장하고, `--comment` 프리로드도 세션에 담긴다). `--keep-alive`로 띄웠으므로 브라우저를 닫아도 서버·코멘트가 남아, **실행 중 서버에서** 코멘트를 조회할 수 있다.

- 회수 트리거는 **사용자의 명시적 종료 신호**다 — 사용자가 다음 메시지에서 리뷰가 끝났다고 알린다. detach 실행이므로 **기다릴 하니스 잡이 아예 없고, 브라우저 닫힘을 폴링하지도 않는다.** 런치 후에는 사용자에게 "브라우저를 열어 리뷰하고, 끝나면 알려달라"고 안내한 뒤 턴을 종료한다.
- 신호를 받으면 `difit comment get --port <N> --format text`로 실행 중 서버에서 코멘트를 회수한다. 출력은 아래 포맷이다(difit 내부의 동일한 `formatCommentsOutput` 결과).

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

- thread는 `==================================================` 구분선 사이에 `<file>:L<line>`(범위면 `L<start>-L<end>`) + 첫 메시지 본문으로 나온다. thread가 여러 개면 thread 사이는 짧은 `=====` 구분선으로 나뉜다.
- 사용자 답글은 그 아래 `Reply <N> (<author>)` 라벨 + 본문으로 붙는다.
- 마지막 줄은 `Total comments: <N>`. 블록이 없거나 `Total comments: 0`이면 남긴 코멘트 없음이다.
- 구조화 파싱이 필요하면 `--format json`으로 `{version, threads:[…]}` 형태를 받는다.

## 회수 후 종료

`--no-open`으로 띄웠으므로 브라우저는 difit의 자식 프로세스가 아니다. 따라서 코멘트를 회수한 뒤 **우리가 이번에 띄운 그 서버 프로세스를 종료**해 정리한다. detach된 프로세스는 **하니스가 세션 종료 시 정리해 주지 않으므로**, 이 단계를 건너뛰면 서버가 그대로 남는다.

- **반드시 `comment get`으로 회수를 먼저 끝낸 뒤 종료한다.** 종료가 먼저면 코멘트를 잃는다.
- 종료는 런처 JSON의 `pid`로 한다: `kill <pid>`. `pid`를 잃었으면 **우리가 쓴 그 포트에 한정해** 찾는다: `kill $(lsof -ti tcp:<우리 포트>)`. 종료할 하니스 잡이 없으므로 잡 종료로는 정리되지 않는다.
- `pkill difit`처럼 포트를 특정하지 않고 무관한 difit 서버(다른 세션·다른 리뷰)까지 죽이는 명령은 **쓰지 않는다.**

## 시크릿 금지

토큰·비밀번호·API 키·개인키·PII 등 자격증명류를 `--comment` 본문이나 명령줄 인자에 **절대 복사하지 않는다.**
