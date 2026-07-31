#!/usr/bin/env python3
"""아주 작은 markdown → ADF 변환기.

지원: '### 제목', '- bullet' (중첩 '  - '), 일반 문단, 인라인 `code`, **bold**, [text](url)
"""
import json
import re
import sys

INLINE = re.compile(r'(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\))')


def inline_nodes(text):
    nodes = []
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith('`') and part.endswith('`'):
            nodes.append({"type": "text", "text": part[1:-1], "marks": [{"type": "code"}]})
        elif part.startswith('**') and part.endswith('**'):
            nodes.append({"type": "text", "text": part[2:-2], "marks": [{"type": "strong"}]})
        elif part.startswith('['):
            m = re.match(r'\[([^\]]+)\]\(([^)]+)\)', part)
            nodes.append({
                "type": "text",
                "text": m.group(1),
                "marks": [{"type": "link", "attrs": {"href": m.group(2)}}],
            })
        else:
            nodes.append({"type": "text", "text": part})
    return nodes


def para(text):
    return {"type": "paragraph", "content": inline_nodes(text)}


def build(src):
    content = []
    pending = None  # (indent, listItems)

    def flush():
        nonlocal pending
        if pending:
            content.append(pending[1])
            pending = None

    for raw in src.split('\n'):
        line = raw.rstrip()
        if not line.strip():
            continue
        if line.startswith('### '):
            flush()
            content.append({
                "type": "heading",
                "attrs": {"level": 3},
                "content": inline_nodes(line[4:]),
            })
            continue
        m = re.match(r'^(\s*)- (.*)$', line)
        if m:
            indent = len(m.group(1))
            item = {"type": "listItem", "content": [para(m.group(2))]}
            if indent == 0:
                if not pending:
                    pending = (0, {"type": "bulletList", "content": []})
                pending[1]["content"].append(item)
            else:
                parent = pending[1]["content"][-1]
                nested = next((c for c in parent["content"] if c["type"] == "bulletList"), None)
                if nested is None:
                    nested = {"type": "bulletList", "content": []}
                    parent["content"].append(nested)
                nested["content"].append(item)
            continue
        flush()
        content.append(para(line))

    flush()
    return {"version": 1, "type": "doc", "content": content}


if __name__ == '__main__':
    src = open(sys.argv[1], encoding='utf-8').read()
    json.dump(build(src), open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f"wrote {sys.argv[2]}")
