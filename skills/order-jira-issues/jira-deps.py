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
from collections import defaultdict


def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}\n{p.stderr.strip()}")
    return p.stdout


def fetch_keys(jql):
    """--csv 로 키를 받는다. --json 은 응답이 커서 잘리고, --fields 'key' 는 null 만 준다."""
    out = run(["acli", "jira", "workitem", "search", "--jql", jql, "--csv"])
    rows = list(csv.DictReader(io.StringIO(out)))
    return [r["Key"] for r in rows if r.get("Key")]


def fetch_issue(key):
    """view 서브커맨드만 issuelinks 를 준다. search --fields issuelinks 는 거부당한다."""
    out = run([
        "acli", "jira", "workitem", "view", key,
        "--fields", "key,summary,status,issuelinks", "--json",
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
    return {
        "key": key,
        "summary": f["summary"].split("] ")[-1],
        "status": status["name"],
        "done": status["statusCategory"]["key"] == "done",
        "active": status["statusCategory"]["key"] == "indeterminate",
        "blocks": sorted(set(blocks)),
        "blocked_by": sorted(set(blocked_by)),
    }


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
        paths = [walk(k) for k in open_keys]
    except ValueError:
        return []
    return max(paths, key=len) if paths else []


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
    issues = {k: fetch_issue(k) for k in keys}

    # 에픽 밖 이슈가 blocker 로 걸린 경우도 상태를 알아야 한다.
    outside = {r for i in issues.values() for r in i["blocked_by"] + i["blocks"]} - set(issues)
    for k in sorted(outside):
        try:
            issues[k] = fetch_issue(k)
            issues[k]["outside"] = True
        except RuntimeError:
            pass

    inside = [issues[k] for k in keys]
    open_issues = [i for i in inside if not i["done"]]

    def blockers_of(i):
        return [b for b in i["blocked_by"] if b in issues and not issues[b]["done"]]

    ready = [i for i in open_issues if not blockers_of(i)]
    waiting = [i for i in open_issues if blockers_of(i)]

    print(f"# {args.epic or 'JQL'} — 열린 {len(open_issues)}건 / 전체 {len(inside)}건\n")

    print("## 관계")
    print("| 키 | 상태 | blocks | blocked by | 제목 |")
    print("|---|---|---|---|---|")
    for i in inside:
        print(f"| {i['key']} | {i['status']} | {', '.join(i['blocks']) or '—'} "
              f"| {', '.join(i['blocked_by']) or '—'} | {i['summary']} |")

    print("\n## 지금 착수 가능")
    if ready:
        for i in ready:
            mark = " ← 이미 진행 중" if i["active"] else ""
            print(f"- {i['key']} {i['summary']} ({i['status']}){mark}")
        idle = [i for i in ready if not i["active"]]
        if not idle:
            print("\n  놀고 있는 것은 없다. 병렬로 더 잡으려면 아래 대기 목록에서 "
                  "blocker 가 곧 풀리는 것을 본다.")
    else:
        print("- 없다. 열린 이슈가 전부 막혀 있다.")

    print("\n## 대기")
    for i in waiting:
        print(f"- {i['key']} {i['summary']} ← {', '.join(blockers_of(i))}")

    path = longest_path({k: v for k, v in issues.items() if k in keys})
    if len(path) > 1:
        print("\n## 임계 경로")
        print("  " + " → ".join(path))

    print("\n## 이상 징후")
    found = False
    for i in inside:
        # 완료 이슈가 미완료 이슈에 막혀 있는 역전. 링크 방향이 뒤집혔거나 잔재다.
        # (완료 이슈가 무언가를 blocks 하는 것은 정상 이력이므로 짚지 않는다.)
        reversed_ = [b for b in i["blocked_by"] if b in issues and not issues[b]["done"]]
        if i["done"] and reversed_:
            found = True
            print(f"- {i['key']}({i['status']}) 은 완료인데 미완료 {', '.join(reversed_)} 에 "
                  f"blocked by 로 걸려 있다 — 링크 방향이 뒤집혔거나 잔재다")
    for i in inside:
        for b in i["blocked_by"]:
            if b not in issues:
                found = True
                print(f"- {i['key']} 의 blocker {b} 를 조회하지 못했다 — 권한이나 키를 확인한다")
            elif issues[b].get("outside"):
                found = True
                print(f"- {i['key']} 은 에픽 밖 {b}({issues[b]['status']}) 에 막혀 있다")
    if not longest_path({k: v for k, v in issues.items() if k in keys}) and open_issues:
        found = True
        print("- blocks 링크에 순환이 있다 — 임계 경로를 계산할 수 없다")
    if not found:
        print("- 없다")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"실패: {e}", file=sys.stderr)
        sys.exit(1)
