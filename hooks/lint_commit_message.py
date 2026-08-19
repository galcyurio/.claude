#!/usr/bin/env python3
"""git commit 메시지가 ~/.claude/references/commit-rules.md 형식 규칙에 맞는지 검사한다.

PreToolUse(Bash) 훅의 본체다. 빠른 탈출은 lint-commit-message.sh 가 담당하고,
여기까지 오는 건 명령 문자열에 'git commit' 이 들어 있는 경우뿐이다.

판정 가능한 형식만 본다. 커밋 단위 분리나 기획자/유저 관점처럼 판단이 필요한
규칙은 검사하지 않는다 — 그건 commit-rules.md 를 읽고 사람이 지키는 영역이다.
"""
import json
import re
import shlex
import sys

TAGS = ("feat", "fix", "refactor", "docs", "style", "test", "chore", "build", "ci")

# 메시지를 새로 쓰지 않는 형태 — 검사 대상이 아니다
SKIP_FLAGS = re.compile(
    r"--amend(?!\s+-m\b)(?!\s+--message)|--no-edit|--fixup|--squash|--reuse-message|--reedit-message|(?<!\S)-C(?!\S)|(?<!\S)-c(?!\S)"
)
GIT_COMMIT = re.compile(r"(?:^|[|;&\n]|\s)git\s+(?:-[^\s]+\s+)*commit(?:\s|$)")
SUMMARY = re.compile(r"^(?:[A-Z][A-Z0-9]*-\d+\s+)?(" + "|".join(TAGS) + r")(?:\([^)]+\))?: \S")
HANGUL = re.compile(r"[가-힣]")
# git 이 만들어 주는 메시지는 형식이 다르다 — 손대지 않는다
GENERATED = re.compile(r'^(Revert "|Merge (branch|remote-tracking|pull request|tag) )')

REF = "~/.claude/references/commit-rules.md"


def extract_message(cmd: str) -> str | None:
    """명령 문자열에서 커밋 메시지를 뽑는다. 확실하지 않으면 None (통과시킨다)."""
    # 1) heredoc:  git commit -F - <<'EOF' ... EOF   /  <<EOF ... EOF
    #    heredoc 이 둘 이상이면 어느 것이 커밋 메시지인지 단정할 수 없으므로 검사하지 않는다.
    docs = re.findall(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1\s*\n(.*?)\n\2\s*$",
                      cmd, re.S | re.M)
    if docs:
        return docs[0][2] if len(docs) == 1 else None

    # 2) -m "..." / --message="..."
    #    git 은 여러 -m 을 빈 줄로 이어 하나의 메시지로 만든다. 같은 방식으로 합친다.
    try:
        tokens = shlex.split(cmd, comments=False, posix=True)
    except ValueError:
        return None
    parts = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in ("-m", "--message") and i + 1 < len(tokens):
            parts.append(tokens[i + 1])
            i += 2
            continue
        if t.startswith("--message="):
            parts.append(t[len("--message="):])
        elif t.startswith("-m") and len(t) > 2:
            parts.append(t[2:])
        i += 1
    return "\n\n".join(parts) if parts else None


def violations(msg: str) -> list[str]:
    lines = msg.rstrip("\n").split("\n")
    summary = lines[0].strip()
    out = []

    if GENERATED.match(summary):
        return out
    if not SUMMARY.match(summary):
        out.append(f"'[IssueID ]태그: 내용' 형식이 아니거나 태그가 목록({', '.join(TAGS)}) 밖이다")
    if summary.endswith("."):
        out.append("요약 끝에 마침표를 붙이지 않는다")
    # 한글 요약만 종결어를 본다. 리네임(A -> B)은 규칙상 '다'로 끝나지 않는다.
    if HANGUL.search(summary) and "->" not in summary and not summary.endswith("다"):
        out.append("요약을 '~한다' 명령문체로 끝낸다")
    if len(lines) > 1 and lines[1].strip():
        out.append("본문이 있으면 요약 다음 줄을 비운다")
    if not any(l.startswith("Co-Authored-By:") for l in lines):
        out.append("Co-Authored-By trailer가 없다")
    return out


def main() -> int:
    raw = sys.stdin.read()
    try:
        cmd = json.loads(raw).get("tool_input", {}).get("command", "")
    except (json.JSONDecodeError, AttributeError):
        return 0
    if not cmd or not GIT_COMMIT.search(cmd) or SKIP_FLAGS.search(cmd):
        return 0

    msg = extract_message(cmd)
    if msg is None:
        return 0
    problems = violations(msg)
    if not problems:
        return 0

    reason = (
        "커밋 메시지가 규칙에 맞지 않는다. "
        + " / ".join(dict.fromkeys(problems))
        + f". {REF} 를 Read하고 메시지를 고쳐 다시 시도한다."
    )
    json.dump(
        {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }},
        sys.stdout,
        ensure_ascii=False,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
