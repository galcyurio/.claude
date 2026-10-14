---
name: approve-pr
effort: low
description: PR을 `LGTM 👍🙆‍♀️🙏💻` 메시지와 함께 Approve하는 스킬. 사용자가 'approve-pr', 'PR 승인해', 'PR approve해', '어프루브해줘', 'LGTM 남겨줘' 등을 PR 링크·번호와 함께 요청할 때 이 스킬을 사용한다. PR 리뷰 요청에는 `review-by-agents`를 사용한다.
argument-hint: "[PR URL | PR 번호]"
allowed-tools: Bash
---

## 역할

지정한 PR을 고정 메시지 `LGTM 👍🙆‍♀️🙏💻`와 함께 Approve한다. 이 스킬을 호출한 것 자체가 Approve 승인이므로 추가 확인 없이 실행한다.

사용자 입력: $ARGUMENTS

## 대상 PR

- PR URL이나 번호가 있으면 그대로 쓴다.
- 없으면 현재 브랜치의 PR을 대상으로 한다(`gh pr view`가 찾는 PR). 찾지 못하면 실행하지 않고 PR을 지정해 달라고 보고한다.

## 실행

```bash
gh pr review <PR> --approve --body "LGTM 👍🙆‍♀️🙏💻"
```

인자가 없을 때는 `<PR>`을 생략한다. 실행 뒤 `gh pr view <PR> --json url,title -q '.title + "\n" + .url'`로 승인한 PR의 제목과 URL을 보고한다.

## 실패 시

본인이 작성한 PR이라 Approve할 수 없다는 등 `gh`가 거부하면, 다시 시도하지 않고 오류 메시지를 그대로 보고한다.
