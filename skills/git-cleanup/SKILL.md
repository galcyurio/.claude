---
name: git-cleanup
description: 현재 디렉토리의 git 저장소에서 fetch --prune 후 upstream gone 브랜치를 정리한다
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
