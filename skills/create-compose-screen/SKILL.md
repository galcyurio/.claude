---
name: create-compose-screen
description: HeyDealer 또는 Revolt 테마의 Compose Screen 묶음(Activity, ViewModel, Screen, UiState, UiAction 5개 파일)을 한 번에 생성하는 스킬. 사용자가 'create-compose-screen', 'compose screen 만들어', '화면 추가', 'Activity + ViewModel 묶음 만들어', 'MVI 화면 생성', '골격 구현 추가' 등을 요청할 때 이 스킬을 사용해야 한다. 단일 Composable만 필요할 때는 create-composable, View로 감싸야 할 때는 create-composable-with-view 를 사용한다.
argument-hint: "[name] [target_dir_or_fqcn] [screen_label]"
---

# /create-compose-screen

HeyDealer 또는 Revolt 테마의 Compose Screen 묶음 5개 파일(`{Name}Activity.kt`, `{Name}Screen.kt`, `{Name}ViewModel.kt`, `{Name}UiAction.kt`, `{Name}UiState.kt`)을 한 번에 생성한다. 동시에 analytics `Screen` 상수와 `AndroidManifest.xml` activity 등록까지 함께 처리한다.

사용자 입력: $ARGUMENTS

## 입력

- **name** (필수): PascalCase 스크린 이름. 예) `DropZeroParticipate`, `MarketNotificationList`
- **target_dir_or_fqcn** (필수): 디렉터리 절대경로 또는 FQCN
- **screen_label** (선택): analytics `Screen` 상수 값으로 사용할 한국어 설명 (예: "헤이딜러 마켓 - 관심 차 가격 변동 알림"). 입력에 없으면 `AskUserQuestion`으로 보완한다.

입력이 부족하면 `AskUserQuestion`으로 보완한다.

## 실행 단계

### 1. 입력 파싱

`$ARGUMENTS`에서 `name`, `target`, `screen_label` 추출. 다음 4가지 형식을 모두 허용:

| 입력 형태 | 해석 |
|----------|------|
| `MyScreen app/.../foo/` | name = `MyScreen`, target_dir 그대로 |
| `MyScreen kr.co.prnd.heydealer.foo` | name = `MyScreen`, package에서 디렉터리 역추론 |
| `kr.co.prnd.heydealer.foo.MyScreen` | FQCN으로 해석. name + package 동시 추출 |
| `MyScreen` (위치 미지정) | `AskUserQuestion`으로 위치 질문 |

`screen_label`은 자연어 입력 중 따옴표·콜론·줄바꿈으로 구분된 한국어 설명을 우선 매핑하고, 추출 실패 시 별도 단계에서 보완한다.

자연어 입력으로 진입한 경우, 컨텍스트에 `Composable 한 개`·`View로 감싼` 단어가 있으면 다른 스킬 사용을 안내. 모호하면 `AskUserQuestion`으로 종류 확인.

### 2. target 정규화

- FQCN → 디렉터리로 변환 + `name` 자동 추출
- 디렉터리 경로 → 그대로 사용
- 존재하지 않으면 `AskUserQuestion`으로 확인

### 3. 테마 추론

- 경로에 `heydealer`/`HeyDealer` 포함 → HeyDealer
- 경로에 `revolt`/`Revolt` 포함 → Revolt
- 둘 다 매칭/미매칭 → `AskUserQuestion`

### 4. 패키지 추론

`src/main/kotlin/` 또는 `src/main/java/` 아래 경로를 점으로 연결. 실패 시 `AskUserQuestion`.

### 5. Screen 상수 결정

- **상수 이름(`SCREEN_CONST`)**: `name`을 SCREAMING_SNAKE_CASE로 변환 (예: `MarketPriceNotification` → `MARKET_PRICE_NOTIFICATION`).
- **상수 값(`SCREEN_LABEL`)**: 입력에서 추출했으면 그대로 사용. 없으면 `AskUserQuestion`으로 한국어 설명을 입력받는다 (예: "헤이딜러 마켓 - 관심 차 가격 변동 알림"). 동일 도메인의 기존 상수 값(예: `MARKET_NOTIFICATION_LIST = "헤이딜러 마켓 - 알림 추가"`)을 참고해 일관된 prefix(예: `헤이딜러 마켓 - …`)를 제안한다.

### 6. Screen.kt / AndroidManifest.xml 위치 결정

- **analytics Screen.kt**: `grep -rn "object Screen " --include="*.kt"` 또는 알려진 경로(`analytics/src/main/java/.../analytics/Screen.kt`)에서 자동 탐지. Revolt 테마에서도 동일한 `kr.co.prnd.heydealer.analytics.Screen`을 공통 사용한다 (별도 Revolt analytics 파일이 발견되면 그것을 우선).
- **AndroidManifest.xml**: `target_dir`에서 위로 거슬러 올라가 가장 가까운 `src/main/AndroidManifest.xml`을 찾는다.
- 둘 중 하나라도 발견 실패 시 `AskUserQuestion`으로 위치를 확인하거나, 사용자가 직접 처리하기로 선택할 수 있게 한다.

### 7. 파일 충돌 검사

생성 대상 5개 파일 중 **하나라도** 존재하면 전체 작업을 중단하고 `AskUserQuestion`으로 처리 방법 확인:
- `{name}Activity.kt`
- `{name}Screen.kt`
- `{name}ViewModel.kt`
- `{name}UiAction.kt`
- `{name}UiState.kt`

옵션: 모두 덮어쓰기 / 일부만 덮어쓰기 / 중단.

추가 확인:
- Screen.kt에 이미 동일 `SCREEN_CONST`가 존재하면 새로 추가하지 않고 그 값을 그대로 사용한다.
- AndroidManifest.xml에 이미 동일 activity가 등록돼 있으면 추가하지 않는다.

### 8. 템플릿 로드 + 치환

다음 5개 템플릿을 모두 처리:

| 템플릿 경로 | 출력 파일 |
|------------|-----------|
| `~/.claude/skills/create-compose-screen/templates/{Theme}/Activity.kt.template` | `{target_dir}/{name}Activity.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/Screen.kt.template` | `{target_dir}/{name}Screen.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/ViewModel.kt.template` | `{target_dir}/{name}ViewModel.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/UiAction.kt.template` | `{target_dir}/{name}UiAction.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/UiState.kt.template` | `{target_dir}/{name}UiState.kt` |

치환 변수:

| 변수 | 값 |
|------|-----|
| `${NAME}` | `name` (PascalCase) |
| `${PACKAGE_NAME}` | 추론 패키지 |
| `${SCREEN_CONST}` | SCREAMING_SNAKE_CASE 이름 |

치환 후 `Write` 도구로 저장.

### 9. Screen.kt에 상수 추가

`Screen.kt` 파일에 다음 형식의 const val을 추가한다:

```kotlin
const val ${SCREEN_CONST} = "${SCREEN_LABEL}"
```

**추가 위치 규칙**:
- 동일 prefix(예: `MARKET_`)의 const 블록이 있으면 그 블록 마지막에 끼워넣는다.
- 그렇지 않으면 const 목록의 자연스러운 위치(가장 가까운 도메인 그룹)에 추가.
- 정 적당한 위치가 없으면 const 목록의 가장 마지막에 추가.

### 10. AndroidManifest.xml에 activity 등록

신규 activity 항목을 추가한다:

```xml
<activity
    android:name=".{RELATIVE_PATH}.${NAME}Activity"
    android:screenOrientation="portrait" />
```

- `RELATIVE_PATH`: 기존 manifest의 `<activity android:name>` 값이 사용하는 prefix(예: 다른 activity가 `.market.foo.X`라면 manifest namespace 기준 상대 경로)를 분석해 동일한 규칙으로 계산한다. 패키지에서 manifest namespace 부분을 제거한 나머지를 점 경로로 사용.
- 분석이 어렵거나 모호하면 전체 FQCN(`${PACKAGE_NAME}.${NAME}Activity`)을 그대로 사용해도 manifest 유효성에는 문제없다.
- 입력 옵션(`android:screenOrientation` 등): 같은 manifest의 가장 인접한 기존 activity 패턴을 참고해 일관성 있게 맞춘다 (기본은 `screenOrientation="portrait"`).

**추가 위치 규칙**: 동일/유사 도메인의 다른 activity 선언 직후에 끼워넣는다. 그렇지 않으면 마지막 `<activity>` 항목 다음에 추가.

### 11. 자동 커밋

생성·수정된 파일을 자동으로 커밋한다.

1. **Issue ID 추출**: `git branch --show-current` 결과에서 `HDA-\d+` 정규식 추출
2. **추출 실패 시**: `AskUserQuestion`으로 Issue ID 입력 받기 (옵션: "직접 입력" / "없이 진행")
3. **staging**: `git add`는 아래 파일 절대경로를 모두 명시한다 (working tree 다른 변경 보호)
   - 신규 5개 파일 (`{name}Activity.kt`, `{name}Screen.kt`, `{name}ViewModel.kt`, `{name}UiAction.kt`, `{name}UiState.kt`)
   - 수정된 Screen.kt
   - 수정된 AndroidManifest.xml
4. **commit**: 메시지 형식
   - Issue ID 있음: `HDA-XXX feat: 골격 구현을 추가한다`
   - Issue ID 없음: `feat: 골격 구현을 추가한다`
   - 본문에 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer 추가
5. 커밋 실패 시 에러 보고, staged 상태 유지

### 12. 결과 보고

- 생성·수정된 파일 절대경로 목록 (신규 5개 + Screen.kt + AndroidManifest.xml)
- 추론된 테마/패키지/Screen 상수
- 생성된 커밋 hash (단축 형식)

## 에러 처리

| 케이스 | 처리 |
|--------|------|
| `name`/`target` 누락 | `AskUserQuestion`으로 보완 |
| FQCN 마지막 세그먼트가 PascalCase 아님 | 에러 |
| `target_dir` 미존재 | `AskUserQuestion`으로 확인 |
| 테마 추론 실패/충돌 | `AskUserQuestion` |
| 패키지 추론 실패 | `AskUserQuestion` |
| `screen_label` 누락 | `AskUserQuestion`으로 보완 |
| Screen.kt 위치 탐지 실패 | `AskUserQuestion` |
| AndroidManifest.xml 위치 탐지 실패 | `AskUserQuestion` |
| 5개 중 1개라도 충돌 | 전체 중단 후 `AskUserQuestion` |
| 템플릿 파일 없음 | 에러 |
| `name` non-PascalCase | 경고 후 그대로 사용 |
| Issue ID 추출 실패 | `AskUserQuestion`으로 입력 또는 "없이 진행" |
| git 커밋 실패 | 에러 보고, staged 상태 유지 |

## 주의사항

- **`git add`는 명시한 파일 절대경로만 지정**한다. `git add .`이나 `git add -A`를 쓰지 않는다. working tree의 다른 변경을 보호한다.
- 5개 파일 모두 같은 패키지에 생성된다. 패키지가 모두 동일하므로 `${PACKAGE_NAME}.${NAME}ViewModel.Event` import는 사실 같은 패키지 내 inner 클래스 참조다. 원본 file template과 동일하게 명시적 import를 유지한다 (불필요해도 컴파일은 정상 동작).
- 5개 파일이 부분적으로만 생성되는 상태를 피한다. 도중에 실패하면 이미 생성된 파일을 안내하고 자동 커밋 단계를 건너뛴다.
- Screen.kt / AndroidManifest.xml 수정 실패 시: 이미 생성된 신규 5개 파일은 유지하되, 어떤 단계에서 실패했는지 명시하고 사용자가 수동으로 마무리할 수 있도록 안내한다 (커밋은 진행하지 않는다).
- 커밋 메시지는 `~/.claude/rules/git-commit-message.md` 규칙을 따른다.
