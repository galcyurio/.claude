---
name: review-by-self
description: "변경사항을 difit(diff 뷰어)로 띄워 사용자가 직접 리뷰하게 하는 스킬. 사용자가 'review-by-self', 'difit', 'difit으로 띄워', 'difit으로 리뷰', '뷰어로 보여줘' 등을 지칭할 때만 사용한다. 일반 '리뷰해줘'·'코드 리뷰'·다관점 병렬 리뷰는 review-by-agents를 사용한다."
model: sonnet
effort: low
---

# review-by-self — difit 뷰어로 변경사항 직접 리뷰

## Overview

This skill opens the user's diff in difit so the user can review it themselves, then collects any comments they leave — **without blocking the session**.

Choose `<difit-command>`:

- If `command -v difit` succeeds, use `difit`.
- Otherwise, use `npx difit`.
- If `npx difit` would require network access in a sandboxed environment without network permission, request escalated permissions and user approval before running it.

## Commands

Pick the target by what the user wants reviewed:

- Review uncommitted changes before commit: `<difit-command> .`
- Review the HEAD commit: `<difit-command>`
- Review staging area changes: `<difit-command> staged`
- Review unstaged changes only: `<difit-command> working`

```bash
<difit-command> <target>                    # View single commit diff. ex: difit 6f4a9b7
<difit-command> <target> [compare-with]     # Compare two commits/branches. ex: difit feature main
```

## Launch (non-blocking)

Launch difit **as a background process** so the session is not blocked while the user reviews:

- Run `<difit-command> <target>` in the background (do not block the turn waiting for the command to return).
- Do **not** pass difit's own `--background` flag — it forces `--no-open`, so the browser never opens. A plain `<difit-command> <target>` launched as a background job is what opens the viewer.
- Do **not** pass `--keep-alive`. Without it, difit shuts itself down when the user closes the browser. That auto-shutdown is the "review done" signal and needs no cleanup.
- Do **not** author `--comment` payloads (see "Startup Comments").

difit prints `difit server started on http://localhost:<port>` and opens the browser. Tell the user the viewer is open and to **close the browser when they finish reviewing**, then end your turn. Do not verify the page launched. Do not poll.

## Retrieving comments

The background difit task ends on its own when the user closes the browser (the server auto-exits on client disconnect). When that task completes, read its output. difit prints any comments left during the session on exit:

```
📝 Comments from review session:
==================================================
<file>:L<line>
<comment body>
==================================================
Total comments: N
```

- If a comment block is present, address each comment (use its `file`:`line` and body) and continue the work.
- If `Total comments: 0` or no comment block appears, treat it as "no review comments were provided." Restarting difit is unnecessary.

## Never kill the difit process

**Never run `kill`, `pkill`, or `lsof … | xargs kill` against difit.** difit launches the browser as a child process; killing difit (or its process group) can take the user's browser down with it. difit exits cleanly on its own when the browser is closed — always let it self-terminate.

## Startup Comments — review-by-agents only

**Do not author startup comments for direct difit requests.** When a user invokes difit directly (e.g. `/review-by-self`, "difit으로 띄워"), they want the diff viewer — not AI opinions. Launch immediately: do **not** read the diff to find "key decisions," grep for line numbers, or compose `--comment` payloads before launching. That pre-launch analysis is what makes difit feel slow.

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

- Can only be used inside a Git-managed directory.
- Never kill the difit process (see "Never kill the difit process").
