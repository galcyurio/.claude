# Orca 워크스페이스 카드 상태

Orca가 관리하는 세션에서는 카드 상태를 실제 진행 상황과 일치시킨다. 전이는 훅이 자동으로 수행하므로 내가 `orca worktree set`을 직접 호출하지 않는다.

## 전이 규칙

보드는 Idle, In progress, My turn, Standby, In review 다섯 열이다.

- Idle은 지금 볼 필요가 없는 카드로, 아직 시작하지 않은 세션과 끝난 세션을 함께 담는다. 기존 Done 열의 id인 `completed`를 그대로 쓰고 이름만 Idle로 바꿨다.
- My turn은 사용자가 볼 차례인 카드다. 턴이 끝나 결과를 확인할 때와 권한 승인·질문에 답해야 할 때를 함께 담는다. 보드에서 열을 추가할 때 만들어진 id `status-4`를 쓴다.
- Standby는 확인을 마치고 세워 둔 카드다. 숲을 보는 오케스트레이션 세션처럼 턴이 끝나 확인만 하고 그대로 두는 세션을 사용자가 My turn에서 직접 옮겨 둔다. 훅은 이 열로 옮기지 않는다. 한 번 Standby에 둔 카드는 In review처럼 훅이 다른 열로 옮기지 않고, 볼 차례가 오면 사이드바에 읽지 않음 표시만 붙인다. Standby에서 빼는 것도 사용자가 직접 한다. id는 `status-5`다.

| 시점 | 훅 이벤트 | status id | 보드 컬럼 |
|---|---|---|---|
| 세션이 시작된 순간 | `SessionStart` | `completed` | Idle |
| 사용자가 프롬프트를 보낸 순간 | `UserPromptSubmit` | `in-progress` | In progress |
| 권한 승인을 요청한 순간 | `PermissionRequest` | `status-4` | My turn |
| 질문을 띄우기 직전 | `PreToolUse`(`AskUserQuestion`) | `status-4` | My turn |
| 권한·질문에 답해 도구가 실행된 직후 | `PostToolUse` | `in-progress` | In progress |
| 턴이 끝난 순간 | `Stop`, `StopFailure` | `status-4` | My turn |
| `gh pr create`가 성공한 직후 | `PostToolUse` | `in-review` | In review |
| 세션이 끝난 순간 | `SessionEnd` | `completed` | Idle |
| 탭을 그대로 닫아 세션이 사라진 순간 | `SessionStart`에서 띄운 지킴이 | `completed` | Idle |

- 카드가 이미 `in-review`나 Standby(`status-5`)면 스크립트가 다른 상태로 옮기지 않는다. PR이 리뷰를 기다리는 동안이나 사용자가 세워 둔 동안 다른 열로 옮겨지지 않게 하려는 것이다.
- `PostToolUse`는 도구 호출마다 불리므로 스크립트가 `resume` 모드로 받아, 자신이 마지막으로 My turn으로 넘긴 카드만 In progress로 되돌린다. 사용자가 카드를 직접 옮겼다면 되돌리지 않는다.
- `/clear`로 세션이 끊기는 경우도 `SessionEnd`에 해당하므로 `completed`로 보낸다. 대화를 이어가면 다음 프롬프트에서 다시 `in-progress`로 올라간다.
- 세션을 새로 열면 카드는 `completed`(Idle)로 돌아가고, 첫 프롬프트에서 다시 `in-progress`로 올라간다. `release-worktree` 스킬도 자리를 반납할 때 카드를 `completed`로 넘긴다.

## 훅이 닿지 않는 경우

탭을 그대로 닫으면 `SessionEnd`가 오지 않으므로, `~/.claude/hooks/orca-workspace-watchdog.sh`가 `SessionStart`에서 떠 이 세션의 claude 프로세스를 지켜본다. 그 프로세스가 사라지면 지킴이가 대신 `completed`로 넘기며, 종료 신호를 받지 않고 폴링하므로 강제 종료에도 동작한다(반영 지연은 최대 5초).

전이를 수행하는 스크립트는 `~/.claude/hooks/orca-workspace-status.sh`이며, `ORCA_WORKTREE_ID`가 없거나 `orca` 명령을 찾지 못하면 조용히 종료한다. 어떤 이벤트가 스크립트를 깨웠는지는 `$TMPDIR/orca-workspace-status.log`에 남으므로, 카드가 엉뚱한 상태로 넘어가면 이 기록부터 확인한다.

- 사용자가 카드를 직접 옮겼더라도 그 상태를 존중한다. 다음 프롬프트에서 훅이 `in-progress`로 올리는 것은 의도된 동작이다.
- 상태 변경은 보고 대상이 아니다. 최종 메시지에 "카드를 X로 바꿨다"고 따로 적지 않는다.
