# fast-path 판정 상세 (review-by-agents 3단계 3-0)

`SKILL.md` 3단계 **3-0**에서 참조하는 저위험 변경 fast-path의 트랙별 조건·게이트·출력 형태다. 3-0은 "기본은 3-A fan-out, 아래 트랙 조건을 전부 충족할 때만 생략"까지만 인라인으로 두고, 판정에 진입할 때 이 파일을 Read한다.

fast-path는 **3-A 코드 리뷰 fan-out만** 대체한다. 2단계 외부 링크/컨텍스트 수집과 3-B 디자인 리뷰는 그대로 수행한다(상세: 3-0 인라인).

## 공통 조건 (두 트랙 모두 AND)

- 보안 표면이 사실상 0 — auth/인가·crypto·injection·secret·파일 IO·신뢰 못 할 외부 입력 파싱이 없다. 있으면 fast-path 무효(정규 3-A — Code Reviewer가 보안까지 검토).
- 레포/PR head 조회가 가능하다(불가 시 무효).

## Track A — 기계적 제거/리네임

**적용 조건 (전부 AND)**:

- 변경이 기계적이다 — 필드 제거/리네임, 시그니처 일괄 변경, import/패키지 정리 등. 제거·리네임에 **수반된 널 처리(`?.let`, `?: default`)와 동일 계산식의 피연산자 리네임**을 제외하고, **새 비즈니스 로직·분기·계산식 도입이 없다.**
- 실질 리스크가 "제거/리네임된 심볼의 잔존 참조 → 컴파일/빌드 깨짐"으로 환원된다.
- 동작이 바뀌는 지점이 소수(≤3)이고, 각 지점이 diff만으로 자명하다.

**강제 게이트**:

- PR head 커밋을 `git fetch` 후 제거/리네임된 심볼을 `git grep`(또는 레포 전역 grep)으로 조회해 **잔존 참조 0건**을 확인한다. **로컬 작업 브랜치가 아니라 PR head 기준**으로 grep한다(로컬은 다른 브랜치일 수 있어 오탐/누락이 난다).
- 동작 변경 지점(≤3)을 **각각 파일을 직접 Read해 로직을 검토**한다 — 수반된 널 처리·계산식이 올바른지(피연산자 순서·부호 포함) 반드시 확인한다. grep 통과는 컴파일 안전만 보장할 뿐 계산 정확성을 보장하지 않는다.

## Track B — additive DTO/매퍼

**적용 조건 (전부 AND)**:

- 변경이 additive-only에 가깝다 — 신규 모델/DTO(`Response`/`Request`/`Entity`/도메인 모델/`Model`)·enum·필드·매퍼·API 메서드·UseCase·Repository/DataSource 메서드 **추가**. 삭제 거의 없고 기존 함수 본문 수정은 최소(주로 exhaustive `when`에 새 분기 추가).
- 새 코드가 **레이어드 매핑·위임 보일러플레이트**에 국한된다 — `toDomain/toData/toRemote/toPresentation` 매퍼, 단순 위임 호출, sealed에 새 subtype 추가. 새 알고리즘·상태 분기는 없거나, 있어도 **명세에 1:1 대응하는 사소한 조건부**(예: 명세대로 nullable이면 쿼리에서 omit)뿐이며 diff만으로 자명하다.
- 실질 리스크가 세 종류로 환원된다: (a) 서버-클라 **계약 불일치**(쿼리 파라미터·직렬화 키·enum wire값·nullability·응답 형태), (b) **매퍼 왕복 불완전 / 레이어 비대칭**(새 필드가 일부 레이어에서 누락), (c) 새 sealed subtype의 **exhaustive `when` 미커버**.

**강제 게이트**:

- **계약 대조**: 2단계에서 확보한 1급 계약(API 명세·Slack 스펙 스레드)에 신규 DTO의 **모든 필드·enum wire값·쿼리 파라미터**의 이름·타입·nullable·직렬화 키를 1:1 대조한다. 계약을 확보 못 했거나 하나라도 불일치면 fast-path 무효 → 3-A.
- **매퍼 왕복 완전성**: 새 필드가 remote↔data↔domain↔presentation **모든 레이어에 대칭**으로 매핑되는지 각 레이어 파일을 직접 확인한다. 한 레이어라도 silent drop이 있으면 finding으로 올린다(fast-path 무효는 아님 — 발견이 목적).
- **exhaustive `when` 커버**: 새 sealed subtype을 PR head 기준 grep해 그 타입을 소비하는 **모든 `when`이 갱신**됐는지 확인한다(미커버 = 빌드 깨짐 → Critical finding).

**"trivial해 보인다"만으로는 부족하다** — 선택한 트랙의 조건이 명시적으로 충족돼야 한다. 판단이 조금이라도 흔들리면 3-A.

## 출력 플러밍

직접 검증에서 발견한 이슈를 `codeIssues`와 동일한 형태(`severity`·`perspective`·`file`·`line`·`issue`·`mergeBlocking`·`problem_code`·`language`·`suggestion`, 선택 `suggestion_code`)로 정리해 4단계에 넘긴다. fast-path는 교차검증이 없어 `verifyNote`는 붙지 않으며, `mergeBlocking`은 5단계 REJECT 게이트(머지차단 Warning)에 쓰이므로 반드시 채운다. 선별(검증된 Critical·머지차단 Warning 전량 + 나머지 non-critical 최대 5건)·5단계 판정·6단계 difit 게이트는 그대로 적용한다. 6-C/6-B 요약 라인의 에이전트 표기는 사용한 트랙에 맞춰 `직접 검토(fast-path A: 기계적 변경, PR head grep 검증)` 또는 `직접 검토(fast-path B: additive DTO, 계약 대조·매퍼 왕복 검증)`로 한다. (구조는 "Workflow 실패 시 폴백"과 유사하나, fast-path는 애초에 fan-out을 스폰하지 않는 점이 다르다.) 디자인 리뷰(3-B)는 fast-path와 무관하게 Figma 링크 확보 시 정상 진행한다.
