#!/usr/bin/env python3
"""difit을 새 세션으로 detach해 띄우고 실제 바인딩 포트·pid를 JSON으로 돌려준다.

하니스 백그라운드 잡(run_in_background)으로 띄우면 잡이 끝나지 않아 태스크가
계속 running으로 남고, `nohup … &`로 띄우면 호출 셸의 프로세스 그룹에 남아
턴이 끝날 때 함께 죽는다. 이 런처는 start_new_session으로 **새 세션**을 만들어
턴 경계를 넘어 살아남게 하고, difit 자체 `--background`와 달리 stdin(PR diff)을
그대로 물려준다.

사용법:
    python3 launch-difit.py --log <로그경로> [--stdin <patch경로>] -- <difit 명령과 인자…>

성공 시 stdout에 JSON 한 줄: {"port": N, "url": "http://localhost:N", "pid": P}
실패 시 stderr에 로그 tail을 남기고 exit 1.
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

BANNER = re.compile(r"server started on http://localhost:(\d+)")
BANNER_TIMEOUT = 30.0
HTTP_TIMEOUT = 15.0


def read_log(path):
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fp:
            return fp.read()
    except FileNotFoundError:
        return ""


def fail(message, log_path):
    tail = "\n".join(read_log(log_path).splitlines()[-20:])
    print(f"launch-difit: {message}", file=sys.stderr)
    if tail:
        print(f"--- {log_path} (tail) ---\n{tail}", file=sys.stderr)
    sys.exit(1)


def wait_for_banner(child, log_path):
    """로그에 기동 배너가 찍히기를 기다려 실제 바인딩 포트를 돌려준다."""
    deadline = time.monotonic() + BANNER_TIMEOUT
    while time.monotonic() < deadline:
        match = BANNER.search(read_log(log_path))
        if match:
            return int(match.group(1))
        if child.poll() is not None:
            fail(f"difit이 기동 전에 종료됐다 (exit {child.returncode})", log_path)
        time.sleep(0.2)
    fail(f"{BANNER_TIMEOUT:.0f}초 안에 기동 배너가 나오지 않았다", log_path)


def wait_for_http(port, log_path):
    """포트가 실제로 응답할 때까지 기다린다. 배너만 보고 URL을 안내하지 않는다."""
    deadline = time.monotonic() + HTTP_TIMEOUT
    last = ""
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(f"http://localhost:{port}/", timeout=2) as resp:
                if resp.status == 200:
                    return
                last = f"HTTP {resp.status}"
        except (urllib.error.URLError, OSError) as exc:
            last = str(exc)
        time.sleep(0.3)
    fail(f"포트 {port}가 응답하지 않는다 ({last})", log_path)


def resolve_pid(port, child):
    """포트를 실제로 들고 있는 pid를 찾는다 (npx difit이면 자식은 래퍼다)."""
    try:
        out = subprocess.run(
            ["lsof", "-ti", f"tcp:{port}"],
            capture_output=True, text=True, timeout=5,
        ).stdout.split()
        if out:
            return int(out[0])
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return child.pid


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--log", required=True, help="difit stdout·stderr을 받을 로그 경로")
    parser.add_argument("--stdin", help="stdin으로 물릴 diff patch 경로 (PR 모드)")
    parser.add_argument("command", nargs=argparse.REMAINDER,
                        help="`--` 뒤에 difit 명령과 인자")
    args = parser.parse_args()

    argv = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not argv:
        print("launch-difit: `--` 뒤에 difit 명령을 넘겨야 한다", file=sys.stderr)
        sys.exit(2)

    stdin_source = subprocess.DEVNULL
    if args.stdin:
        try:
            stdin_source = open(args.stdin, "rb")
        except OSError as exc:
            print(f"launch-difit: stdin 파일을 열 수 없다 — {exc}", file=sys.stderr)
            sys.exit(2)

    with open(args.log, "wb") as log:
        child = subprocess.Popen(
            argv, stdin=stdin_source, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
        )

    port = wait_for_banner(child, args.log)
    wait_for_http(port, args.log)
    print(json.dumps({
        "port": port,
        "url": f"http://localhost:{port}",
        "pid": resolve_pid(port, child),
    }))


if __name__ == "__main__":
    main()
