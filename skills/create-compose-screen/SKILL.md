---
name: create-compose-screen
description: HeyDealer 또는 Revolt 테마의 Compose Screen 묶음(Activity, ViewModel, Screen, UiState, UiAction 5개 파일)을 한 번에 생성하는 스킬. 사용자가 'create-compose-screen', 'compose screen 만들어', '화면 추가', 'Activity + ViewModel 묶음 만들어', 'MVI 화면 생성', '골격 구현 추가' 등을 요청할 때 이 스킬을 사용해야 한다. 단일 Composable만 필요할 때는 create-composable, View로 감싸야 할 때는 create-composable-with-view 를 사용한다.
argument-hint: "[name] [target_dir_or_fqcn]"
---

# /create-compose-screen

HeyDealer 또는 Revolt 테마의 Compose Screen 묶음 5개 파일(`{Name}Activity.kt`, `{Name}Screen.kt`, `{Name}ViewModel.kt`, `{Name}UiAction.kt`, `{Name}UiState.kt`)을 한 번에 생성한다.

사용자 입력: $ARGUMENTS

## 입력

- **name** (필수): PascalCase 스크린 이름. 예) `DropZeroParticipate`, `MarketNotificationList`
- **target_dir_or_fqcn** (필수): 디렉터리 절대경로 또는 FQCN

입력이 부족하면 `AskUserQuestion`으로 보완한다.

## 실행 단계

### 1. 입력 파싱

`$ARGUMENTS`에서 `name`과 `target` 추출. 다음 4가지 형식을 모두 허용:

| 입력 형태 | 해석 |
|----------|------|
| `MyScreen app/.../foo/` | name = `MyScreen`, target_dir 그대로 |
| `MyScreen kr.co.prnd.heydealer.foo` | name = `MyScreen`, package에서 디렉터리 역추론 |
| `kr.co.prnd.heydealer.foo.MyScreen` | FQCN으로 해석. name + package 동시 추출 |
| `MyScreen` (위치 미지정) | `AskUserQuestion`으로 위치 질문 |

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

### 5. 파일 충돌 검사

생성 대상 5개 파일 중 **하나라도** 존재하면 전체 작업을 중단하고 `AskUserQuestion`으로 처리 방법 확인:
- `{name}Activity.kt`
- `{name}Screen.kt`
- `{name}ViewModel.kt`
- `{name}UiAction.kt`
- `{name}UiState.kt`

옵션: 모두 덮어쓰기 / 일부만 덮어쓰기 / 중단.

### 6. 템플릿 로드 + 치환

다음 5개 템플릿을 모두 처리:

| 템플릿 경로 | 출력 파일 |
|------------|-----------|
| `~/.claude/skills/create-compose-screen/templates/{Theme}/Activity.kt.template` | `{target_dir}/{name}Activity.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/Screen.kt.template` | `{target_dir}/{name}Screen.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/ViewModel.kt.template` | `{target_dir}/{name}ViewModel.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/UiAction.kt.template` | `{target_dir}/{name}UiAction.kt` |
| `~/.claude/skills/create-compose-screen/templates/{Theme}/UiState.kt.template` | `{target_dir}/{name}UiState.kt` |

각 템플릿에서 `${NAME}` → `name`, `${PACKAGE_NAME}` → 추론 패키지로 치환 후 `Write` 도구로 저장.

### 7. 자동 커밋

생성된 5개 파일을 자동으로 커밋한다.

1. **Issue ID 추출**: `git branch --show-current` 결과에서 `HDA-\d+` 정규식 추출
2. **추출 실패 시**: `AskUserQuestion`으로 Issue ID 입력 받기 (옵션: "직접 입력" / "없이 진행")
3. **staging**: `git add`는 5개 파일 절대경로를 모두 명시한다 (working tree 다른 변경 보호)
4. **commit**: 메시지 형식
   - Issue ID 있음: `HDA-XXX feat: 골격 구현을 추가한다`
   - Issue ID 없음: `feat: 골격 구현을 추가한다`
   - 본문에 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer 추가
5. 커밋 실패 시 에러 보고, staged 상태 유지

### 8. 결과 보고

- 생성된 5개 파일 절대경로 목록
- 추론된 테마/패키지
- 생성된 커밋 hash (단축 형식)
- **AndroidManifest.xml 안내**: 생성된 `{name}Activity.kt`의 주석(`// TODO: AndroidManifest.xml 파일에 activity 선언`)을 그대로 두었음을 명시하고, 사용자가 manifest에 `<activity android:name=".{name}Activity" ... />`를 직접 추가해야 한다고 안내
- **TODO 안내**: `TODO("screenName 추가")` 부분은 사용자가 `Screen.{SCREEN_NAME}` analytics enum을 직접 채워야 한다고 안내

## 에러 처리

| 케이스 | 처리 |
|--------|------|
| `name`/`target` 누락 | `AskUserQuestion`으로 보완 |
| FQCN 마지막 세그먼트가 PascalCase 아님 | 에러 |
| `target_dir` 미존재 | `AskUserQuestion`으로 확인 |
| 테마 추론 실패/충돌 | `AskUserQuestion` |
| 패키지 추론 실패 | `AskUserQuestion` |
| 5개 중 1개라도 충돌 | 전체 중단 후 `AskUserQuestion` |
| 템플릿 파일 없음 | 에러 |
| `name` non-PascalCase | 경고 후 그대로 사용 |
| Issue ID 추출 실패 | `AskUserQuestion`으로 입력 또는 "없이 진행" |
| git 커밋 실패 | 에러 보고, staged 상태 유지 |

## 주의사항

- **`git add`는 정확히 5개 파일 절대경로만 지정**한다. `git add .`이나 `git add -A`를 쓰지 않는다. working tree의 다른 변경을 보호한다.
- 5개 파일 모두 같은 패키지에 생성된다. 패키지가 모두 동일하므로 `${PACKAGE_NAME}.${NAME}ViewModel.Event` import는 사실 같은 패키지 내 inner 클래스 참조다. 원본 file template과 동일하게 명시적 import를 유지한다 (불필요해도 컴파일은 정상 동작).
- 5개 파일이 부분적으로만 생성되는 상태를 피한다. 도중에 실패하면 이미 생성된 파일을 안내하고 자동 커밋 단계를 건너뛴다.
- 커밋 메시지는 `~/.claude/rules/git-commit-message.md` 규칙을 따른다.
