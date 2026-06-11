# Figma frame 추적 (feature-memory STEP 2.3 상세)

> SKILL.md STEP 2.3 "5 소스 병렬 dispatch"의 Figma 소스 상세 절차. 본문은 요약만 두고 전체 절차는 여기 둔다.

분류된 Figma URL 각각을 fileKey+nodeId로 파싱. 페이지 단위 nodeId는 `get_design_context`가 항상 실패(`선택된 레이어 없음`)하므로 **frame 단위로 우회**한다.

## 1단계 — frame 목록 추출 + diff

`mcp__claude_ai_Figma__get_metadata(fileKey, page_nodeId)` 호출. 응답은 수십만 자로 token limit 초과하지만 도구가 자동으로 임시 파일에 저장한다 (응답 메시지에 파일 경로 포함). 그 임시 파일과 기존 `figma_frame_hashes`를 **`figma-diff.py` 스크립트에 전달**해 frame 추출 + diff를 한 번에 수행한다:

```bash
python3 ~/.claude/skills/feature-memory/figma-diff.py \
  --metadata <임시파일경로> \
  --hashes '<figma_frame_hashes_json>'
```

출력 JSON 구조:
```json
{
  "current_frames": [{"nodeId", "name", "size", "is_screen"}],
  "new":     [{"nodeId", "name", "size"}],
  "deleted": [{"nodeId"}],
  "new_hashes": {"nodeId": "기존hash_or_new"},
  "summary": {"total", "new_count", "deleted_count", "unchanged_count"}
}
```

`is_screen=true`인 것이 화면, `false`인 것이 부품·에셋. LLM은 이 결과만 받아서 표 구성과 변경 이력 작성에 집중한다.

각 줄은 `nodeId|name|WxH` 형태 (표 구성 시 참고). frame 목록 표로 정리해 본문 `## 📚 Reference`의 `Figma frame 목록` toggle에 부착. 각 frame은 `https://www.figma.com/design/{fileKey}/?node-id={nodeId_with_dash}` (콜론을 대시로 변환) 형식의 클릭 링크.

**frame 목록 표는 매 갱신 시 get_metadata 결과로 전량 재생성한다** (직전 표에 누적 prepend 금지). 1단계는 페이지당 `get_metadata` 1회라 비용이 낮으므로 `__skip__` 여부와 무관하게 **항상 수행**한다. 직전 목록·`figma_frame_hashes`에는 있으나 이번 결과에 없는 nodeId는 **유령 frame**(Figma에서 삭제·이동됨)이므로 표와 hash dict에서 즉시 제거한다. 표가 stale해져 존재하지 않는 frame이 잔존하면 이를 참조하는 review-by-agents 등 하위 소비자가 헛도므로 신선도 유지가 중요하다.

**frame 이름은 Figma name 원문 그대로 쓴다.** 동명 frame이 여럿이어도 `한화면`·`(2)`·`신규` 같은 임의 suffix를 붙이지 않는다 — 구별은 표의 별도 nodeId 칼럼으로 한다 (Figma에서 "홈_최초" 같은 이름이 여러 frame에 중복되는 경우가 흔하다). 이름 기반으로 frame을 참조하는 소비자가 임의 suffix 때문에 매칭에 실패하는 것을 막는다.

**frame 목록을 `화면`과 `부품·에셋` 두 그룹으로 분리한다.** 페이지 직계 자식에는 화면 시안과 부분 컴포넌트(카드·버튼·배너 이미지 등)가 섞여 있다. 분류 가이드:
- **화면**: 너비가 표준 디바이스 폭(폰 ≈360~440, 태블릿 ≈600 이상)이고 세로로 긴(높이 ≥ 너비) frame.
- **부품·에셋**: 너비 < 320, 가로형(높이 < 너비), 정사각에 가깝거나, 이름이 카드/이미지/버튼 등 부분 요소인 frame.

너비만으로 카드(예: 352)와 폰 화면(예: 360·393)을 완벽히 가를 수는 없으므로 크기 가이드 + 이름 휴리스틱으로 판단하되, 애매하면 `부품·에셋`에 둔다. 두 그룹 모두 표에 남기되(정보 보존) Reference에서 별도 표로 분리해 화면을 우선 노출한다. review-by-agents 등 화면 매칭 소비자는 `화면` 표만 대상으로 삼을 수 있다.

## 2단계 — frame별 디자인 컨텍스트 incremental fetch (hash diff)

Figma API는 `last_modified`를 제공하지 않으므로 **응답 코드 hash 비교 방식**으로 변경 감지를 구현한다.

1. 1단계에서 얻은 모든 frame nodeId에 대해 `mcp__claude_ai_Figma__get_design_context(fileKey, frame_nodeId, excludeScreenshot=true)`를 **병렬 호출**한다 (응답 크기를 줄이기 위해 스크린샷 제외).
2. 각 응답의 React 코드 문자열에서 변동성 높은 부분(`data-node-id` 속성값, `https://www.figma.com/api/mcp/asset/...` asset URL — asset URL은 7일마다 재발급되므로 hash에 포함하면 항상 변경으로 잡힘)을 정규식으로 제거한 뒤 SHA-256 해시 계산:
   ```bash
   echo "$response_code" \
     | sed -E 's| data-node-id="[^"]*"||g; s|https://www\.figma\.com/api/mcp/asset/[a-f0-9-]+|ASSET|g' \
     | shasum -a 256 | awk '{print $1}'
   ```
3. page property `figma_frame_hashes` (JSON 문자열: `{"nodeId": "hash", ...}`)에서 직전 hash dict 로드. property가 비어 있으면 `{}`로 초기화.
4. 각 frame에 대해 hash 비교:
   - 신규 frame (직전 dict에 없음) → `## 변경 이력`에 `- (YYYY-MM-DD) · [Figma](url) · 신규 frame 추가 — "{name}" (WxH)` prepend
   - hash 변경 → `## 변경 이력`에 `- (YYYY-MM-DD) · [Figma](url) · frame 디자인 변경 — "{name}"` prepend
   - hash 동일 → 본문에 반영하지 않음
5. 1단계에서 더 이상 보이지 않는 frame (직전 dict에는 있는데 새 목록에 없음) → 위 1단계에서 표·hash dict에서 이미 제거된 항목이다. `## 변경 이력`에 `- (YYYY-MM-DD) · [Figma](url) · frame 삭제 — "{name}"` prepend한다. 이 비교는 frame 목록만으로 가능하므로 2단계를 `__skip__`해도 수행한다.
6. 새 hash dict를 JSON 직렬화하여 STEP 5에서 `figma_frame_hashes` property에 저장.
7. Reference의 `Figma frame 목록` 표에서 변경된 frame은 이름 앞에 🔄 마커를 붙여 시각적으로 구분한다 (`🔄 관심 차 가격 변동`).

## 3단계 — 변경된 frame의 디자인 컨텍스트를 Reference에 보존

위에서 `신규/변경`으로 식별된 frame들의 응답 코드(asset URL 정리 전)를 본문 `## 📚 Reference`의 `Figma 디자인 컨텍스트 (최근 변경)` toggle에 저장. 형식:

~~~markdown
<details>
<summary>Figma 디자인 컨텍스트 (최근 변경)</summary>

### 🔄 {frame_name} ({nodeId})

변경 감지: {YYYY-MM-DD}, asset 유효 기한 ~7일

```tsx
{React+Tailwind 코드}
```

스타일 토큰: {색상/폰트 요약}
</details>
~~~

## 비용 제어

비싼 단계는 2단계(frame별 `get_design_context` + hash 계산)다. `figma_frame_hashes`가 `__skip__`으로 설정되면 **2단계만 skip**하고 **1단계 `get_metadata` + frame 목록 표 재생성은 항상 수행**한다 (유령 frame 방지를 위해 표 신선도는 비용 제어와 무관하게 유지). frame 수가 30개를 초과해 2단계 비용이 부담될 때 활용한다.

## 실패 처리

- 1단계(`get_metadata`) 실패 → 모든 frame 처리 skip, `## 데이터 소스 상태`에 ⚠️ 기록
- 2단계 일부 frame `get_design_context` 실패 → 해당 frame은 직전 hash 유지하고 다른 frame은 정상 처리
- 전체 실패 → `## 한눈에 보기`의 Figma 링크만 유지하고 `## 데이터 소스 상태`에 ⚠️ 1줄 기록
