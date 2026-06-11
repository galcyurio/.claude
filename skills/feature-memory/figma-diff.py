#!/usr/bin/env python3
"""
figma-diff.py — Figma frame 목록 추출 + hash diff

사용법:
  python3 figma-diff.py \\
    --metadata <get_metadata_tmpfile> \\
    --hashes '<existing_figma_frame_hashes_json>'

출력 (stdout JSON):
  {
    "current_frames": [{"nodeId", "name", "size", "width", "height", "is_screen"}],
    "new":     [{"nodeId", "name", "size"}],
    "deleted": [{"nodeId", "name_or_unknown"}],
    "new_hashes": {"nodeId": "new", ...}   // 기존 hashes에서 deleted 제거 + new 추가
  }

hash 계산은 get_design_context 응답이 있을 때만 가능하므로 스크립트는 diff 결과만 제공.
실제 hash 값은 LLM이 get_design_context 호출 후 별도 계산.
"""

import argparse
import json
import re
import sys
from pathlib import Path


def parse_canvas_children(metadata_path: str) -> list[dict]:
    """get_metadata 임시 파일에서 canvas 직계 자식 frame 추출."""
    raw = Path(metadata_path).read_text(encoding="utf-8")

    # 파일 포맷: [{"type": "text", "text": "<canvas ...>\n  <frame ...>"}]
    try:
        data = json.loads(raw)
        text = "".join(item.get("text", "") for item in data if isinstance(item, dict))
    except Exception:
        text = raw

    frames = []
    pattern = re.compile(
        r'^  <(?:frame|section) id="([0-9]+:[0-9]+)" name="([^"]*)"'
        r'[^>]*width="([0-9.]+)"[^>]*height="([0-9.]+)"',
        re.MULTILINE,
    )
    for m in pattern.finditer(text):
        node_id, name, w_str, h_str = m.groups()
        width = float(w_str)
        height = float(h_str)
        # 화면 판별: 표준 폰 너비(360~440) 또는 태블릿(600+), 세로 비율
        is_screen = (320 <= width <= 900) and (height >= width * 0.7)
        frames.append(
            {
                "nodeId": node_id,
                "name": name,
                "size": f"{int(width)}x{int(height)}",
                "width": int(width),
                "height": int(height),
                "is_screen": is_screen,
            }
        )
    return frames


def main() -> None:
    parser = argparse.ArgumentParser(description="Figma frame diff")
    parser.add_argument("--metadata", required=True, help="get_metadata 임시 파일 경로")
    parser.add_argument("--hashes", default="{}", help="기존 figma_frame_hashes JSON 문자열")
    args = parser.parse_args()

    try:
        old_hashes: dict[str, str] = json.loads(args.hashes)
    except Exception:
        old_hashes = {}

    current_frames = parse_canvas_children(args.metadata)
    current_ids = {f["nodeId"] for f in current_frames}
    old_ids = set(old_hashes.keys())

    new_frame_ids = current_ids - old_ids
    deleted_ids = old_ids - current_ids

    new_frames = [f for f in current_frames if f["nodeId"] in new_frame_ids]
    deleted_frames = [{"nodeId": nid, "name": "unknown"} for nid in deleted_ids]

    # 새 hashes: 기존 유지 + deleted 제거 + new 추가("new" 마커)
    new_hashes = {k: v for k, v in old_hashes.items() if k not in deleted_ids}
    for f in new_frames:
        new_hashes[f["nodeId"]] = "new"

    result = {
        "current_frames": current_frames,
        "new": new_frames,
        "deleted": deleted_frames,
        "new_hashes": new_hashes,
        "summary": {
            "total": len(current_frames),
            "new_count": len(new_frames),
            "deleted_count": len(deleted_ids),
            "unchanged_count": len(current_ids & old_ids),
        },
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
