---
name: agent-stats
description: "에이전트 사용 통계를 확인하는 스킬. 사용자가 'agent-stats', '에이전트 통계', '에이전트 사용량', '에이전트 현황', 'agent usage' 등을 언급할 때 이 스킬을 사용해야 한다."
---

# Agent Stats - 에이전트 사용 통계

트랜스크립트를 분석하여 에이전트 사용 현황을 보여준다.

## 기본 정보

- **트랜스크립트 경로 (2곳)**:
  - `~/.claude/transcripts/*.jsonl` — 레거시 (2026-03-13 이전)
  - `~/.claude/projects/*/**/*.jsonl` — 현재 (2026-03-30 이후, 프로젝트별)
- **통계 캐시 경로**: `~/.claude/stats-cache.json`
- **에이전트 정의 경로**: `~/.claude/agents/`

---

## 워크플로우

### 1단계: 기간 파라미터 파싱

사용자가 기간을 지정하면 해당 기간만 필터링한다.

- 기간 미지정: 전체 기간
- `7d`, `7일`: 최근 7일
- `30d`, `30일`, `1달`: 최근 30일
- `2026-04-01~2026-04-06`: 특정 기간

### 2단계: 에이전트 스폰 횟수 통합 집계

**두 경로 모두** 검색하여 합산한다. 에이전트 이름에 공백이 포함될 수 있으므로 `while IFS= read -r` 패턴을 사용한다.

기간 필터가 없는 경우:
```bash
# 레거시 + 프로젝트 트랜스크립트 통합 집계
{ grep -h 'subagent_type' ~/.claude/transcripts/*.jsonl 2>/dev/null; find ~/.claude/projects/ -name "*.jsonl" -type f -exec grep -h 'subagent_type' {} + 2>/dev/null; } | grep -o '"subagent_type":"[^"]*"' | sed 's/"subagent_type":"//;s/"$//' | sort | uniq -c | sort -rn
```

기간 필터가 있는 경우 (`-mtime` 또는 timestamp 기반 필터링):
```bash
# 예: 최근 7일
{ find ~/.claude/transcripts/ -name "*.jsonl" -mtime -7 -exec grep -h 'subagent_type' {} + 2>/dev/null; find ~/.claude/projects/ -name "*.jsonl" -type f -mtime -7 -exec grep -h 'subagent_type' {} + 2>/dev/null; } | grep -o '"subagent_type":"[^"]*"' | sed 's/"subagent_type":"//;s/"$//' | sort | uniq -c | sort -rn
```

### 3단계: 에이전트별 세션 수 + 날짜 범위 통합 집계

공백이 포함된 에이전트 이름을 올바르게 처리하기 위해 단일 스크립트로 실행한다.

```bash
{ grep -h 'subagent_type' ~/.claude/transcripts/*.jsonl 2>/dev/null; find ~/.claude/projects/ -name "*.jsonl" -type f -exec grep -h 'subagent_type' {} + 2>/dev/null; } | grep -o '"subagent_type":"[^"]*"' | sed 's/"subagent_type":"//;s/"$//' | sort -u | while IFS= read -r agent; do
  # 스폰 횟수
  count_legacy=$(grep -c "\"subagent_type\":\"$agent\"" ~/.claude/transcripts/*.jsonl 2>/dev/null | awk -F: '{s+=$NF}END{print s+0}')
  count_project=$(find ~/.claude/projects/ -name "*.jsonl" -type f -exec grep -c "\"subagent_type\":\"$agent\"" {} + 2>/dev/null | awk -F: '{s+=$NF}END{print s+0}')
  count=$((count_legacy + count_project))

  # 세션 수 (subagents/ 하위 제외 = 메인 세션만 카운트)
  sess_legacy=$(grep -l "\"subagent_type\":\"$agent\"" ~/.claude/transcripts/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  sess_project=$(find ~/.claude/projects/ -name "*.jsonl" -type f -not -path "*/subagents/*" -exec grep -l "\"subagent_type\":\"$agent\"" {} + 2>/dev/null | wc -l | tr -d ' ')
  sessions=$((sess_legacy + sess_project))

  # 날짜 범위
  first=$({ grep -h "\"subagent_type\":\"$agent\"" ~/.claude/transcripts/*.jsonl 2>/dev/null; find ~/.claude/projects/ -name "*.jsonl" -type f -exec grep -h "\"subagent_type\":\"$agent\"" {} + 2>/dev/null; } | grep -o '"timestamp":"[^"]*"' | sort | head -1 | sed 's/"timestamp":"//;s/"$//')
  last=$({ grep -h "\"subagent_type\":\"$agent\"" ~/.claude/transcripts/*.jsonl 2>/dev/null; find ~/.claude/projects/ -name "*.jsonl" -type f -exec grep -h "\"subagent_type\":\"$agent\"" {} + 2>/dev/null; } | grep -o '"timestamp":"[^"]*"' | sort | tail -1 | sed 's/"timestamp":"//;s/"$//')

  echo "$count|$sessions|$agent|$first|$last"
done | sort -t'|' -k1 -rn
```

### 4단계: 모델별 토큰 사용량

`~/.claude/stats-cache.json`에서 모델별 누적 토큰 사용량을 읽는다.

```bash
python3 -c "
import json
data = json.load(open('$HOME/.claude/stats-cache.json'))
for model, usage in data.get('modelUsage', {}).items():
    inp = usage.get('inputTokens', 0)
    out = usage.get('outputTokens', 0)
    cache_read = usage.get('cacheReadInputTokens', 0)
    cache_create = usage.get('cacheCreationInputTokens', 0)
    print(f'{model}|{inp:,}|{out:,}|{cache_read:,}|{cache_create:,}')
print('---')
print(f\"{data.get('totalSessions', 0)}|{data.get('totalMessages', 0)}\")
"
```

### 5단계: 에이전트 분류

3단계 결과를 아래 기준으로 3개 그룹으로 분류한다.

**활성 에이전트** — `~/.claude/agents/`에 정의 파일(`.md`)이 존재:
- explore, librarian, oracle, metis, momus, atlas, junior

**빌트인 에이전트** — Claude Code 내장 에이전트 (대소문자 무관):
- claude-code-guide, general-purpose, Worker, Plan, Explore (대문자), Librarian (대문자), Oracle (대문자), Momus (대문자), Junior (대문자)

> **중요**: 같은 에이전트가 레거시 트랜스크립트에서는 소문자(`explore`), 프로젝트 트랜스크립트에서는 대문자(`Explore`)로 기록될 수 있다. 대소문자만 다른 경우 **합산**하여 활성 에이전트 표에 표시한다.

**레거시/보관 에이전트** — 위 두 그룹에 속하지 않는 모든 에이전트:
- `~/.claude/agents/archived/`에 있으면 → `보관됨`
- 정의 파일이 없으면 → `삭제됨`

### 6단계: 결과 출력

아래 형식으로 출력한다. 활성 에이전트와 레거시/빌트인 에이전트를 **별도 표**로 분리한다.

```
## 에이전트 사용 통계 {기간 표시}

### 활성 에이전트

| 에이전트 | 모델 | 스폰 횟수 | 세션 수 | 첫 사용 | 마지막 사용 |
|----------|------|--------:|-------:|---------|-----------|
| explore  | Haiku | 439 | 93 | 02-25 | 04-06 |
| ...      |       |     |    |       |       |

### 빌트인/레거시 에이전트

| 에이전트 | 스폰 횟수 | 세션 수 | 기간 | 상태 |
|----------|--------:|-------:|------|------|
| claude-code-guide | 21 | 16 | 03-30 ~ 04-06 | 빌트인 |
| Hephaestus (Deep Agent) | 19 | 15 | 02-25 ~ 03-13 | 삭제됨 |
| ...      |     |    |       |       |

### 모델별 토큰 사용량

| 모델 | Input | Output | Cache Read | Cache Create |
|------|------:|-------:|-----------:|-------------:|
| ... | | | | |

### 요약
- 총 세션: N개 / 총 메시지: N개
- 가장 많이 사용한 에이전트: {name} ({count}회)
- 활성: N개 / 빌트인: N개 / 레거시: N개
```

**모델 매핑** (활성 에이전트 표에서 사용, orchestration.md 기준):
- explore, librarian → Haiku
- junior, atlas → Sonnet
- oracle, metis, momus → Opus
