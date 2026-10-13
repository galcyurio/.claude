---
name: apply-ai-review-loop
description: PR 하나에 달리는 AI 리뷰 봇(`tester-prnd`) 코멘트를 사용자 대신 반복해서 반영해야 할 때 사용한다. 사용자가 'apply-ai-review-loop', 'AI 리뷰 자동 반영', '봇 리뷰 알아서 반영해', 'tester-prnd 코멘트 계속 반영해', 'AI 리뷰 루프 돌려' 등을 PR 링크와 함께 요청하면 이 스킬을 사용한다. 사람 리뷰어 코멘트를 골라 반영하는 요청에는 `apply-pr-feedback`, 직접 준 피드백을 기존 커밋에 흡수하는 요청에는 `rebase-fix`를 사용한다.
argument-hint: <PR 링크>
---

# apply-ai-review-loop

PR 하나를 지정받아 "감시 → 반영 판단 → 커밋 → autosquash → force push → 재리뷰 대기"를 종료 조건에 닿을 때까지 반복한다. 코멘트 반영은 `rebase-fix` 절차를 따르고, 이 스킬은 루프·판단·push 안전장치·보고만 더한다.

## push 승인 범위 (`rules/git.md` 예외)

사용자가 이 스킬을 호출한 것은 **그 PR의 head 브랜치에, 이 루프가 끝날 때까지** 반복 force push 하는 것을 승인한 것으로 본다. 반영하지 않는 지적에 사유를 남기는 스레드 답글(2단계)도 같은 승인에 들어간다. 다른 브랜치·서브모듈 push, 그 밖의 PR 답글, resolve, re-request review는 들어가지 않는다. 루프가 끝나면(종료 조건·중단·보고 후 대기) 승인도 끝난다. 다시 push하려면 스킬을 다시 호출받아야 한다.

이 승인은 훅이 집행한다. `hooks/approve-push.sh`가 `/apply-ai-review-loop` 호출을 보면 세션 마커 `~/.claude/cache/push-gate/loop-<session_id>`에 호출 시점 브랜치를 적고, `hooks/guard-push.sh`는 그 브랜치로 SHA를 지정한 `git push --force-with-lease=<head>:<sha> origin HEAD:<head>`만 통과시킨다. 그래서 head 브랜치에 체크아웃된 상태에서 호출받아야 하고, push는 5단계 명령 형태를 그대로 쓴다.

## 0. 시작 점검

```bash
gh pr view <PR> --json number,headRefName,baseRefName,headRefOid,isCrossRepository,url
git status --porcelain                  # 비어 있어야 한다
git rev-parse --abbrev-ref HEAD         # headRefName 과 같아야 한다
git fetch origin <head> <base>
git rev-parse HEAD                      # headRefOid 와 같아야 한다
```

- 어긋나면 시작하지 않고 보고한다. 로컬과 원격이 다르면 어느 쪽이 맞는지 추측하지 않는다.
- `LEASE=<headRefOid>`, `BASE=$(git merge-base HEAD origin/<base>)`를 기억한다. `rebase-fix`의 base 자동 탐지 대신 이 BASE를 쓴다.
- 이슈 ID는 브랜치명의 `[A-Z]+-[0-9]+`에서 얻는다. 없으면 커밋 메시지에 넣지 않는다.
- 상태 디렉터리 `~/.claude/state/apply-ai-review-loop/<owner>_<repo>_<n>/`에 `ledger.tsv`(스레드 URL, 위치, 판정, 대상 커밋 제목, 사유)를 둔다. 이미 있으면 재개한 것이므로 이어서 쓴다.

## 1. 감시

처음 시작할 때는 지금 미해결인 `tester-prnd` 스레드를 2~5단계로 먼저 처리한다. 그다음 감시를 띄운다.

```
Monitor(command: "bash ~/.claude/skills/apply-ai-review-loop/watch-pr.sh <owner/repo> <n>",
        description: "<repo>#<n> CI·새 리뷰 스레드", timeout_ms: 1800000)
ScheduleWakeup(delaySeconds: 1800, prompt: "/apply-ai-review-loop <PR 링크>", reason: "Monitor 가 멈췄을 때를 대비한 예비 점검")
```

스크립트는 처음 띄울 때 그 시점의 미해결 스레드를 기준값(`seen`)으로 저장하고, 그 뒤에 생긴 스레드만 내보낸다. 이 스킬은 스레드를 resolve하지 않으므로 처리한 스레드는 계속 미해결로 남는다. 기준값 파일이 이를 걸러 주니, 감시를 다시 띄울 때 `seen`을 지우지 않는다.

| 이벤트 | 처리 |
|---|---|
| `THREAD tester-prnd …` | 2단계로 간다. 같은 head에 대한 스레드가 이어서 올 수 있으니 `CI <head> …`가 올 때까지 모아서 한 번에 처리한다 |
| `THREAD <다른 사람> …` | 반영하지 않는다. ledger에 `사람`으로 적고 최종 보고에 넣는다 |
| `CI <sha> fail` | 6단계로 간다 |
| `CI <sha> pass` | 모아 둔 스레드가 있으면 처리하고, 없으면 조용한 점검으로 센다 |
| `ERROR …` | 사용자에게 보고하고 멈춘다 |
| Monitor 만료·ScheduleWakeup 기상 | 점검 1회. 같은 명령으로 Monitor를 다시 띄운다 |

## 2. 반영 판단

코멘트마다 지적이 사실인지 직접 확인하고, 사실이라도 고칠 필요가 있는지 따진다. 해당 줄의 현재 코드, 그 코드가 호출하는 함수·스킬, 참조한 문서를 읽고 판정한다. 리뷰를 무작정 반영하지 않는다.

| 판정 | 기준 | 처리 |
|---|---|---|
| 반영 | 지적이 현재 코드와 맞고, 고칠 필요가 있으며, 고치는 것이 PR 범위 안이다 | 3단계 |
| 부분 반영 | 문제는 맞지만 봇이 제시한 근거나 해법 일부를 확인할 수 없다 | 확인된 부분만 고친다. 확인되지 않은 내용을 단정하는 코드·문구를 넣지 않는다. 고치지 않은 부분은 스레드에 답글로 사유를 남긴다 |
| 미반영 | 이미 처리돼 있다 · 사실이 아니다 · 근거를 확인할 수 없다 · PR 범위 밖이다 · 맞는 지적이지만 고칠 필요가 없다(드문 경우를 위해 복잡도만 늘린다, 효과가 작다, 취향 차이다) | 고치지 않는다. 스레드에 답글로 사유를 남기고 ledger에 적는다 |

같은 지점에 지적이 거듭 오면, 코드나 문서가 실제로 그렇게 읽힌다는 뜻이다. 지적을 건너뛰지 않고 둘 중 하나로 끝낸다.

- **고친다**: 그 지점이 오해 없이 읽히도록 명확하게 고친다. 지적된 한 줄만 덧대지 말고, 같은 질문이 다시 나오지 않도록 지적들이 공통으로 가리키는 원인을 고친다.
- **고치지 않는다**: 스레드에 답글로 왜 그대로 두는지와 근거(코드·문서 위치)를 남긴다. 답글이 없으면 봇과 리뷰어는 같은 지적을 다시 한다.

답글은 스레드 안에 남긴다(`gh api repos/<owner>/<repo>/pulls/<n>/comments/<id>/replies -f body=…`). 반영한 지적에는 답글을 달지 않는다.

## 3. 커밋

`rebase-fix`의 3~6단계를 따른다. 단 아래 세 가지는 이 스킬이 대신 정한다.

- 분류 결과를 사용자에게 확인받지 않는다. fixup과 새 커밋 판정이 애매하면 **새 커밋**으로 만든다.
- 새 커밋 메시지는 `~/.claude/references/commit-rules.md`를 Read한 뒤 쓴다. 커밋 훅이 명령 문자열에서 메시지를 직접 읽으므로, 메시지와 trailer를 셸 변수에 담지 말고 heredoc에 그대로 적는다.

  ```bash
  git commit -F - <<'EOF'
  HDA-123 fix: 모델명이 길면 말줄임표로 줄인다

  Co-Authored-By: ...
  EOF
  ```

- 커밋 대상 파일만 `git add`한다. ledger에는 SHA가 아니라 대상 커밋 제목을 적는다. autosquash가 SHA를 바꾸기 때문이다.

## 4. autosquash와 검증

```bash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash $BASE
git diff --stat ORIG_HEAD HEAD                                   # 출력이 없어야 한다
git log -p $BASE..HEAD | grep -nE '^\+(<{7}|={7}|>{7})( |$)'     # 출력이 없어야 한다
```

- 충돌이 나면 `git rebase --abort`로 되돌리고 **멈춘다**. 충돌이 단순해 보여도 이 루프에서 해결하지 않는다. 충돌 파일과 충돌한 두 커밋을 보고한다.
- 두 검사 중 하나라도 출력이 있으면 push하지 않고 멈춘다.

## 5. push

```bash
git fetch origin <head>
git rev-parse origin/<head>             # LEASE 와 같아야 한다
git push --force-with-lease=<head>:<LEASE 40자 SHA> origin HEAD:<head>
git rev-parse HEAD                      # 다음 push의 LEASE로 기억한다
```

- 원격이 LEASE와 다르면 다른 사람이 push한 것이다. push하지 않고, 그 커밋을 rebase해 넣지도 않고 멈춘다.
- `--force-with-lease`를 SHA 없이 쓰지 않는다. fetch한 뒤에는 SHA 없는 lease가 남의 커밋을 덮어쓴다. SHA는 `$LEASE`·`$(git rev-parse …)` 같은 치환 없이 40자 값을 그대로 적는다. 훅은 명령 문자열에서 `--force-with-lease=<head>:<SHA>` 형태를 확인하므로 치환을 쓰면 막힌다.
- push 뒤에는 떠 있는 Monitor의 다음 이벤트를 기다린다. Monitor를 새로 띄우는 것은 만료됐을 때뿐이다. 두 개가 함께 돌면 같은 이벤트가 두 번 온다.

## 6. CI 실패

`gh pr checks <n> -R <owner/repo>`로 실패한 잡을 찾고 `gh run view <run-id> --log-failed`로 원인을 읽는다.

- 타임아웃, `The runner has received a shutdown signal`, 러너 할당 실패처럼 코드와 무관한 실패는 `gh run rerun <run-id> --failed`로 재실행한다. 같은 잡이 재실행 뒤에도 실패하면 멈추고 보고한다.
- 코드 때문에 생긴 실패는 2~5단계와 같은 방식으로 고쳐서 반영한다.

## 7. 종료

아래 중 하나에 닿으면 Monitor를 TaskStop하고 `ScheduleWakeup(stop: true)`로 예비 점검을 끈 뒤, push 승인 마커를 지우고 보고한다.

```bash
grep -lx '<head>' ~/.claude/cache/push-gate/loop-* 2>/dev/null | xargs rm -f
```

- 현재 head의 CI가 pass이고 새 스레드가 없는 점검이 **연속 2회**다.
- 충돌, 검증 실패, 원격 변경, 재실행 뒤 같은 실패, `ERROR` 이벤트.

종료 조건에 닿으면 그 사이클에 남은 반영·재실행·push도 하지 않는다. 남은 항목은 보고에 "하지 않은 일"로 적는다.

보고에는 멈춘 이유와 ledger를 바탕으로 한 표를 넣는다. 커밋은 최종 `git log $BASE..HEAD`에서 제목으로 찾은 SHA로 링크하고, 링크 텍스트에서 이슈 prefix를 뺀다.

```markdown
| 코멘트 | 판정 | 커밋 · 사유 |
|---|---|---|
| [SearchScreen.kt:88 말줄임 누락](스레드 URL) | 반영 | [feat: 검색 결과 목록을 보여준다](https://github.com/<owner>/<repo>/commit/<sha>) |
| [SearchViewModel.kt:42 collectLatest](스레드 URL) | 미반영 | 이미 collectLatest 를 쓰고 있다 |
```

## 하지 않는 것

| 하고 싶어지는 이유 | 실제 |
|---|---|
| "반영한 지적에도 답글이나 resolve로 처리 상태를 남기면 편하다" | 답글은 반영하지 않는 지적의 사유에만 단다. resolve와 반영 완료 답글은 사용자가 한다 |
| "같은 지점에 또 지적이 왔으니 수렴하지 않는 것이다. 건너뛴다" | 거듭 지적되는 데는 이유가 있다. 원인을 명확하게 고치거나, 그대로 둘 근거를 답글로 남긴다 |
| "충돌이 인접한 두 줄뿐이라 합치면 된다" | 자동 해결은 다른 커밋 의도를 섞는다. abort 후 멈춘다 |
| "fetch했으니 `--force-with-lease`만으로 안전하다" | fetch가 lease 기준을 갱신해 버린다. SHA를 명시한다 |
| "동료 커밋 위로 rebase하고 push하면 된다" | 원격이 바뀌면 멈춘다. 합치는 판단은 사용자가 한다 |
| "봇이 말했으니 고친다" | 코드와 맞는지 확인한 지적만 반영한다 |
