#!/usr/bin/env python3
"""Jira 접근 공통 헬퍼. REST 직접 호출과 acli 검색을 함께 둔다.

remote link 는 acli 가 다루지 못하고 (`acli jira workitem` 하위에 명령이 없다)
Atlassian MCP 도 읽기 도구만 주므로 REST 를 직접 부른다. 인증은
~/.prnd/jira_token 과 ~/.prnd/config.json 의 이메일을 쓰는 Basic 인증이며
~/.prnd-cli 의 스크립트들과 같은 방식이다.
"""
import base64
import csv
import io
import json
import os
import subprocess
import urllib.error
import urllib.request

BASE_URL = "https://prndcompany.atlassian.net"
PREFIX = "extdep"  # 외부 의존 remote link 의 globalId 접두사

_auth = None


def auth_header():
    global _auth
    if _auth is None:
        home = os.path.expanduser("~")
        with open(os.path.join(home, ".prnd/jira_token")) as f:
            token = f.read().strip()
        with open(os.path.join(home, ".prnd/config.json")) as f:
            email = json.load(f)["email"]
        _auth = "Basic " + base64.b64encode(f"{email}:{token}".encode()).decode()
    return _auth


def request(method, path, body=None):
    """REST 호출. 본문이 없는 응답(DELETE 는 204)에는 None 을 준다."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE_URL + path, data=data, method=method)
    req.add_header("Authorization", auth_header())
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} → {e.code} {e.read().decode()[:300]}")
    return json.loads(raw) if raw else None


def search_keys(jql, limit=200):
    """acli 로 이슈 키만 받는다.

    --json 은 응답이 커서 잘리고 --fields 'key' 는 null 만 준다. --limit 을 빼면
    30 건에서 끊긴다.
    """
    p = subprocess.run(
        ["acli", "jira", "workitem", "search",
         "--jql", jql, "--limit", str(limit), "--csv"],
        capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip())
    rows = list(csv.DictReader(io.StringIO(p.stdout)))
    return [r["Key"] for r in rows if r.get("Key")]


def remote_links(key):
    """이슈의 remote link 전량. 외부 의존이 아닌 참고 링크도 함께 온다."""
    return request("GET", f"/rest/api/3/issue/{key}/remotelink") or []


def ext_deps(key):
    """globalId 가 extdep: 으로 시작하는 링크만 고른다."""
    return [l for l in remote_links(key)
            if (l.get("globalId") or "").startswith(PREFIX + ":")]
