# Intent Gate

사용자 메시지를 처리하기 전에 아래 단계를 통과한다.

**Intent(의도) 판별과 Routing(실행 경로)은 별개다.** Intent Gate는 **"사용자가 진짜 무엇을 원하는가"**만 판별한다. "어떤 에이전트/도구로 실행하는가"는 `orchestration.md`가 담당한다. 두 레이어를 섞지 않는다.

## 참고: Layer 1 (훅) 자동 응답 모드

`~/.claude/hooks/intent-gate.js` 훅이 사용자 메시지에서 아래 한글 키워드를 감지하면 응답 전략 메시지를 자동 주입한다.

- **search 모드** (`찾아`, `탐색`, `조회`, `검색`, `어디` 등): 병렬 탐색 최대화 (Explore/Librarian 다중 + Grep/rg/ast-grep)
- **analyze 모드** (`분석`, `조사`, `파악`, `디버깅`, `왜`, `어떻게` 등): 맥락 수집 후 깊이 분석, 필요 시 Oracle 자문

이 두 모드는 아래 Intent 분류와 **직교**한다. 한 메시지에서 Intent와 Mode가 동시 활성 가능 (예: Intent=Investigation + search 모드).

## Step 1. Intent Classification

사용자 발화의 **진짜 의도**를 아래 중 하나로 분류한다. 표면 단어가 아니라 사용자가 궁극적으로 얻으려는 것을 본다.

| Intent | 표면 예시 | 기본 응답 방향 |
|--------|---------|-------------|
| **Research/understanding** | "X가 뭐야?", "Y는 어떻게 동작해?", "왜 이렇게 되어 있어?" | 조사 → 설명. **코드 변경 금지**. |
| **Investigation** | "X 확인해봐", "Y 원인 찾아", "로그 뒤져봐" | 조사 → 보고. **코드 변경 금지**. |
| **Evaluation** | "이 설계 맞아?", "어떻게 생각해?", "리뷰해줘" | 의견 제시 → **사용자 확인 대기**. |
| **Implementation (explicit)** | "X 추가해", "Y 수정해", "Z 만들어" — 명시적 구현 동사 + 구체적 대상 | 구현 또는 위임. |
| **Fix needed** | "X가 안 돼", "에러 났어", "Y가 깨졌어" | 진단 → 최소 수정. |
| **Open-ended change** | "리팩토링", "개선해", "정리해" — 변경은 원하지만 범위가 암시적 | 범위 평가 → 접근 제안 → **사용자 확인 대기**. |
| **Meta** | "너 설정 바꿔", "훅 수정해", "규칙 추가해" — harness/규칙 변경 | 설정·규칙 변경. 코드 작업과 구분한다. |

**핵심 구분**:
- `Implementation (explicit)` vs `Open-ended change`: 명시적 동사 + 구체적 대상이면 explicit, 방향만 있고 범위가 모호하면 open-ended.
- `Research/understanding` vs `Investigation`: 개념/원리 이해 목적이면 Research, 특정 상태 확인/원인 추적이면 Investigation.
- `Fix needed` vs `Implementation (explicit)`: 깨진 것을 고치는 것이면 Fix, 멀쩡한 상태에 기능을 더하는 것이면 Implementation.
- `Meta` vs 나머지: 대상이 **코드베이스가 아니라 harness/규칙/훅**이면 Meta.

## Step 2. Ambiguity Check

Step 1에서 2개 이상 Intent가 후보로 남으면 **명확화 질문 1개**를 던진다. 추측으로 진행 금지. 여러 질문을 묶어 던지지 않는다 — 가장 결정적인 하나만 고른다.

## Step 3. Intent Verbalization (응답 필수 표기)

매 응답의 **첫 줄**에 아래 형식으로 Step 1 결과를 명시한다:

```
[의도: <Intent> — <한 문장 근거>]
```

예시:
- `[의도: Research/understanding — 코드 동작 원리 설명 요청]`
- `[의도: Implementation (explicit) — 로그인 기능 신규 추가]`
- `[의도: Open-ended change — "리팩토링" 범위 미정]`
- `[의도: Evaluation — 설계 타당성 판단 요청]`
- `[의도: Fix needed — 로그인 500 에러 디버깅]`
- `[의도: Meta — UserPromptSubmit 훅 스크립트 수정]`

사용자가 명시적으로 표시 생략을 요청하지 않는 한 **모든 응답**(단순 답변, 에러 상황, 이어지는 턴 포함)에 붙인다.
