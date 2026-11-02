---
name: annotate-figma-design
description: Figma 시안에서 바뀐 부분을 표시한 이미지(PNG)가 필요할 때 사용한다. PR 본문의 디자인 화면, 변경 전·후 시안 비교, A안·B안 비교가 대상이다. 사용자가 'annotate-figma-design', '시안에 바뀐 부분 표시해줘', '디자인 화면 이미지 만들어줘', 'Figma 변경점 이미지', '시안 비교 이미지' 등을 Figma 링크와 함께 요청하거나, `create-pr`가 디자인 화면 이미지를 요청할 때 이 스킬을 사용한다. 코드 구조를 설명하는 그림은 `illustrate-concept`, 앱 화면 캡처는 `capture-preview-screenshot`·`verify-on-device`, 업로드는 `upload-pr-image`를 사용한다.
---

# Figma 시안 변경점 이미지

Figma 프레임을 PNG로 내보내고, 바뀐 부분에 빨간 사각형과 라벨을 그린 뒤, 여러 프레임을 캡션과 함께 한 장으로 합친다. 표시와 합본은 `scripts/annotate.py`가 맡는다. 매번 그리기 스크립트를 새로 짜지 않는다.

이 스킬의 책임은 **PNG를 만들어 눈으로 검증하는 데까지**다. 업로드와 PR 본문 수정은 호출한 쪽이 맡는다.

## 절차

작업 디렉터리 `<dir>`은 세션 scratchpad 아래에 새로 만든다. 작업 저장소 안에는 만들지 않는다.

1. **프레임과 변경점을 정한다.** 비교할 프레임 노드 ID(URL의 `node-id=61-3968` → `61:3968`)와, 프레임마다 표시할 변경점 목록을 정한다. 변경점이 주어지지 않았으면 두 프레임의 `get_metadata`를 비교해 찾는다. 표시 대상은 **화면에 보이는 변화**뿐이다. 레이어 구조만 바뀌고 위치·크기가 같은 노드, `hidden="true"` 노드는 표시하지 않는다. 글자 크기·색처럼 metadata에 없는 값을 `notes`에 적을 때만 `get_design_context`를 호출한다.

2. **프레임마다 두 파일을 받는다.** `create_session`을 먼저 호출한다.
   - `download_assets`(`defaultFormat: "png"`, `defaultScale: 2`)의 `export.url`을 `curl -f -L -o <dir>/raw/<이름>.png "<url>"`로 바로 받는다. URL은 금방 만료된다. SVG 자산이 20개를 넘는다는 경고는 `export`와 무관하므로 무시한다.
   - `get_metadata`(프레임 노드)의 XML 원문을 Write로 `<dir>/raw/<이름>.xml`에 그대로 저장한다. 좌표 합산은 스크립트가 하므로 직접 계산하지 않는다.

3. **spec.json을 쓴다.** 형식은 `scripts/annotate.py` 맨 위 docstring에 있다. 표시 하나는 아래 중 하나로 고른다.

   | 표시할 것 | 키 |
   |---|---|
   | 요소 하나가 추가·변경·제거됨 | `node` |
   | 위아래 간격이나 높이가 바뀜 | `between: [위 노드, 아래 노드]` |
   | 여러 요소를 한 덩어리로 묶음 | `nodes` |
   | 노드로 잡을 수 없는 영역 | `box` (프레임 기준 1x 좌표) |

   - 제거된 요소는 `"dashed": true`로 점선을 쓴다.
   - 라벨은 무엇이 바뀌었는지 10자 안팎으로 쓴다(`제거`, `설명 문구 추가(B안)`, `간격 24 · 높이 48`). 수치·토큰 같은 긴 설명은 `notes`에 한 줄씩 쓴다.
   - 캡션은 `변경 전`, `변경 후`, `A안`, `B안`처럼 프레임이 무엇인지 쓴다.

4. **실행한다.**

   ```bash
   python3 ~/.claude/skills/annotate-figma-design/scripts/annotate.py <dir>/spec.json
   ```

   `OUTPUT:` 줄이 결과 PNG(프레임별, 2장 이상이면 `compare.png`)이고, `MARK:` 줄이 각 사각형의 좌표다. `[오류] metadata 에 없는 노드`가 나오면 노드 ID나 저장한 XML을 확인한다.

5. **눈으로 검증한다.** `compare.png`(프레임이 하나면 그 PNG)를 Read로 열어 본다.
   - 사각형이 각 변경 요소에 맞게 얹혔는가
   - 라벨이 표시한 내용이나 다른 글자를 가리지 않는가
   - 바뀐 부분이 빠짐없이 표시됐는가

   어긋나면 spec.json의 표시 종류나 노드를 고쳐 4번부터 다시 한다. 스크립트를 고치지 않는다.

6. **전달한다.** PNG 절대 경로를 별도 라인에 출력하고, 프레임마다 Figma 링크(`https://www.figma.com/design/<fileKey>/?node-id=<id>`)를 함께 적는다. PR에 넣는다면 호출한 쪽이 `upload-pr-image`로 URL을 받아 `<img width="720" src="...">`로 넣는다.

## Common Mistakes

| 실수 | 결과 | 대신 |
|---|---|---|
| `get_screenshot` 이미지로 표시한다 | 1배율이라 글자가 흐리고 좌표 배율이 어긋난다 | `download_assets` + `defaultScale: 2` |
| metadata의 x, y를 프레임 좌표로 바로 쓴다 | x, y는 부모 기준이라 사각형이 위로 밀린다 | XML을 저장해 `node`로 넘긴다 |
| 간격 변화를 `nodes: [위, 아래]`로 묶는다 | 위 요소까지 감싸 라벨이 그 글자를 가린다 | `between` |
| 그리기 스크립트를 새로 짠다 | 시간이 들고 표시 형식이 매번 달라진다 | `annotate.py` + spec.json |
| 결과 PNG를 열어 보지 않고 전달한다 | 어긋난 사각형이 그대로 PR에 올라간다 | 5번 검증 |
