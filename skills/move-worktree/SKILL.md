---
name: move-worktree
effort: low
description: 진행 중인 작업 브랜치와 현재 claude 세션을 같은 저장소의 다른 worktree 자리로 옮겨야 할 때 사용한다. 사용자가 'move-worktree', 'N번 worktree로 옮겨', '작업 자리 옮겨', '이 작업 N번 자리로', '다른 worktree에서 이어서 해' 등을 요청하면 이 스킬을 사용한다. 이슈를 새로 착수하는 요청에는 `start-worktree`, 작업을 끝내고 자리를 반납하는 요청에는 `release-worktree`를 사용한다.
argument-hint: "<N | 대상 자리 경로> [--discard-target]"
allowed-tools: Bash, AskUserQuestion
---

## 역할

이미 커밋이 쌓인 작업 브랜치를 다른 유휴 자리로 옮긴다. 원래 자리는 짝이 맞는 base 사본으로 되돌리고, 대상 자리에 새 탭을 띄워 세션을 이어 붙인 뒤 원래 탭을 닫는다. 새 탭의 세션은 상태만 보고하고 다음 지시를 기다린다. 판정과 실행은 전부 `move-worktree.sh`가 맡는다.

사용자 입력: $ARGUMENTS

## 절차

1. **대상 자리 경로를 정한다.**
   - 경로를 받았으면 그대로 쓴다.
   - 번호 N을 받았으면 현재 자리 이름에서 끝의 `-<숫자>`를 뗀 상위 자리 이름 뒤에 `-N`을 붙인다. 현재 자리가 상위 자리 자체면 그 이름에 `-N`을 붙인다. 예: `heydealer-android-HDA-23574` 또는 `heydealer-android-HDA-23574-2`에서 "3번" → `heydealer-android-HDA-23574-3`.
2. **스크립트를 호출한다.**

```
bash ~/.claude/skills/move-worktree/move-worktree.sh <대상 자리 경로> [--discard-target]
```

3. **결과를 처리한다.**

| 종료 | 처리 |
|---|---|
| 성공 | 탭이 닫힌다. 호출 이후에는 어떤 도구도 부르지 않고 어떤 메시지도 쓰지 않는다 |
| 코드 3 | 대상 자리에 미커밋 변경이 있다. 출력된 변경 목록을 넣어 `AskUserQuestion`으로 묻는다: "변경 유지(이동 취소)", "변경 버리고 이동", "다른 자리 지정" |
| 그 외 | 탭이 닫히지 않았다. 출력된 오류를 사용자에게 그대로 전달한다 |

"변경 버리고 이동"을 고르면 같은 명령에 `--discard-target`을 붙여 다시 실행한다.

## 주의

- `--discard-target`은 사용자가 그 뜻으로 답했을 때만 붙인다. 되돌릴 수 없다.
- 스크립트를 우회해 `git switch`·`orca` 명령을 직접 실행하지 않는다. 원래 자리가 되돌아갈 base 사본의 짝 규칙과 세션 이사 순서가 스크립트 안에 있다.
- 대상 자리를 새로 만들지 않는다. 자리가 없다는 오류가 나면 `start-worktree`를 안내한다.
