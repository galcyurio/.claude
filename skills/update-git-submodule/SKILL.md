---
name: update-git-submodule
description: Use when 현재 프로젝트의 prnd-library 서브모듈을 특정 release/feature 브랜치로 전환하고 원격 최신 커밋으로 업데이트한 뒤 커밋까지 한 번에 처리하고 싶을 때 사용한다. 사용자가 'prnd-library 업데이트', 'prnd-library 최신화', '라이브러리 업데이트', '라이브러리 최신화', 'prnd-library를 feature/release 브랜치로 변경', '서브모듈 업데이트' 등을 요청할 때 사용한다.
argument-hint: "[branch]"
allowed-tools: Bash
---

## 역할

현재 프로젝트 루트의 `prnd-library` 서브모듈을 지정한 브랜치로 전환하고, 원격 최신 커밋으로 업데이트한 뒤, `.gitmodules`와 서브모듈 포인터를 한 번에 커밋한다.

사용자 입력: $ARGUMENTS

## 입력

- **branch** (필수): `prnd-library`에서 추적할 git 브랜치. 이름에 `release` 또는 `feature`가 포함되어야 한다.
  - `release` 포함 → 커밋 메시지 `<JiraId> feat: 라이브러리를 최신화한다`
  - `feature` 포함 → 커밋 메시지 `<JiraId> feat: 라이브러리를 feature 브랜치로 변경한다`

branch가 주어지지 않았으면 어떤 브랜치로 전환할지 사용자에게 먼저 물어본 뒤 진행한다.

## 사전 조건

- **현재 작업 디렉토리가 `prnd-library` 서브모듈을 가진 프로젝트 루트**여야 한다. 아니면 스크립트가 오류를 내고 중단한다.
- 커밋 메시지의 Jira ID는 현재 체크아웃된 브랜치 이름에서 `HDA-숫자`를 추출한다. 없으면 ID 없이 `feat: ...`로 커밋한다.

## 실행

프로젝트 루트에서 아래 한 줄을 Bash 도구로 실행한다:

```
${CLAUDE_SKILL_DIR}/update-git-submodule.sh "<branch>"
```

스크립트가 수행하는 일:

1. 커밋 메시지 결정 (release/feature 분기 + 현재 브랜치의 Jira ID 추출)
2. `prnd-library` 원격에 해당 브랜치 존재 확인 (`origin/<branch>`)
3. `git submodule set-branch --branch <branch> prnd-library` + `git submodule update --remote prnd-library`
4. `git commit .gitmodules prnd-library -m "<message>"`

## 주의

- 이미 최신이라 변경할 게 없으면 커밋 단계에서 실패한다(정상 동작). 그대로 사용자에게 알린다.
