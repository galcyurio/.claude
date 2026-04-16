---
name: audit-agents
description: "오케스트레이션 규칙과 에이전트 정의의 일관성을 검사하는 스킬. 사용자가 'audit-agents', '에이전트 감사', '에이전트 점검', '오케스트레이션 리뷰', 'agent audit' 등을 언급할 때 이 스킬을 사용해야 한다."
---

# Audit Agents - 오케스트레이션/에이전트 일관성 검사

orchestration.md와 에이전트 정의 파일 간의 모순, 실행 불가능한 지시, 누락된 흐름을 탐지한다.

## 기본 정보

- **오케스트레이션 규칙**: `~/.claude/rules/orchestration.md`
- **에이전트 정의**: `~/.claude/agents/*.md`
- **팀 설정**: `~/.claude/teams/*/config.json`

## 기술적 제한 (검사 전제)

- 서브에이전트는 Agent 도구를 사용할 수 없다 (중첩 스폰 불가)
- SendMessage로 아직 스폰되지 않은 에이전트를 깨울 수 없다
- 서브에이전트의 "All tools" 표기에 Agent 도구는 포함되지 않는다

---

## 워크플로우

### 1단계: 데이터 수집

1. `~/.claude/rules/orchestration.md` 읽기
2. `~/.claude/agents/*.md` 전체 읽기 (Glob → Read)
3. `~/.claude/teams/*/config.json` 읽기 (존재하는 경우)

### 2단계: 검사 항목 실행

#### 검사 1: 에이전트 테이블 정합성

orchestration.md의 에이전트 테이블과 실제 `~/.claude/agents/` 파일을 비교한다.

- 테이블에 있지만 정의 파일이 없는 에이전트
- 정의 파일이 있지만 테이블에 없는 에이전트
- 모델 불일치 (테이블의 모델 vs frontmatter의 model)
- 역할 설명 불일치

#### 검사 2: 스폰 불가 참조

각 에이전트 정의에서 다른 에이전트를 스폰하는 지시를 탐지한다.

탐지 패턴:
- `{에이전트명} 에이전트로`, `{에이전트명} 에이전트에게`, `{에이전트명} 에이전트:`
- `Agent 도구`, `Agent tool`
- 에이전트명 목록: Explore, Librarian, Oracle, Junior, Metis, Momus 및 agents/ 디렉토리의 모든 에이전트

예외: 자기 자신의 이름 참조, "오케스트레이터에게 권고" 형태

#### 검사 3: 존재하지 않는 도구 참조

에이전트 정의에서 참조하는 도구명이 실제 사용 가능한 도구 목록에 있는지 확인한다.

사용 가능한 도구 목록:
- 기본: Read, Edit, Write, Glob, Grep, Bash, Agent, WebSearch, WebFetch, NotebookEdit
- 지연 로드: TaskCreate, TaskUpdate, TaskGet, TaskList, SendMessage, EnterPlanMode, ExitPlanMode, ToolSearch, AskUserQuestion 등
- MCP: mcp__로 시작하는 도구

#### 검사 4: 역할 제약 위반

에이전트 frontmatter 또는 제약 섹션에서 선언한 역할 제약과 지시 내용의 모순을 탐지한다.

- "읽기 전용" 선언 + 코드 수정/생성 지시
- "위임하지 않는다" 선언 + 다른 에이전트 스폰 지시
- "위임 불가" 선언 + Agent 도구 사용 지시

#### 검사 5: orchestration.md 내부 정합성

- 라우팅 테이블의 처리 방식과 핵심 원칙 간 모순
- 프롬프트 템플릿의 지시와 핵심 원칙 간 모순
- 라우팅 예시가 라우팅 테이블 규칙과 불일치

### 3단계: 결과 보고

```markdown
## 에이전트 감사 결과

### 요약
- 검사 항목: N개
- 문제 발견: N개 (심각: N, 경고: N)

### 심각 (실행 불가능 또는 직접 모순)
1. [파일:행] — [문제 설명]

### 경고 (모호하거나 개선 가능)
1. [파일:행] — [문제 설명]

### 통과
- [검사 항목] — 이상 없음
```

심각도 기준:
- **심각**: 기술적 제한으로 실행 불가능한 지시, 직접적 모순
- **경고**: 모호한 흐름, 미정의 엣지 케이스, 개선 가능한 부분
