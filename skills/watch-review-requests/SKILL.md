---
name: watch-review-requests
effort: low
description: 나에게 온 PR 리뷰 요청을 주기적으로 확인하는 모니터를 Orca 탭에 띄우거나 끄는 스킬. 모니터는 새 요청이 오면 같은 Jira 키의 PR 을 레포와 상관없이 묶어 Orca 탭 하나를 열고 `/review-by-agents` 를 보낸다. 사용자가 'watch-review-requests', '리뷰 모니터', '리뷰 요청 감시', '리뷰 요청 모니터링 켜줘', '리뷰 모니터 꺼줘' 등을 요청할 때 이 스킬을 사용해야 한다. PR 하나를 지금 리뷰하는 요청에는 `review-by-agents` 를 사용한다.
argument-hint: "[--interval <초>] | stop"
allowed-tools: Bash
---

## 역할

`watch-review-requests.sh` 를 Orca 탭 하나에 띄운다. 감시와 세션 발송은 전부 스크립트가 맡고, 이 스킬은 띄우기 · 상태 확인 · 끄기만 한다.

- 스크립트는 `PRNDcompany` 의 열린 PR 중 나에게 개인으로 리뷰를 요청한 것을 1분마다 확인한다
- 새 요청은 PR 제목의 Jira 키로 묶는다. 레포가 달라도 Jira 키가 같으면 한 묶음이고, 제목에 Jira 키가 없으면 PR 하나가 한 묶음이다
- Jira 키 묶음은 `~/dev` 에서, Jira 키가 없는 PR 은 `~/dev/{repo}` 원본 클론에서 새 탭(`🔍 리뷰 · {Jira 키 또는 repo#n}`)을 열어 `claude '/review-by-agents {PR 링크 …}'` 를 실행한다. Jira 키 묶음은 나중에 다른 레포의 PR 이 합류해도 같은 대화를 이어 써야 해서 폴더를 `~/dev` 로 고정한다
- 이미 세션이 있는 묶음에 요청이 다시 오거나 같은 Jira 키의 PR 이 나중에 오면 그 세션 탭에 `/review-by-agents` 를 보낸다. 탭이 닫혔으면 같은 claude 대화를 `--resume` 으로 이어 새 탭을 연다
- 상태 파일은 `~/.claude/state/watch-review-requests/` 에 쌓인다. 실행 기록은 그 안의 `watch.log` 에 있다

## 1. 실행 중인지 확인

```bash
pid=$(cat ~/.claude/state/watch-review-requests/lock/pid 2>/dev/null); [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && echo "running $pid"
```

## 2. 인자에 따라 처리

| 인자 | 처리 |
|---|---|
| 없음 · `--interval` | 실행 중이면 띄우지 않고 그 사실만 알린다. 아니면 아래 명령으로 띄운다 |
| `stop` · 끄라는 말 | 실행 중이면 `kill -TERM {pid}`. 아니면 꺼져 있다고 알린다 |

```bash
orca terminal create --title "📡 리뷰 모니터" \
  --command "~/.claude/skills/watch-review-requests/watch-review-requests.sh {--interval 초}" --json
```

- 탭은 현재 Orca 작업 공간에 열리고, 리뷰 세션 탭도 같은 작업 공간에 열린다
- 띄운 뒤 몇 초 기다려 1단계 명령으로 실행 중인지 확인하고, 실패하면 `watch.log` 마지막 줄을 보여준다

## 3. 보고

한두 줄로 끝낸다: 켰는지 · 이미 켜져 있었는지 · 껐는지. 모니터 탭에서 Enter 를 누르면 바로 확인하고 Ctrl+C 로 끈다는 안내는 처음 켤 때만 붙인다.
