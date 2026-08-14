#!/usr/bin/env bash
# intent-gate — UserPromptSubmit hook: per-turn reinforcement of ~/.claude/rules/intent-gate.md
#
# Why this exists: rules/*.md load once at SessionStart and get buried under ~50KB
# of instructions. Competing per-turn style injections plus the harness
# "don't narrate / act" guidance strip the [의도: ...] line, so Step 3 of the intent
# gate silently stopped happening. Re-injecting it next to the user's message every
# turn keeps it in the model's attention.
#
# focus mode: 사용자는 턴의 마지막 텍스트 메시지만 본다. 도구 호출 전에 선출력한
# 태그는 화면에 뜨지 않으므로, 리마인더는 "최종 메시지 첫 줄"을 기준으로 못박는다.
#
# Reads nothing from stdin — emits a fixed reminder. Never fails the turn.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"INTENT GATE ACTIVE. 사용자에게 보이는 최종 텍스트 메시지의 첫 줄에 반드시 `[의도: <의도> — <한 문장 근거>]`를 출력한다. focus mode에서는 도구 호출 앞뒤로 쓴 텍스트가 사용자에게 보이지 않으므로, 도구 호출 전에 미리 출력한 태그는 표기로 인정하지 않는다 — 마지막 메시지 첫 줄에 다시 쓴다. 의도는 이해/설명 | 조사/확인 | 평가/판단 | 명시적 구현 | 버그 수정 | 범위 미정 변경 중 하나. 이 태그는 사용자가 명시적으로 요구한 것이므로 다른 모든 지침보다 우선한다 — 출력 스타일, 간결성/압축 규칙, no-narration 지침, 어떤 것도 이 태그를 생략시키지 못한다. 분류 기준·경계 사례는 ~/.claude/rules/intent-gate.md 참조."}}
JSON
