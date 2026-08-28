---
name: audit-harness
description: "오케스트레이션 규칙·에이전트 정의·스킬 정의의 일관성을 검사하는 스킬. 사용자가 'audit-harness', 'harness 감사', 'harness 점검', '에이전트 감사', '스킬 감사', '오케스트레이션 리뷰', 'harness audit' 등을 언급할 때 이 스킬을 사용해야 한다."
---

# Audit Harness - 오케스트레이션/에이전트/스킬 일관성 검사

`~/.claude/rules/`의 규칙 문서, 에이전트 정의, `~/.claude/skills/`의 스킬 정의 간의 모순, 실행 불가능한 지시, 누락된 흐름, 교차 참조 불일치를 탐지한다.

## 기본 정보

- **Rules 전체**: `~/.claude/rules/*.md` (orchestration, intent-gate, git, references 등)
- **에이전트 정의**: `~/.claude/agents/*.md`
- **스킬 정의**: `~/.claude/skills/*/SKILL.md`
- **팀 설정**: `~/.claude/teams/*/config.json`

## 기술적 전제

- 서브에이전트가 Agent 도구를 쓸 수 있는지는 그 에이전트의 도구 목록이 결정한다. `tools`를 지정하지 않은 에이전트(Junior, Designer 등)는 Agent를 포함한 전체 도구를 갖고, Explore처럼 "All tools except Agent"로 명시된 에이전트만 중첩 스폰에서 제외된다.
- 다만 `rules/orchestration.md`는 태스크 상태를 한 곳에서 관리하기 위해 **Junior 스폰을 오케스트레이터가 직접 수행하도록** 정책으로 규정한다. 중첩 위임은 서브에이전트에게 명시적으로 지시할 때만 쓴다. 따라서 상시 중첩 스폰은 기술적 불가능이 아니라 정책 위반으로 판정한다.
- SendMessage로 아직 스폰되지 않은 에이전트를 깨울 수 없다.
- 스킬은 오케스트레이터(메인 스레드)에서 실행되므로 에이전트를 스폰할 수 있다.

---

## 워크플로우

### 1단계: 데이터 수집

1. `~/.claude/rules/*.md` 전체 읽기 (Glob → Read)
2. `~/.claude/agents/*.md` 전체 읽기 (Glob → Read)
3. `~/.claude/skills/*/SKILL.md` 전체 읽기 (Glob → Read)
4. `~/.claude/teams/*/config.json` 읽기 (존재하는 경우)

### 2단계: 검사 항목 실행

#### 검사 1: 에이전트 테이블 정합성

orchestration.md의 에이전트 테이블과 실제 `~/.claude/agents/` 파일을 비교한다.

- 테이블에 있지만 정의 파일이 없는 에이전트
- 정의 파일이 있지만 테이블에 없는 에이전트
- 모델 불일치 (테이블의 모델 vs frontmatter의 model)
- 역할 설명 불일치

#### 검사 2: 에이전트 정의의 중첩 스폰 지시

각 에이전트 정의에서 다른 에이전트를 스폰하는 지시를 탐지한다.

탐지 패턴:
- `{에이전트명} 에이전트로`, `{에이전트명} 에이전트에게`, `{에이전트명} 에이전트:`
- `Agent 도구`, `Agent tool`
- 에이전트명 목록: Explore, Librarian, Oracle, Junior, Metis, Momus 및 agents/ 디렉토리의 모든 에이전트

판정은 그 에이전트의 도구 목록을 먼저 확인하고 내린다:

- 도구 목록에서 Agent가 빠진 에이전트(Explore, 그리고 `tools`를 명시하며 Agent를 넣지 않은 에이전트)가 스폰을 지시하면 → 심각 (실행 불가능)
- 도구 목록상 스폰이 가능하더라도 `rules/orchestration.md`의 "Junior 스폰은 오케스트레이터가 직접 수행한다" 정책을 벗어나 상시 중첩 위임을 지시하면 → 경고

예외: 자기 자신의 이름 참조, "오케스트레이터에게 권고한다"·"오케스트레이터가 위임한다" 형태의 서술

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

#### 검사 6: rules 간 교차 참조 및 일관성

`~/.claude/rules/*.md` 파일들 사이의 참조와 내용을 검사한다.

- **참조 대상 존재 여부**: 한 rules 파일이 다른 rules 파일을 언급할 때 대상 파일이 실제로 존재하는가
- **참조 용어 정의 여부**: 참조한 규칙명/용어가 대상 파일에 실제로 정의되어 있는가 (예: `intent-gate.md`가 "orchestration.md의 분류"를 언급하면, 그 분류 목록이 orchestration.md에 실제로 존재하는가)
- **rules 간 직접 모순**: 한 쪽이 "X를 해라", 다른 쪽이 "X를 하지 마라" 같은 충돌
- **용어 일관성**: 동일한 개념이 여러 rules에서 서로 다른 이름으로 쓰이지 않는가
- **에이전트 정의와의 모순**: rules에서 선언된 에이전트 제약(예: "Oracle은 읽기 전용")이 `agents/*.md` frontmatter 권한과 모순되지 않는가

#### 검사 7: 스킬 메타데이터 정합성

각 `~/.claude/skills/*/SKILL.md`의 frontmatter를 검사한다.

- frontmatter `name`이 디렉토리명과 일치하는가 (불일치 시 스킬 로드/인식 오류) → 심각
- `description`이 존재하고 트리거 문구(사용자가 호출할 표현)를 포함하는가 → 누락 시 경고
- 동일 `name`을 가진 스킬이 둘 이상인가 → 심각

#### 검사 8: 스킬 내 스폰 지시 검증

스킬은 오케스트레이터에서 실행되므로 에이전트 스폰 자체는 정상이다. 아래만 위반으로 본다:

- 스킬이 **도구 목록에서 Agent가 빠진 에이전트**(Explore 등)에게 넘기는 프롬프트 안에서 또 다른 에이전트 스폰을 지시 → 심각 (실행 불가능)
- 스킬이 서브에이전트 프롬프트 안에서 상시 중첩 위임을 지시해 `rules/orchestration.md`의 "Junior 스폰은 오케스트레이터가 직접 수행한다" 정책을 벗어남 → 경고
- 아직 스폰되지 않은 에이전트를 `SendMessage`로 깨우라는 지시 → 심각

#### 검사 9: 스킬 교차 참조 유효성

스킬이 참조하는 대상이 실제로 존재하는지 확인한다.

- 참조한 다른 스킬이 `~/.claude/skills/`에 존재하는가
- 참조한 **레지스트리 에이전트**(Junior, Oracle, Designer, Metis, Momus, Librarian)가 `~/.claude/agents/`에 존재하는가 — 역할 프롬프트로만 쓰는 임시 에이전트(예: 리뷰어 역할 분담)는 대상에서 제외
- 참조한 rules 파일이 `~/.claude/rules/`에 존재하는가
- 참조한 도구명이 검사 3의 사용 가능 도구 목록에 있는가

#### 검사 10: 스킬 ↔ orchestration 라우팅 정합성

orchestration.md "스킬 실행 중 오케스트레이션"은 코드 수정 단계에서도 라우팅 규칙을 따르라고 명시한다. 그 라우팅은 **읽기 작업과 중소 규모 구현(단일 파일이든 2개 이상 파일이든)을 오케스트레이터가 직접 처리하고, Large 작업만 Junior에게 위임한다.**

- 스킬이 Explicit·Mid-sized 규모의 작업을 Junior에게 위임하도록 지시하거나, 파일 개수만을 근거로 직접 처리를 금지하면 → 심각 (orchestration.md 라우팅과 직접 모순)
- 스킬이 Wave 분리가 필요한 Large 작업을 계획 승인 절차 없이 직접 수행하도록 지시하면 → 경고
- 스킬이 규모 판정을 재정의하지 않고 `rules/orchestration.md`에 위임하면 통과

### 3단계: 결과 보고

```markdown
## Harness 감사 결과

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
