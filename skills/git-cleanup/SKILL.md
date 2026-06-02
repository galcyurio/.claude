---
name: git-cleanup
description: 로컬에 머지·삭제된 브랜치가 쌓여 정리하고 싶을 때 이 스킬을 사용한다. 사용자가 'git-cleanup', '브랜치 정리', 'gone 브랜치 정리', '머지된 브랜치 삭제', '오래된 브랜치 청소' 등을 요청할 때 사용한다. 현재 디렉토리 git 저장소에서 fetch --prune 후 upstream이 사라진(gone) 브랜치를 삭제한다.
disable-model-invocation: true
allowed-tools: Bash
---

## 역할

하나의 git 저장소에 대해 git fetch --prune, upstream gone 브랜치 정리를 수행한다.

## 실행 방법

아래 명령어를 Bash 도구로 실행한다:

```
${CLAUDE_SKILL_DIR}/git-cleanup.sh [저장소경로]
```

- 인자를 생략하면 현재 디렉토리를 대상으로 실행한다.
- 경로를 지정하면 해당 저장소를 대상으로 실행한다.
