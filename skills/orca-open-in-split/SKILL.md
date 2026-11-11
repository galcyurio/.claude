---
name: orca-open-in-split
effort: low
description: 웹 페이지(PR, Jira, 문서 등) 여러 개를 Orca 탭의 분할 창에 띄워야 할 때 사용한다. 사용자가 'orca-open-in-split', 'orca 탭에서 열어줘', '우측에 띄워줘', 'split해서 열어줘', 'PR 옆에 띄워줘', '분할 창으로 열어줘' 등을 요청하면 이 스킬을 사용한다. 기본 브라우저(Chrome·Safari)로 여는 요청에는 `open` 명령을, 페이지를 조작·캡처하는 요청에는 `orca-cli`를 사용한다.
argument-hint: "[--direction right|left|down|up] <url> [<url> ...]"
allowed-tools: Bash
---

# Orca 분할 창에 URL 열기

URL 여러 개를 Orca 내장 브라우저의 분할 창 **하나**에 탭으로 모아 연다. 기본 방향은 오른쪽이다.

## 절차

1. 열 URL을 정한다. 인자에 없으면 직전 대화에서 사용자가 가리킨 링크(방금 만든 PR 등)를 쓴다. 그래도 정할 수 없으면 `AskUserQuestion`으로 묻는다.
2. 방향을 정한다. 사용자가 "왼쪽", "아래" 등을 말했을 때만 `--direction`을 넘긴다.
3. 스크립트를 부른다.

```
bash ~/.claude/skills/orca-open-in-split/open-in-split.sh [--direction <방향>] <url> [<url> ...]
```

4. 스크립트 출력에서 `열림`/`실패` 줄을 세어 보고한다. 탭이 어느 분할 창에 들어갔는지는 CLI로 확인할 수 없으므로, 보고에서 화면 확인을 요청한다.

## 왜 스크립트를 거치는가

- **`--split`은 URL마다 붙여야 한다.** 첫 URL에만 붙이면 나머지 탭은 분할 창이 아니라 원래 그룹에 열린다. 분할 창이 이미 있으면 Orca는 새 창을 만들지 않고 그 창에 탭을 추가하므로, 매번 붙여도 창이 늘어나지 않는다.
- **같은 URL로 이미 열린 탭은 먼저 닫는다.** 남겨 두면 원래 그룹과 분할 창에 같은 페이지가 중복된다.
- `orca tab list`와 `terminal list --include-visual-layouts`는 브라우저 탭이 속한 분할 창을 알려 주지 않는다. 배치를 CLI로 검증하려고 시도하지 않는다.
