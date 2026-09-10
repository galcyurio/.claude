#!/usr/bin/env python3
"""에픽 하위 이슈의 blocks 그래프를 만들고 착수 가능한 이슈를 골라낸다.

사용법:
    python3 jira-deps.py HDA-22517
    python3 jira-deps.py HDA-22517 --jql "project = HDA AND labels = foo"

acli 읽기 서브커맨드(search/view)만 쓴다. 이슈를 만들거나 고치지 않는다.
"""
import argparse
import csv
import io
import json
import subprocess
import sys
import unicodedata
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

import jira_rest

SUMMARY_MAX = 40  # 그래프 정렬이 깨지지 않게 제목을 자르는 표시 폭
DESC_MAX = 600    # 설명 부록에서 이슈당 싣는 길이. 판단에 필요한 앞부분만 남긴다
MAX_WORKERS = 8   # acli 는 호출마다 프로세스를 새로 띄운다. 순차로 돌리면 이슈 수에 비례해 느려진다


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{p.stderr.strip()}")
    return p.stdout


def fetch_keys(jql):
    """--csv 로 키를 받는다.

    --json 은 응답이 커서 잘리고, --fields 'key' 는 null 만 준다. --limit 을 빼면
    30 건에서 끊긴다.
    """
    out = run(["acli", "jira", "workitem", "search",
               "--jql", jql, "--limit", "200", "--csv"])
    rows = list(csv.DictReader(io.StringIO(out)))
    return [r["Key"] for r in rows if r.get("Key")]


def adf_text(node):
    """Jira 설명은 ADF 트리로 온다. text 노드만 모으고 블록 사이에 줄을 바꾼다."""
    if not isinstance(node, dict):
        return ""
    if node.get("type") == "text":
        return node.get("text", "")
    sep = "\n" if node.get("type") in ("doc", "bulletList", "orderedList") else ""
    return sep.join(adf_text(c) for c in node.get("content") or [])


def fetch_issue(key):
    """view 서브커맨드만 issuelinks 를 준다. search --fields issuelinks 는 거부당한다."""
    out = run([
        "acli", "jira", "workitem", "view", key,
        "--fields", "key,summary,status,issuelinks,description", "--json",
    ])
    f = json.loads(out)["fields"]
    blocks, blocked_by = [], []
    for link in f.get("issuelinks") or []:
        if (link.get("type") or {}).get("name") != "Blocks":
            continue
        if "outwardIssue" in link:
            blocks.append(link["outwardIssue"]["key"])
        if "inwardIssue" in link:
            blocked_by.append(link["inwardIssue"]["key"])
    status = f["status"]
    desc = " ".join(adf_text(f.get("description")).split("\n\n"))
    return {
        "key": key,
        "summary": f["summary"].split("] ")[-1],
        "full_summary": f["summary"],  # 그래프는 제목을 자르므로 부록에는 원본을 싣는다
        "desc": desc.strip(),
        "status": status["name"],
        "done": status["statusCategory"]["key"] == "done",
        "active": status["statusCategory"]["key"] == "indeterminate",
        "blocks": sorted(set(blocks)),
        "blocked_by": sorted(set(blocked_by)),
    }


def fetch_issues(keys):
    """키 순서를 지키면서 병렬로 받는다. 조회에 실패하면 그대로 올려보낸다."""
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        return dict(zip(keys, ex.map(fetch_issue, keys)))


def strip_mark(title):
    """그래프가 노드 앞에 마커를 다시 붙이므로 저장된 접두사(⛔·✅)는 걷어낸다."""
    return title.lstrip("⛔✅ ")


def fetch_extdeps(keys):
    """이슈별 외부 의존(remote link)을 병렬로 받는다."""
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        return dict(zip(keys, ex.map(jira_rest.ext_deps, keys)))


def attach_extdeps(issues, keys):
    """미해소 외부 의존을 가상 노드로 세우고 막힌 이슈의 blocked_by 에 잇는다.

    서버 API 전달·디자인 에셋·기획 결정처럼 Jira 이슈가 아닌 blocker 를 순서
    계산에 넣기 위한 것이다. extdep.py 가 건 링크(globalId 가 extdep:)만 본다.
    """
    open_keys = [k for k in keys if not issues[k]["done"]]
    for key, links in fetch_extdeps(open_keys).items():
        for l in links:
            if (l["object"].get("status") or {}).get("resolved"):
                continue  # 전달이 끝난 것은 순서 판단에 쓰지 않는다
            gid = l["globalId"]
            node = issues.setdefault(gid, {
                "key": gid,
                "summary": strip_mark(l["object"]["title"]),
                "status": "외부 대기",
                "done": False,
                "active": False,
                "blocks": [],
                "blocked_by": [],
                "extdep": True,
            })
            if key not in node["blocks"]:
                node["blocks"].append(key)
            if gid not in issues[key]["blocked_by"]:
                issues[key]["blocked_by"].append(gid)


def longest_path(issues):
    """미완료 이슈만으로 가장 긴 blocks 사슬을 구한다. 순환이 있으면 빈 리스트."""
    open_keys = {k for k, i in issues.items() if not i["done"]}
    memo, visiting = {}, set()

    def walk(k):
        if k in memo:
            return memo[k]
        if k in visiting:
            raise ValueError("cycle")
        visiting.add(k)
        best = [k]
        for nxt in issues[k]["blocks"]:
            if nxt in open_keys:
                cand = [k] + walk(nxt)
                if len(cand) > len(best):
                    best = cand
        visiting.discard(k)
        memo[k] = best
        return best

    try:
        paths = [walk(k) for k in sorted(open_keys)]  # 동률일 때 결과를 고정한다
    except ValueError:
        return []
    return max(paths, key=len) if paths else []


# --- 그래프 렌더링 -------------------------------------------------------------

def dwidth(s):
    """터미널 표시 폭. 한글·전각 문자는 두 칸을 먹는다."""
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def pad(s, w):
    return s + " " * max(0, w - dwidth(s))


def trunc(s, w):
    """표시 폭 w 로 자른다. 말줄임표는 폭이 확정된 ASCII 를 쓴다."""
    if dwidth(s) <= w:
        return s
    out = ""
    for c in s:
        if dwidth(out) + dwidth(c) > w - 2:
            break
        out += c
    return out + ".."


def build_waves(issues, keys, open_blockers):
    """열린 이슈에 Wave 레벨을 매긴다. 순환에 걸린 이슈는 따로 돌려준다."""
    nodes = [k for k in keys if not issues[k]["done"]]
    for k in list(nodes):
        for b in open_blockers(k):
            if b not in nodes:
                nodes.append(b)  # 에픽 밖 열린 blocker 도 노드로 세운다
    level, remaining = {}, set(nodes)
    while remaining:
        layer = [k for k in nodes if k in remaining
                 and not [b for b in open_blockers(k) if b in remaining]]
        if not layer:
            break  # 남은 것은 순환
        lv = max(level.values(), default=0) + 1
        for k in layer:
            level[k] = lv
        remaining -= set(layer)
    waves = defaultdict(list)
    for k in nodes:
        if k in level:
            waves[level[k]].append(k)
    return waves, [k for k in nodes if k in remaining]


def render_graph(issues, keys, crit):
    """Wave 레이어 그래프. 관계표를 대체하는 전량 뷰다."""
    inside = set(keys)

    def open_blockers(k):
        return [b for b in issues[k]["blocked_by"]
                if b in issues and not issues[b]["done"]]

    waves, cyclic = build_waves(issues, keys, open_blockers)

    def label(k):
        i = issues[k]
        # 마커는 East Asian Wide 글리프만 쓴다. ○ ▶ ✔ 는 폭이 터미널마다 1~2 로
        # 달라져서 뒤따르는 화살표 열이 어긋난다.
        if i.get("extdep"):
            # 외부 의존은 키가 없다. 키 자리를 제목에 내주고 마커는 막힌 이슈와
            # 같은 ⛔ 를 쓴다 — 읽는 쪽에서는 둘 다 "지금 못 하는 이유"다.
            s = f"⛔ {trunc(i['summary'], SUMMARY_MAX + 12)}"
            return s + " *" if k in crit else s
        if open_blockers(k):
            mark = "⛔"
        elif i["active"]:
            mark = "🟠"
        else:
            mark = "🟢"
        s = f"{mark} {k}  {trunc(i['summary'], SUMMARY_MAX)}"
        if i["active"]:
            s += f" ({i['status']})"
        if k not in inside:
            s += " (에픽 밖)"
        if k in crit:
            s += " *"
        return s

    shown = [k for lv in sorted(waves) for k in waves[lv]] + cyclic
    if not shown:
        print("## 그래프\n\n열린 이슈가 없다.")
        return
    labels = {k: label(k) for k in shown}
    col = max((dwidth(v) for v in labels.values()), default=0) + 4

    def name(k):
        """외부 의존은 키가 아니라 제목으로 가리킨다."""
        i = issues.get(k)
        return i["summary"] if i and i.get("extdep") else k

    def block(k):
        rows = []
        head = "  " + labels[k]
        outs = [name(t) if t in issues else t + "(?)"
                for t in issues[k]["blocks"]
                if not (t in issues and issues[t]["done"])]
        # 조회 못 한 blocker 도 그린다. 안 그리면 그래프가 실제보다 낙관적으로 보인다.
        ins = [name(b) for b in open_blockers(k)] + [
            b + "(?)" for b in issues[k]["blocked_by"] if b not in issues]
        lone = not outs and not issues[k]["blocked_by"] and not issues[k]["done"]
        if not outs:
            rows.append(head + ("  (고립)" if lone else ""))
        elif len(outs) == 1:
            rows.append(pad(head, col) + f"───▶ {outs[0]}")
        else:
            rows.append(pad(head, col) + f"─┬─▶ {outs[0]}")
            for t in outs[1:-1]:
                rows.append(" " * col + f" ├─▶ {t}")
            rows.append(" " * col + f" └─▶ {outs[-1]}")
        if ins:
            rows.append(" " * 7 + "▲ " + ", ".join(ins))
        return "\n".join(rows)

    # 외부 의존은 Wave 에 섞지 않고 따로 낸다. 내가 지금 잡을 수 있는 것과
    # 다른 팀에서 와야 풀리는 것은 읽는 목적이 다르다.
    ext_nodes = [k for lv in sorted(waves) for k in waves[lv]
                 if issues[k].get("extdep")]

    print("## 그래프")
    for lv in sorted(waves):
        layer = [k for k in waves[lv] if not issues[k].get("extdep")]
        if not layer:
            continue
        mine = [k for k in layer if k in inside]  # 에픽 밖 노드는 세지 않는다
        n = len(mine)
        if lv == 1:
            # Wave 1 은 "미완료 blocker 가 없다"는 뜻일 뿐이다. 이미 누가 잡고 있는
            # 이슈까지 "착수 가능"으로 세면 병렬 여력이 실제보다 커 보인다.
            active = len([k for k in mine if issues[k]["active"]])
            head = f"Wave 1 ─ 막힌 것 없음 (착수 가능 {n - active}"
            head += f" · 진행 중 {active})" if active else ")"
        else:
            head = f"Wave {lv} ─ Wave {lv - 1} 이후 ({n}건)"
        print(f"\n{head}")
        for k in layer:
            print(block(k))

    if ext_nodes:
        print(f"\n외부 대기 ─ 다른 팀에서 와야 풀린다 ({len(ext_nodes)}건)")
        for k in ext_nodes:
            print(block(k))
    if cyclic:
        print("\n순환 ─ blocks 링크가 서로를 물고 있어 Wave 를 매길 수 없다")
        for k in cyclic:
            print(block(k))
    print("\n범례  🟢 착수 가능  🟠 진행 중  ⛔ 막힘·외부 대기  * 임계 경로"
          "  ───▶ blocks  ▲ 남은 blocker  (?) 조회 실패")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("epic", nargs="?", help="에픽 키 (예: HDA-22517)")
    ap.add_argument("--jql", help="에픽 대신 임의 JQL 로 대상 지정")
    args = ap.parse_args()

    if not args.epic and not args.jql:
        ap.error("에픽 키나 --jql 중 하나는 필요하다")
    jql = args.jql or f"parent = {args.epic} ORDER BY key ASC"

    keys = fetch_keys(jql)
    if not keys:
        print("대상 이슈가 없다.")
        return
    issues = fetch_issues(keys)

    # 에픽 밖 이슈가 blocker 로 걸린 경우도 상태를 알아야 한다.
    outside = sorted({r for i in issues.values()
                      for r in i["blocked_by"] + i["blocks"]} - set(issues))
    if outside:
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
            pending = [(k, ex.submit(fetch_issue, k)) for k in outside]
        for k, fut in pending:
            try:
                issues[k] = fut.result()
                issues[k]["outside"] = True
            except RuntimeError:
                pass

    # 외부 의존은 에픽 밖 이슈 조회가 끝난 뒤에 붙인다. 먼저 붙이면 가상 노드의
    # globalId 가 에픽 밖 키로 잡혀 acli 조회를 시도한다.
    attach_extdeps(issues, keys)

    inside = [issues[k] for k in keys]
    open_issues = [i for i in inside if not i["done"]]

    path = longest_path({k: v for k, v in issues.items() if k in keys})

    print(f"# {args.epic or 'JQL'} — 열린 {len(open_issues)}건 / 전체 {len(inside)}건\n")

    crit = set(path) if len(path) > 1 else set()
    render_graph(issues, keys, crit)

    if len(path) > 1:
        print("\n## 임계 경로")
        print("  " + " → ".join(path))

    # 이상 징후는 있을 때만 낸다. "없다" 한 줄도 그래프를 화면 밖으로 밀어낸다.
    notes = []
    for i in inside:
        # 완료 이슈가 미완료 이슈에 막혀 있는 역전. 링크 방향이 뒤집혔거나 잔재다.
        # (완료 이슈가 무언가를 blocks 하는 것은 정상 이력이므로 짚지 않는다.)
        reversed_ = [b for b in i["blocked_by"] if b in issues and not issues[b]["done"]]
        if i["done"] and reversed_:
            notes.append(f"- {i['key']}({i['status']}) 은 완료인데 미완료 "
                         f"{', '.join(reversed_)} 에 blocked by 로 걸려 있다 — "
                         f"링크 방향이 뒤집혔거나 잔재다")
    for i in inside:
        for b in i["blocked_by"]:
            if b not in issues:
                notes.append(f"- {i['key']} 의 blocker {b} 를 조회하지 못했다 — "
                             f"권한이나 키를 확인한다")
            elif issues[b].get("outside"):
                notes.append(f"- {i['key']} 은 에픽 밖 {b}({issues[b]['status']}) 에 막혀 있다")
    for i in inside:
        # 임계 경로가 외부 의존에 걸리면 내가 서둘러 앞당길 수 있는 지점이 아니다.
        ext = [issues[b]["summary"] for b in i["blocked_by"]
               if b in issues and issues[b].get("extdep")]
        if i["key"] in crit and ext:
            notes.append(f"- 임계 경로의 {i['key']} 이 외부 의존에 막혀 있다 — "
                         f"{', '.join(ext)}")
    if not path and open_issues:
        notes.append("- blocks 링크에 순환이 있다 — 임계 경로를 계산할 수 없다")
    if notes:
        print("\n## 이상 징후")
        print("\n".join(notes))

    # 착수 대상을 고를 때 쓰는 재료다. 스킬은 소스 코드를 열지 않으므로, 무엇을
    # 건드리는 작업인지 알 원천은 이 설명뿐이다.
    described = [i for i in open_issues if i["desc"]]
    if described:
        print("\n## 설명 — 열린 이슈")
        for i in described:
            print(f"\n### {i['key']}  {i['full_summary']}")
            d = i["desc"]
            print(d[:DESC_MAX] + (" …" if len(d) > DESC_MAX else ""))

if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"실패: {e}", file=sys.stderr)
        sys.exit(1)
