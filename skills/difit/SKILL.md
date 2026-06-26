---
name: difit
description: "변경사항을 difit(diff 뷰어)로 띄워 사용자에게 리뷰를 요청하는 스킬. 사용자가 'difit', 'difit으로 띄워', 'difit으로 리뷰', '뷰어로 보여줘' 등 difit를 명시적으로 지칭할 때만 사용한다. 일반 '리뷰해줘'·'코드 리뷰'·다관점 병렬 리뷰는 review-by-agents를 사용한다."
---

# Difit

## Overview

This skill requests a code review from the user using difit.
Before running commands, choose `<difit-command>` using the following rule:

- If `command -v difit` succeeds, use `difit`.
- Otherwise, use `npx difit`.
- If falling back to `npx difit` would require network access in a sandboxed environment without network permission, request escalated permissions and user approval before running it.

If the user leaves review comments, they are printed to stdout when the chosen difit command exits.
When review comments are returned, continue work and address them.
If the server is shut down without comments, treat it as "no review comments were provided." Restarting it is unnecessary.
Manual verification of whether the page launched correctly is also unnecessary.

## Commands

- Review uncommitted changes before commit: `<difit-command> .`
- Review the HEAD commit: `<difit-command>`
- Review staging area changes: `<difit-command> staged`
- Review unstaged changes only: `<difit-command> working`

Basic Usage:

```bash
<difit-command> <target>                    # View single commit diff. ex: difit 6f4a9b7
<difit-command> <target> [compare-with]     # Compare two commits/branches. ex: difit feature main
```

## Startup Comments — review-by-agents only

**Do not author startup comments for direct difit requests.** When a user invokes difit directly (e.g. `/difit`, "difit으로 띄워"), they want the diff viewer — not AI opinions. Launch immediately: do **not** read the diff to find "key decisions," grep for line numbers, or compose `--comment` payloads before launching. That pre-launch analysis is what makes difit feel slow.

The `--comment` flag is reserved for the `review-by-agents` skill, which builds its own comment payloads from review findings and constructs the difit command itself (see review-by-agents step 6-A). The syntax, for reference:

```bash
<difit-command> <target> [compare-with] \
  --comment '{"type":"thread","filePath":"src/foobar.ts","position":{"side":"old","line":102},"body":"line 1\nline 2"}' \
  --comment '{"type":"thread","filePath":"src/example.ts","position":{"side":"new","line":{"start":36,"end":39}},"body":"Range comment for L36-L39"}'
```

When review-by-agents builds these comments:

- Use `type: "thread"` for each comment.
- Write comment bodies in the language the user is using.
- Use `position.side: "new"` for lines that exist on the target side of the diff; `"old"` for lines that exist only on the deleted side.
- Use range comments for issues that span multiple lines.
- Never copy secrets, tokens, passwords, API keys, private keys, or other credential-like material from the diff into `--comment` bodies or any command-line arguments.

## Including Untracked Files

For uncommitted changes, if files not yet added to git should also appear in the diff, add `--include-untracked`.

```bash
<difit-command> . --include-untracked
```

## Constraints

Can only be used inside a Git-managed directory.
