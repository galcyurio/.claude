# Orca 워크스페이스 카드 상태

Orca가 관리하는 세션에서는 카드 상태를 실제 진행 상황과 일치시킨다. 전이는 훅이 자동으로 수행하므로 내가 `orca worktree set`을 직접 호출하지 않는다.

## 전이 규칙

| 시점 | 훅 이벤트 | status id | 보드 컬럼 |
|---|---|---|---|
| 사용자가 프롬프트를 보낸 순간 | `UserPromptSubmit` | `in-progress` | In progress |
| `gh pr create`가 성공한 직후 | `PostToolUse` | `in-review` | In review |
| 세션이 끝난 순간 | `SessionEnd` | `completed` | Done |

- 카드가 이미 `in-review`면 스크립트가 다른 상태로 되돌리지 않는다. PR이 리뷰를 기다리는 동안 In progress나 Done으로 내려가지 않게 하려는 것이다.
- `/clear`로 세션이 끊기는 경우도 `SessionEnd`에 해당하므로 `completed`로 보낸다. 대화를 이어가면 다음 프롬프트에서 다시 `in-progress`로 올라간다.
- `todo`로 되돌리는 일은 `clean-merged-session` 스킬의 세션 마감 단계가 담당한다. 그 밖에서 임의로 `todo`로 내리지 않는다.

## 훅이 닿지 않는 경우

전이를 수행하는 스크립트는 `~/.claude/hooks/orca-workspace-status.sh`이며, `ORCA_WORKTREE_ID`가 없거나 `orca` 명령을 찾지 못하면 조용히 종료한다. 어떤 이벤트가 스크립트를 깨웠는지는 `$TMPDIR/orca-workspace-status.log`에 남으므로, 카드가 엉뚱한 상태로 넘어가면 이 기록부터 확인한다.

- 사용자가 카드를 직접 옮겼더라도 그 상태를 존중한다. 다음 프롬프트에서 훅이 `in-progress`로 올리는 것은 의도된 동작이다.
- 상태 변경은 보고 대상이 아니다. 최종 메시지에 "카드를 X로 바꿨다"고 따로 적지 않는다.
