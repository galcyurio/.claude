---
name: order-jira-issues
description: Jira 이슈들의 blocks·blocked by 관계를 정리하고 지금 착수할 이슈를 고를 때 사용한다. 사용자가 'order-jira-issues', '이슈 관계 보여줘', '차단 관계', 'blocked by 정리', '뭐부터 해야 해', '작업 순서', '지금 뭐 진행할까', '같이 진행할 수 있는 거 있어', '병렬로 할 수 있는 거', '막혀 있는 이슈', '남은 작업 순서' 등을 물을 때 이 스킬을 사용해야 한다. 이슈를 새로 만들거나 쪼개거나 링크를 거는 요청에는 `plan-feature-issues`를 사용한다.
---

# Jira 이슈 순서 파악

## Overview

에픽 하위 이슈의 blocks 그래프를 뽑아 **지금 착수 가능한 것**과 **무엇에 막혀 있는지**를 보고한다.

**핵심 원칙: 그래프는 스크립트가 뽑고, 사람이 필요한 판단만 직접 한다.** Jira 링크는 보수적으로 걸려 있는 경우가 많아 링크만 읽으면 "할 게 없다"는 오답이 나온다.

## 언제 쓰지 않나

- 이슈 생성·분해·링크 설정 → `plan-feature-issues`
- 단일 이슈 내용 조회 → 그냥 `getJiraIssue`

## 절차

### 1. 그래프를 뽑는다 — 한 번의 호출로

```bash
python3 ~/.claude/skills/order-jira-issues/jira-deps.py HDA-22517
```

에픽이 아닌 대상은 `--jql "project = HDA AND labels = foo"`로 넘긴다.

Wave 레이어 그래프·착수 가능·대기·임계 경로·이상 징후를 한 번에 낸다. **이슈를 하나씩 조회해 손으로 그래프를 맞추지 않는다** — 그렇게 하면 12건짜리 에픽에 14회 호출과 12만 토큰이 든다(실측).

그래프는 이렇게 나온다. 의존 깊이별로 Wave 를 끊고, 노드 오른쪽에 blocks 대상을, 아래에 남은 blocker 를 붙인다.

```
Wave 1 ─ 지금 착수 가능 (병렬 2)
  🟠 HDA-22530  모델 검색 API 연동 (진행 중) *             ─┬─▶ HDA-22554
                                                            └─▶ HDA-22561
  🟢 HDA-22538  퀵링크 DTO 추가                            ───▶ HDA-22554

Wave 2 ─ Wave 1 이후 (2건)
  ⛔ HDA-22554  MarketCarList 에 모델 퀵링크를 연결한다 *  ───▶ HDA-22570
       ▲ HDA-22530, HDA-22538
```

읽는 법:

- `Wave 1` 은 링크상 지금 열려 있는 것이다. 같은 Wave 안은 병렬 후보다.
- `*` 는 임계 경로 위, `▲` 는 아직 안 풀린 blocker, `(?)` 는 조회 실패한 blocker다.
- `(에픽 밖)` 노드는 내 이슈가 아니다. Wave 병렬 건수에도 세지 않는다.
- `순환` 블록이 나오면 blocks 링크가 서로를 물고 있다는 뜻이다 — 링크를 고쳐야 한다.

### 2. 실제 진행 상태를 교차 확인한다

Jira 상태는 늦게 따라온다. 열린 이슈들의 실제 코드 쪽을 확인한다.

```bash
gh pr list --state all --search "HDA-22554 in:title" --json number,state,headRefName,mergedAt
git ls-remote --heads origin "feature/HDA-22554*"
```

**`in:title`을 빼면 오탐이 난다.** 검색어가 PR 본문에도 걸려서, `HDA-22538`로 찾으면 "HDA-22538에서 다룬다"고 적힌 다른 이슈의 PR이 나온다. 이미 된 줄 착각하게 만든다. PR이 정말 없는지 확인할 때만 `in:title` 없이 한 번 더 본다.

읽는 법:

- PR이 머지됐는데 이슈가 Backlog → 그래프가 실제보다 비관적이다.
- 브랜치가 원격에 없다 → 아직 push 전. 그 이슈에 막힌 것들은 당분간 안 열린다.
- **브랜치가 원격에 있고 PR이 열려 있다 → 그 위에 스택해서 지금 착수 가능으로 본다.** 머지를 기다릴 이유가 없다. 다만 리뷰에서 API가 바뀔 수 있다는 점을 함께 말한다.

### 3. 링크상 막혀 있어도 실제로 가능한 것을 찾는다

스크립트는 링크에 적힌 것만 본다. **링크가 실제보다 보수적으로 걸려 있는 경우를 잡는 것이 이 단계의 몫이다.**

대기 목록을 그대로 옮겨 적지 않는다. 각 대기 이슈에 묻는다: *blocker가 만드는 산출물을 정말 쓰나, 아니면 파일이 겹치지 않아 지금 시작해도 되나?*

**근거는 코드로 확인한다.** 두 가지가 특히 잘 듣는다.

```bash
# 이 에픽이 실제로 얹은 것만 본다. 원래 develop에 있던 것을 에픽 산출물로 오인하는 것을 막는다.
git diff --stat origin/develop...origin/feature-base/HDA-22517-market-home-model-search

# 후속 이슈 번호를 심어둔 TODO 마커. 마커가 있는 파일이 곧 그 이슈의 작업 대상이자 실제 선행 조건의 증거다.
git grep -n "TODO(HDA-22538)" origin/feature-base/HDA-22517-market-home-model-search
```

근거 없이 "아마 될 것 같다"고 말하지 않는다. 같은 파일을 고치는 두 이슈는 병렬 후보가 아니다 — 충돌한다고 분명히 말한다.

링크가 과했다면 어느 링크를 어디로 바꿔야 하는지까지 짚고, 고칠지 묻는다.

### 4. 보고한다

순서대로:

1. **지금 착수할 것 하나** — 여러 개면 임계 경로 위의 것을 먼저 고른다
2. **병렬 후보** — 있으면 근거와 함께, 없으면 "없다"
3. **그래프** — 스크립트가 낸 `## 그래프` 블록을 **코드블록에 그대로** 붙인다. 요약해서 다시 쓰지 않는다. 정렬이 폭 계산에 맞춰져 있으므로 코드블록 밖에 두면 어긋난다. 이슈 키 링크(`https://prndcompany.atlassian.net/browse/KEY`)는 코드블록 안에서 렌더되지 않으니 1·2번 항목에서 건다
4. **이상 징후** — 스크립트가 짚은 것

## acli 함정

베이스라인 테스트에서 실제로 걸린 것들이다. 스크립트를 안 쓰고 직접 조회할 때만 필요하다.

| 하려던 것 | 결과 | 대신 |
|---|---|---|
| MCP `searchJiraIssuesUsingJql`로 `issuelinks` 받기 | 응답이 잘리는데 `hasNextPage: false`, `endCursor: null` — 페이징 불가 | 키만 받고 이슈별로 `view` |
| `fields`를 줄여 응답 축소 | `description`은 요청 안 해도 항상 붙는다 | 위와 동일 |
| `acli workitem search --fields "...,issuelinks"` | `✗ Error: field 'issuelinks' is not allowed` | `acli workitem view KEY --fields "...,issuelinks" --json` |
| `acli workitem search --fields "key" --json` | `[null, null, ...]` | `acli workitem search --csv` |
| `acli workitem link list --json` 파싱 | 배열 키가 `links`가 아니라 `issueLinks` | `d["issueLinks"]` |
| `acli workitem link delete --json` | `unknown flag: --json` | `--id ID --yes` (출력은 텍스트) |

## 흔한 실수

- **상태 이름으로 완료를 판정한다.** `종료`·`Ready to Deploy`·`Deployed`가 뒤섞여 있다. `status.statusCategory.key == "done"`으로 본다.
- **완료된 blocker를 blocker로 센다.** 완료 이슈가 무언가를 blocks 하는 것은 정상 이력이다. 막고 있는 것으로 치지 않는다.
- **종료된 이슈에 남은 링크를 그래프에 넣는다.** 대기 목록이 실제보다 길어 보인다.
- **임계 경로를 빼먹는다.** 어느 이슈가 병목인지가 "다음에 뭘 할까"의 답이다.
- **그래프를 말로 풀어 요약한다.** 구조는 그림으로 봐야 빠르다. 스크립트 출력을 그대로 붙이고, 해석만 덧붙인다.
