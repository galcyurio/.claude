#!/usr/bin/env node
// Claude Code UserPromptSubmit hook: inject search/analyze mode strategies.
// Ported from omo keyword-detector (code-yeongyu/oh-my-openagent).

const SEARCH_PATTERN =
  /검색|찾아|탐색|조회|스캔|서치|뒤져|찾기|어디|추적|탐지|찾아봐|찾아내|보여줘|목록/;

const ANALYZE_PATTERN =
  /분석|조사|파악|연구|검토|진단|이해|설명|원인|이유|뜯어봐|따져봐|평가|해석|디버깅|디버그|어떻게|왜|살펴/;

const SEARCH_MESSAGE = `[search-mode]
MAXIMIZE SEARCH EFFORT. Launch multiple agents IN PARALLEL:
- Explore agent (codebase patterns, file structures, ast-grep)
- Librarian agent (remote repos, official docs, GitHub examples)
Plus direct tools: Grep, ripgrep (rg), ast-grep (sg)
NEVER stop at first result - be exhaustive.`;

const ANALYZE_MESSAGE = `[analyze-mode]
ANALYSIS MODE. Gather context before diving deep:

CONTEXT GATHERING (parallel):
- 1-2 Explore agents (codebase patterns, implementations)
- 1-2 Librarian agents (if external library involved)
- Direct tools: Grep, AST-grep, LSP for targeted searches

IF COMPLEX - DO NOT STRUGGLE ALONE. Consult Oracle for architecture/design decisions.

SYNTHESIZE findings before proceeding.`;

const CODE_BLOCK_PATTERN = /```[\s\S]*?```/g;
const INLINE_CODE_PATTERN = /`[^`]+`/g;

let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  input += chunk;
});
process.stdin.on("end", () => {
  let data;
  try {
    data = JSON.parse(input);
  } catch {
    process.exit(0);
  }

  const prompt = typeof data.prompt === "string" ? data.prompt : "";
  if (!prompt) process.exit(0);

  const cleaned = prompt
    .replace(CODE_BLOCK_PATTERN, "")
    .replace(INLINE_CODE_PATTERN, "");

  const messages = [];
  if (SEARCH_PATTERN.test(cleaned)) messages.push(SEARCH_MESSAGE);
  if (ANALYZE_PATTERN.test(cleaned)) messages.push(ANALYZE_MESSAGE);

  if (messages.length === 0) process.exit(0);

  const output = {
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: messages.join("\n\n"),
    },
  };
  process.stdout.write(JSON.stringify(output));
});
