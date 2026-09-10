#!/usr/bin/env python3
"""이슈를 막고 있는 외부 의존을 Jira remote link 로 걸고 해소한다.

서버 API 전달·디자인 에셋 전달·기획 결정처럼 Jira 이슈가 없는 blocker 를,
의존하는 이슈마다 remote link 로 붙인다. jira-deps.py 가 이 링크를 읽어
그래프에 반영하므로 걸어 두면 그 이슈는 착수 가능으로 나오지 않는다.

사용법:
    extdep.py add --issues HDA-22886,HDA-22891 --source server --slug reward-api \
        --title "적립금 잔액·내역 조회 API 전달" \
        --url https://prnd.slack.com/archives/C123/p456 \
        --summary "잔액·내역 조회 엔드포인트 스펙 확정 대기"
    extdep.py list --epic HDA-22882
    extdep.py resolve --epic HDA-22882 --slug reward-api
    extdep.py remove --epic HDA-22882 --slug reward-api

상대 팀 Jira 이슈는 --url 로 쓰지 않는다. 서버에서 개발이 끝난 것과 그것이
클라이언트에 전달된 것은 다른 사건이라, 이슈 상태를 해소 신호로 삼으면
아직 막혀 있는 이슈가 착수 가능으로 올라온다. 근거로는 전달 여부를 실제로
확인할 수 있는 자리(요청 스레드·API 문서·시안)를 쓰고, 상대 이슈 키를
남겨야 하면 --summary 에 적는다.
"""
import argparse
import sys
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

import jira_rest

SOURCES = {"server": "서버", "design": "디자인", "plan": "기획", "other": "외부"}

# 실측에서 표시가 확인된 파비콘만 둔다. 없는 도메인은 기본 링크 아이콘으로 둔다.
ICONS = {
    "figma.com": "https://static.figma.com/app/icon/1/favicon.png",
    "slack.com": "https://a.slack-edge.com/80588/marketing/img/meta/favicon-32.png",
    "notion.so": "https://www.notion.so/images/favicon.ico",
    "notion.site": "https://www.notion.so/images/favicon.ico",
}

BLOCKED, RESOLVED = "⛔", "✅"
MAX_WORKERS = 8


def icon_for(url):
    host = urllib.parse.urlparse(url).netloc
    for domain, icon in ICONS.items():
        if host == domain or host.endswith("." + domain):
            return {"url16x16": icon, "title": domain}
    return None


def build_title(source, title, resolved):
    """화면에서 상태를 알 수 있는 수단이 제목뿐이라 접두사로 표시한다.

    relationship 과 status.resolved 는 이슈 화면에 표시되지 않는다(실측).
    """
    return f"{RESOLVED if resolved else BLOCKED} [{SOURCES[source]}] {title}"


def strip_title(title, source):
    """저장된 제목에서 접두사와 라벨을 걷어 원래 제목만 남긴다."""
    t = title.lstrip(BLOCKED + RESOLVED + " ")
    label = f"[{SOURCES.get(source, '외부')}] "
    return t[len(label):] if t.startswith(label) else t


def link_body(source, slug, title, url, summary, resolved=False):
    obj = {
        "url": url,
        "title": build_title(source, title, resolved),
        "status": {"resolved": resolved},
    }
    if summary:
        obj["summary"] = summary
    icon = icon_for(url)
    if icon:
        obj["icon"] = icon
    return {
        "globalId": f"{jira_rest.PREFIX}:{source}:{slug}",
        "relationship": "is blocked by",
        "object": obj,
    }


def put_link(key, body):
    """같은 globalId 로 POST 하면 새 링크가 생기지 않고 기존 링크가 갱신된다."""
    jira_rest.request("POST", f"/rest/api/3/issue/{key}/remotelink", body)


def scan(epic, slug=None):
    """에픽 하위 이슈에서 외부 의존을 모은다. slug 를 주면 그것만 고른다."""
    keys = jira_rest.search_keys(f"parent = {epic} ORDER BY key ASC")
    if not keys:
        return []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        pairs = list(zip(keys, ex.map(jira_rest.ext_deps, keys)))
    found = []
    for key, links in pairs:
        for l in links:
            if slug is None or l["globalId"].split(":")[-1] == slug:
                found.append((key, l))
    return found


def cmd_add(args):
    issues = [k.strip() for k in args.issues.split(",") if k.strip()]
    body = link_body(args.source, args.slug, args.title, args.url, args.summary)
    for key in issues:
        put_link(key, body)
        print(f"{key}  {body['object']['title']}")
    print(f"\nglobalId {body['globalId']} · {len(issues)}건")


def cmd_resolve(args):
    found = scan(args.epic, args.slug)
    if not found:
        print(f"{args.epic} 하위에 '{args.slug}' 의존이 없다.")
        return
    for key, link in found:
        source = link["globalId"].split(":")[1]
        obj = link["object"]
        body = link_body(source, args.slug,
                         strip_title(obj["title"], source),
                         obj["url"], obj.get("summary"), resolved=True)
        put_link(key, body)
        print(f"{key}  {body['object']['title']}")


def cmd_remove(args):
    found = scan(args.epic, args.slug)
    if not found:
        print(f"{args.epic} 하위에 '{args.slug}' 의존이 없다.")
        return
    for key, link in found:
        jira_rest.request(
            "DELETE", f"/rest/api/3/issue/{key}/remotelink/{link['id']}")
        print(f"{key}  삭제  {link['object']['title']}")


def cmd_list(args):
    found = scan(args.epic)
    if not found:
        print(f"{args.epic} 하위에 외부 의존이 없다.")
        return
    grouped = {}
    for key, link in found:
        g = grouped.setdefault(link["globalId"], {"link": link, "issues": []})
        g["issues"].append(key)
    for gid in sorted(grouped, key=lambda g: (
            (grouped[g]["link"]["object"].get("status") or {}).get("resolved", False), g)):
        o = grouped[gid]["link"]["object"]
        print(o["title"])
        print(f"     slug   {gid.split(':')[-1]}")
        print(f"     이슈   {', '.join(grouped[gid]['issues'])}")
        print(f"     근거   {o['url']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("add", help="외부 의존을 여러 이슈에 건다")
    a.add_argument("--issues", required=True, help="쉼표로 구분한 이슈 키")
    a.add_argument("--source", required=True, choices=sorted(SOURCES))
    a.add_argument("--slug", required=True, help="의존을 지목할 짧은 영문 키")
    a.add_argument("--title", required=True, help="무엇을 기다리는지")
    a.add_argument("--url", required=True, help="전달 여부를 확인할 근거 URL")
    a.add_argument("--summary", help="한 줄 설명")
    a.set_defaults(func=cmd_add)

    for name, help_, func in (
            ("resolve", "전달됐다고 표시한다", cmd_resolve),
            ("remove", "잘못 건 링크를 지운다", cmd_remove)):
        p = sub.add_parser(name, help=help_)
        p.add_argument("--epic", required=True)
        p.add_argument("--slug", required=True)
        p.set_defaults(func=func)

    l = sub.add_parser("list", help="에픽에 걸린 외부 의존을 본다")
    l.add_argument("--epic", required=True)
    l.set_defaults(func=cmd_list)

    args = ap.parse_args()
    if getattr(args, "slug", None) and ":" in args.slug:
        ap.error("slug 에 콜론을 쓰지 않는다 — globalId 구분자다")
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        print(f"실패: {e}", file=sys.stderr)
        sys.exit(1)
