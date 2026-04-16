---
name: prnd-library-sync
description: 여러 프로젝트의 prnd-library를 지정한 브랜치로 체크아웃하고 명령어를 실행한다
argument-hint: "[projects] [branch] [command]"
disable-model-invocation: true
allowed-tools: Bash
---

## 역할

프로젝트 목록, 브랜치 이름, 실행할 명령어를 전달받아 shell script를 호출한다.

사용자 입력: $ARGUMENTS

## 입력 형식

사용자는 다음 세 가지를 반드시 제공해야 한다:

- **projects**: 프로젝트 이름 목록 (예: `heydealer-android`, `prnd-web`)
- **branch**: 각 `prnd-library`에서 체크아웃할 git 브랜치 이름
- **command**: 체크아웃 후 각 `prnd-library` 안에서 실행할 쉘 명령어

## 경로 탐색 (AI가 수행)

script를 호출하기 전에, 각 프로젝트 이름에 대해 절대경로를 찾아야 한다:

1. `find ~ -maxdepth 4 -type d -name "<프로젝트 이름>" 2>/dev/null` 으로 후보 경로를 검색한다
2. 후보 중 `prnd-library` 서브디렉토리가 존재하는 경로를 선택한다
3. 매칭되는 경로가 없으면 사용자에게 알리고 해당 프로젝트는 건너뛴다
4. 매칭되는 경로가 여럿이면 사용자에게 어느 경로인지 확인한다

## 실행 방법

절대경로를 확보한 뒤 아래 명령어 한 줄을 Bash 도구로 실행한다:

```
${CLAUDE_SKILL_DIR}/prnd-library-sync.sh "<branch>" "<command>" /절대경로1 /절대경로2 ...
```
