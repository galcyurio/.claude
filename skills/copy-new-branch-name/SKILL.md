---
name: copy-new-branch-name
effort: low
description: 새로 만들 브랜치의 이름이 필요할 때 사용한다. 사용자가 'copy-new-branch-name', '브랜치 이름', '브랜치명', '새 브랜치 이름', '브랜치 이름 만들어', '브랜치명 추천', '브랜치 이름 복사', '브랜치 뭐로 할까' 등을 Jira 이슈와 함께 언급할 때 이 스킬을 사용해야 한다. 브랜치·worktree를 실제로 만드는 요청에는 `create-worktree`, develop 반영 브랜치에는 `merge-develop`을 사용한다.
argument-hint: "[Jira 이슈 키 또는 URL]"
---

# 새 브랜치 이름 복사

## Overview

Jira 이슈 하나를 받아 **새로 만들 브랜치에 붙일 이름**을 정하고 클립보드에 넣는다.

이름을 정하는 것이 이 스킬의 전부다. 브랜치는 만들지 않고, 리포지토리 상태도 진단하지 않는다. 이름은 이슈 하나만으로 결정되므로 리포지토리를 볼 이유가 없다.

## 출력 계약

답변은 아래 템플릿을 채운 것이다. 채울 슬롯은 `{의도}`와 `{브랜치}` 둘뿐이고, 줄 순서도 템플릿 그대로다 — `[의도: ...]` 다음 줄은 곧바로 ```sh 펜스다.

````markdown
[의도: {의도}]

```sh
git checkout -b {브랜치}
```

```text
{브랜치}
```

클립보드에 복사했습니다.
````

이슈 유형을 어떻게 판별했는지, slug를 어디서 뽑았는지, 앱 이름을 왜 뺐는지는 이 템플릿에 슬롯이 없다. 사용자가 물으면 다음 턴에 답한다.

## 절차

### 1. 이슈 키 확정

인자에서 키(`HDA-19432`)를 읽는다. 브라우즈 URL이면 마지막 경로 세그먼트가 키다. 키가 여러 개면 각각 출력 계약을 반복한다. 인자가 없으면 `AskUserQuestion`으로 묻는다.

### 2. 이슈 조회

`mcp__claude_ai_Atlassian__getJiraIssue`

- `cloudId`: `4e8e1a3d-2b6f-40df-820b-43c476f41656` (`prndcompany.atlassian.net`)
- `issueIdOrKey`: 확정한 키
- `fields`: `["summary", "issuetype"]`

조회 실패 시 원인을 보고하고 중단한다. 제목 없이는 slug를 만들 수 없다.

### 3. prefix 결정

`issuetype.hierarchyLevel`로 판별한다. **`issuetype.name`은 한글이다** (`에픽`, `작업`, `하위 작업`) — `"Epic"` 같은 영어로 비교하면 매칭에 실패한다.

| `hierarchyLevel` | 유형 | prefix |
|---|---|---|
| `0` | 작업 · 하위 작업 · 버그 | `feature` |
| `1` 이상 | 에픽 · Feature | `feature-base` |

### 4. slug 원문 추출

**`summary`가 slug의 유일한 출처다.** 기존 브랜치 이름, 코드 식별자, 클래스명에서 가져오지 않는다.

| 유형 | 쓸 부분 | 예 |
|---|---|---|
| 에픽 | 마지막 대괄호 그룹의 **내용** | `[고객][zero 비율 높이기]` → `zero 비율 높이기` |
| 작업 | 대괄호 그룹을 **전부** 걷어낸 뒤 남는 문구 | `[고객][zero 이용료 도입] 부가세 안내 dialog 추가` → `부가세 안내 dialog 추가` |

작업인데 대괄호를 걷어내면 아무것도 남지 않을 때만 에픽 규칙으로 폴백한다.

### 5. slug 작성

추출한 한글을 짧은 영어 kebab-case로 옮긴다.

- **작업(`feature`) slug는 동사로 시작한다** — `add`, `fix`, `show`, `rename`, `connect`, `move`, `refresh`, `separate`. 작업 제목은 행위를 서술하므로 그 행위가 slug의 첫 단어다.
- **에픽(`feature-base`) slug는 명사구다.** 에픽 이름에 행위가 들어 있어도 명사형으로 옮긴다 — `효율화` → `optimization`, `마이그레이션` → `migration` (`optimize`·`migrate`가 아니다).
- 전부 소문자, 단어 구분은 하이픈.
- 제목을 옮기지 말고 **핵심 하나**로 줄인다. 부연 설명은 slug에 넣지 않는다.
- 앱 이름(`고객`, `딜러`, `리볼트`, `평가사`, `공통`)은 어떤 형태로도 넣지 않는다.
- 에픽 이름도 작업 브랜치에 넣지 않는다. 어느 에픽 소속인지는 브랜치 이름의 역할이 아니다.
- 제품명·고유명사(`zero`, `c2b`)는 소문자로 그대로 남긴다.

이슈 키는 **대문자 그대로** 둔다. 최종 형태는 `{prefix}/{이슈키}-{slug}`.

### 6. 클립보드 복사

브랜치 이름만, 개행 없이 복사한다.

```bash
printf '%s' 'feature/HDA-19432-add-vat-info-dialog' | pbcopy
```

### 7. 출력

위 **출력 계약** 그대로 낸다.

## 이름 예시

| 이슈 | 유형 | 브랜치 |
|---|---|---|
| `HDA-16964 [고객][zero 비율 높이기]` | 에픽 | `feature-base/HDA-16964-zero` |
| `HDA-19875 [고객][내차사기 예약금 환불 효율화]` | 에픽 | `feature-base/HDA-19875-deposit-refund-optimization` |
| `HDA-22279 [고객][내차사기 리스트 디자인시스템 공통화]` | 에픽 | `feature-base/HDA-22279-car-list-design-system` |
| `HDA-19432 [고객][zero 이용료 도입] 부가세 안내 dialog 추가` | 작업 | `feature/HDA-19432-add-vat-info-dialog` |
| `HDA-19910 [고객][내차사기 예약금 환불 효율화] B안 예약금 환급 계좌 UI에 계좌정보 확인 API 연동` | 작업 | `feature/HDA-19910-connect-account-verification-api` |
| `HDA-22339 [고객][내차사기 리스트 디자인시스템 공통화] MarketPriceText를 라이브러리로 이동` | 작업 | `feature/HDA-22339-move-price-text-to-library` |

마지막 두 줄이 길이 감각의 기준이다. HDA-19910의 원문은 `B안`과 `예약금 환급 계좌 UI`까지 담고 있지만 브랜치는 핵심 행위(`계좌정보 확인 API 연동`) 하나로 줄었다.

## 흔한 실패

베이스라인 테스트에서 실제로 나온 것들이다.

| 나온 결과 | 문제 | 대신 |
|---|---|---|
| 기존 `feature-base/HDA-22279-car-list-design-system`에서 slug를 베낌 | 우연히 맞을 수 있지만 규칙을 거치지 않는다. 브랜치가 없는 이슈에서는 재현되지 않는다 | `summary`에서 도출한다 |
| 결과 클래스명 `PurchaseCarPriceText` → `purchase-car-price-text` | 코드 식별자에는 행위가 없어 동사가 사라진다 | 제목의 `~를 라이브러리로 이동` → `move-price-text-to-library` |
| base 브랜치·미push 커밋·서브모듈 상태까지 조사해 보고 | 이름은 이슈만으로 결정된다. 90초와 90k 토큰을 썼다 | 2~7단계만 밟는다 |
| "브랜치가 이미 있다"며 해석 3갈래를 제시 | 이름을 달라는 요청에 이름이 없다 | 이슈 유형대로 이름 하나를 낸다 |

## 하지 않는 것

- 브랜치를 만들지 않는다. `git checkout -b`는 사용자가 복사해 쓰도록 문자열로만 낸다. 실제 생성은 `create-worktree`가 맡는다.
- 어느 base에서 분기할지 안내하지 않는다.
- `merge/HDA-xxxx`는 다루지 않는다. develop 반영은 `merge-develop`이 맡는다.
