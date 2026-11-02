"""Figma 프레임 PNG 위에 바뀐 부분을 빨간 사각형과 라벨로 표시하고, 여러 프레임을 한 장으로 합친다.

사용법:
    python3 annotate.py <spec.json>

spec.json (경로는 spec 파일 기준 상대 경로도 된다):
{
  "out_dir": "out",                 # 결과 PNG 디렉터리
  "scale": 2,                       # 내보낸 PNG 배율 (download_assets defaultScale)
  "frames": [
    {
      "name": "before",             # 결과 파일 이름 (before.png)
      "caption": "변경 전",          # 합본에서 프레임 위에 붙는 제목
      "image": "raw/before.png",    # 프레임 export PNG
      "metadata": "raw/before.xml", # get_metadata(프레임 노드) XML 원문. marks 에 node(s) 를 쓸 때 필요
      "marks": [
        {"node": "61:4161", "label": "제거", "dashed": true},
        {"between": ["61:4120", "61:4152"], "label": "간격·높이 변경"},
        {"nodes": ["61:4120", "61:4152"], "label": "두 요소 함께"},
        {"box": [24, 556, 312, 116], "label": "직접 지정"}
      ]
    }
  ],
  "notes": ["표시 설명 한 줄", "..."]  # 선택. 합본 아래에 목록으로 붙는다
}

- node: 노드 하나의 영역. nodes: 여러 노드를 모두 감싸는 영역.
- between: [위 노드, 아래 노드]. 위 노드의 아래 끝부터 아래 노드의 아래 끝까지(사이 간격 + 아래 노드).
  간격이나 높이 변화를 표시할 때 쓴다. 위 노드 자체는 사각형에 들어가지 않아 라벨이 그 글자를 가리지 않는다.
- box: 프레임 기준 Figma 1x 좌표 [x, y, w, h]. 노드가 없는 영역에만 쓴다.
- 좌표는 metadata XML 의 x, y 가 부모 기준이라는 점을 이용해 프레임 기준으로 합산한다.
결과: <out_dir>/<name>.png (프레임별), 프레임이 2개 이상이면 <out_dir>/compare.png.
표시한 사각형 좌표를 stdout 에 MARK: 줄로 남긴다.
"""
import json
import os
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

RED = (229, 25, 25)
STROKE = 5
PAD = 6  # Figma 1x 단위 여백
FONT_PATH = "/System/Library/Fonts/AppleSDGothicNeo.ttc"


def font(size, bold=True):
    for idx in ((6, 0) if bold else (0,)):
        try:
            return ImageFont.truetype(FONT_PATH, size, index=idx)
        except OSError:
            continue
    return ImageFont.load_default()


def node_boxes(xml_path):
    """노드 id -> 프레임 기준 (x, y, w, h). 루트(프레임)는 (0, 0) 으로 본다."""
    root = ET.parse(xml_path).getroot()
    boxes = {}

    def walk(el, ox, oy, is_root):
        x = 0.0 if is_root else ox + float(el.get("x", 0))
        y = 0.0 if is_root else oy + float(el.get("y", 0))
        if el.get("id"):
            boxes[el.get("id")] = (x, y, float(el.get("width", 0)), float(el.get("height", 0)))
        for child in el:
            walk(child, x, y, False)

    walk(root, 0.0, 0.0, True)
    return boxes


def union(rects):
    l = min(r[0] for r in rects)
    t = min(r[1] for r in rects)
    r_ = max(r[0] + r[2] for r in rects)
    b = max(r[1] + r[3] for r in rects)
    return (l, t, r_ - l, b - t)


def resolve_box(mark, boxes):
    if "box" in mark:
        return tuple(mark["box"])
    if "between" in mark:
        above, below = mark["between"]
        for i in (above, below):
            if i not in boxes:
                sys.exit(f"[오류] metadata 에 없는 노드: {i}")
        a, b = boxes[above], boxes[below]
        top = a[1] + a[3]
        l = min(a[0], b[0])
        r = max(a[0] + a[2], b[0] + b[2])
        return (l, top, r - l, b[1] + b[3] - top)
    ids = mark.get("nodes") or [mark["node"]]
    missing = [i for i in ids if i not in boxes]
    if missing:
        sys.exit(f"[오류] metadata 에 없는 노드: {missing}")
    return union([boxes[i] for i in ids])


def dashed_rect(d, l, t, r, b):
    dash, gap = 18, 10
    for x in range(int(l), int(r), dash + gap):
        d.line([x, t, min(x + dash, r), t], fill=RED, width=STROKE)
        d.line([x, b, min(x + dash, r), b], fill=RED, width=STROKE)
    for y in range(int(t), int(b), dash + gap):
        d.line([l, y, l, min(y + dash, b)], fill=RED, width=STROKE)
        d.line([r, y, r, min(y + dash, b)], fill=RED, width=STROKE)


def annotate(frame, scale, base):
    img = Image.open(os.path.join(base, frame["image"])).convert("RGB")
    W, H = img.size
    boxes = node_boxes(os.path.join(base, frame["metadata"])) if frame.get("metadata") else {}
    d = ImageDraw.Draw(img)
    f = font(13 * scale)
    half = STROKE // 2
    for m in frame.get("marks", []):
        x, y, w, h = resolve_box(m, boxes)
        l = max((x - PAD) * scale, half)
        t = max((y - (2 if "between" in m else PAD)) * scale, half)
        r = min((x + w + PAD) * scale, W - 1 - half)
        b = min((y + h + PAD) * scale, H - 1 - half)
        if m.get("dashed"):
            dashed_rect(d, l, t, r, b)
        else:
            d.rectangle([l, t, r, b], outline=RED, width=STROKE)

        label = m.get("label")
        if label:
            tb = d.textbbox((0, 0), label, font=f)
            tw, th = tb[2] - tb[0], tb[3] - tb[1]
            px, py = 6 * scale, 4 * scale
            lw, lh = tw + px * 2, th + py * 2
            # 라벨은 사각형 오른쪽 위 모서리에 걸쳐 두어 표시한 내용을 가리지 않게 한다.
            lx = max(r - lw, 0)
            ly = t - lh // 2
            if ly < 0:
                ly = t
            d.rectangle([lx, ly, lx + lw, ly + lh], fill=RED)
            d.text((lx + px - tb[0], ly + py - tb[1]), label, font=f, fill="white")
        print(f"MARK: {frame['name']} {label!r} figma={tuple(round(v, 1) for v in (x, y, w, h))} px={(round(l), round(t), round(r), round(b))}")
    return img


def compose(imgs, captions, notes, scale):
    gap, margin = 20 * scale, 20 * scale
    cf = font(22 * scale)
    nf = font(14 * scale, bold=False)
    cap_h = 44 * scale if any(captions) else 0
    note_line = 24 * scale
    notes_h = (len(notes) * note_line + margin) if notes else 0
    w = sum(i.width for i in imgs) + gap * (len(imgs) - 1) + margin * 2
    h = max(i.height for i in imgs) + cap_h + notes_h + margin * 2
    canvas = Image.new("RGB", (w, h), "white")
    d = ImageDraw.Draw(canvas)
    x = margin
    top = margin + cap_h
    for img, cap in zip(imgs, captions):
        if cap:
            tb = d.textbbox((0, 0), cap, font=cf)
            d.text((x + (img.width - (tb[2] - tb[0])) // 2 - tb[0], margin), cap, font=cf, fill="black")
        canvas.paste(img, (x, top))
        d.rectangle([x - 1, top - 1, x + img.width, top + img.height], outline=(200, 200, 200), width=1)
        x += img.width + gap
    y = top + max(i.height for i in imgs) + margin
    for n in notes:
        d.text((margin, y), f"• {n}", font=nf, fill=(60, 60, 60))
        y += note_line
    return canvas


def main():
    spec_path = os.path.abspath(sys.argv[1])
    base = os.path.dirname(spec_path)
    spec = json.load(open(spec_path, encoding="utf-8"))
    scale = spec.get("scale", 2)
    out_dir = os.path.join(base, spec.get("out_dir", "out"))
    os.makedirs(out_dir, exist_ok=True)
    imgs = []
    for frame in spec["frames"]:
        img = annotate(frame, scale, base)
        path = os.path.join(out_dir, f"{frame['name']}.png")
        img.save(path)
        print(f"OUTPUT: {path}")
        imgs.append(img)
    if len(imgs) > 1 or spec.get("notes"):
        canvas = compose(imgs, [fr.get("caption", "") for fr in spec["frames"]], spec.get("notes", []), scale)
        path = os.path.join(out_dir, "compare.png")
        canvas.save(path)
        print(f"OUTPUT: {path}")


if __name__ == "__main__":
    main()
