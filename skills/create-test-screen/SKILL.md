---
name: create-test-screen
description: 디바이스에서 즉시 띄워 검증할 수 있는 테스트 전용 Activity를 추가한다 — 커스텀 View/`AbstractComposeView`(XML 컴포넌트)든 `@Composable` 함수(Compose 컴포넌트)든 하나의 Compose 하네스에 올리고, 앱 서랍에 별도 아이콘(LAUNCHER intent-filter + exported=true 포함)으로 노출한다. 사용자가 'create-test-screen', '테스트 화면 만들어줘', '컴포넌트 테스트 화면', '마이그레이션 확인 화면', '변경사항 확인 화면', '디바이스에서 띄워보고 싶다', 등 — 디바이스에서 즉시 띄워 검증할 화면 생성을 요청하면 **반드시** 이 스킬로 진입한다. Activity/Manifest를 스킬 우회로 직접 작성하지 않는다. 프로덕션 화면 생성에는 사용하지 않는다.
argument-hint: "[component_fqcn] [ticket_id]"
---

# /create-test-screen

컴포넌트를 수동 QA하기 위한 테스트 전용 Activity를 추가한다. **하네스(감싸는 Activity + 화면 골격)는 항상 Compose(`setContent {}`)로 만든다.** 테스트 대상은 두 종류를 모두 지원한다:

- **View 대상**: 커스텀 View 또는 `AbstractComposeView` 기반 View → `AndroidView`로 Compose 안에 얹는다.
- **Compose 대상**: `@Composable` 함수 → Compose 하네스에서 직접 호출한다.

앱 서랍에 별도 아이콘으로 나와 바로 실행할 수 있다. 산출물은 Android 빌드 변종 `debug`(`src/debug/`)에만 포함되어 릴리스 APK에는 섞이지 않는다.

사용자 입력: $ARGUMENTS

## 입력

- **component_fqcn** (필수): 테스트 대상의 FQCN. View 클래스든 `@Composable` 함수든 허용.
  - View 예) `kr.co.prnd.heydealer.core.ui.component.carNumber.CarNumberPlateFieldView`
  - Composable 예) `kr.co.prnd.heydealer.core.ui.component.price.PriceInputField`
- **ticket_id** (선택): Jira 이슈 키. 예) `HDA-21109`. 지정 시 Activity/Launcher label에 접두로 사용.

입력이 부족하면 `AskUserQuestion`으로 보완한다.

## 역할

단일 화면에 **대상 컴포넌트 1개**를 띄우고, 관찰 가능한 이벤트(리스너/콜백)와 제어 가능한 API(setter/파라미터/초기화)를 눈으로 확인할 수 있는 **Compose** UI를 자동 생성한다. Activity는 `debug` 변종에만 포함되며, 앱 서랍에 `{ticket_id} Test` 또는 `{Component} Test` 이름으로 별도 아이콘으로 표시되어 adb 없이 탭 한 번으로 실행할 수 있다.

## 타깃 유형 → 하네스 패턴

| 대상 유형 | 판별 | Compose 배선 |
|-----------|------|--------------|
| **View** (커스텀 View, `AbstractComposeView`) | FQCN 마지막 세그먼트가 View를 상속하는 `class` | `AndroidView(factory = { remember 된 인스턴스 })` + 버튼에서 setter 직접 호출 |
| **Composable** (`@Composable fun`) | FQCN 마지막 세그먼트가 `@Composable fun` | 하네스에서 직접 호출 + 파라미터를 `remember` 상태로 hoisting |

**둘 다 최종 골격은 동일하다**: `AppCompatActivity` → `setContent { {Theme} { {Component}TestScreen() } }` → `Column`(스크롤) 안에 제목 / 대상 / 관찰 `Text` / 제어 `Button`. 다른 건 가운데 "대상을 얹는 방식"뿐이다.

## 실행 방법

### 1. 대상 컴포넌트 분석 + 타깃 유형 판별

FQCN으로 `.kt` 파일을 찾아 Read하고, **먼저 타깃 유형을 판별**한다:

- FQCN 마지막 세그먼트와 같은 이름의 `class ... : (…)View`/`AbstractComposeView`/`FrameLayout` 등 View 상속 → **View 대상**
- FQCN 마지막 세그먼트와 같은 이름의 `@Composable fun ...` → **Composable 대상**
- 한 파일에 `{Name}View` 클래스와 `{Name}` Composable이 **둘 다** 있으면(예: `create-composable-with-view` 산출물), FQCN 마지막 세그먼트가 가리키는 심볼로 결정한다. 모호하면 `AskUserQuestion`.

그다음 유형에 맞춰 추출한다:

**View 대상**:
- **생성자 시그니처**: `@JvmOverloads` 여부, `(Context, AttributeSet?, Int)` 시그니처인지
- **공개 멤버**: `fun setXxx(...)` / `fun getXxx(): T` / `fun clearXxx()` (제어용), `fun setOn*Listener(...)` / `var *Listener` (콜백), 단독 프로퍼티 setter
- **XML attr**: `obtainStyledAttributes`에서 읽는 `R.styleable.{Component}_*`

**Composable 대상**:
- **파라미터 목록**: 값 파라미터(`value: String`, `enabled: Boolean` 등)와 콜백 파라미터(`onValueChange: (String) -> Unit`, `onSubmit: (…) -> Unit` 등)를 구분
- 값 파라미터 → `remember` 상태 + 제어 버튼으로 시연. 콜백 파라미터 → 호출 시 관찰 `Text` 갱신
- `modifier: Modifier = Modifier`는 그대로 두거나 생략

- **예상 초기 입력값**: 기본 데모용 값. 한국어 도메인이면 예: `"12가3456"`, 가격이면 `"1000000"`.

정보가 없으면 단계별로 축소 — 관찰/제어 요소 없이 대상만 화면에 올린다.

### 2. 대상 모듈 선택

**하네스가 Compose라 대상 유형과 무관하게 모듈에 Compose Gradle 플러그인이 반드시 있어야 한다.** 다음 우선순위로 결정:

1. **`feature-common`을 기본 선택**한다. Compose 플러그인(`prnd.android.library.compose`)과 `projects.heydealerCoreUi` 의존성이 이미 걸려 있어 추가 작업 없이 컴파일된다.
2. 대상이 `feature-common`에서 도달하지 않는 모듈에 있을 경우:
   - 해당 모듈의 의존성을 타고 올라가, Compose 플러그인이 이미 켜진 상류 모듈 중 가장 가까운 후보를 고른다.
   - 후보가 없으면 `feature-common/build.gradle.kts`에 `debugImplementation(projects.xxx)`를 추가한다는 선택지를 사용자에게 제안한다 (단, 릴리스 APK에 영향이 없는지 확인 후 적용).
3. **`app` 모듈에는 두지 않는다**. 앱 모듈은 Compose 플러그인이 적용되지 않는 경우가 많아 `setContent`/`AndroidView`/`AbstractComposeView` 접근에서 컴파일 실패한다.

모듈을 확정했으면 그 모듈의 `namespace`(build.gradle에서)와 `AndroidManifest.xml` 내 `application` 하위 태그 관례를 확인한다.

### 3. 테마 추론

하네스 `setContent {}`를 감쌀 Compose 테마를 정한다 (대상 컴포넌트가 테마 토큰을 쓰면 이게 있어야 정상 렌더된다):

- 모듈 경로/namespace에 `heydealer`/`HeyDealer` 포함 → `kr.co.prnd.design.theme.HeyDealerTheme`
- `revolt`/`Revolt` 포함 → `kr.co.prnd.revolt.design.theme.RevoltTheme`
- 둘 다 매칭/미매칭 → `AskUserQuestion`

### 4. 경로 계산

- **Activity 파일**: `{module}/src/debug/kotlin/{namespace_path}/test/{Component}TestActivity.kt`
- **Manifest 파일**: `{module}/src/debug/AndroidManifest.xml` (기존에 있으면 `<application>` 내부에 `<activity>`만 추가)
- **Layout XML은 만들지 않는다** — 하네스는 Compose다.

`src/debug/`는 Android Gradle 변종 소스셋 식별자로, 릴리스 빌드에 포함되지 않도록 보장하기 위해 반드시 이 경로를 사용한다.

**namespace_path**: `namespace`의 점을 `/`로. 예) `kr.co.prnd.heydealerfordealer.feature.common` → `kr/co/prnd/heydealerfordealer/feature/common`

**{Component}**: FQCN 마지막 세그먼트 그대로. View 대상이면 보통 `...View`로 끝난다.

### 5. 디렉터리 생성

파일 작성 전에 `mkdir -p`로 상위 디렉터리를 만든다.

### 6. Activity + Test Screen 생성 (`{Component}TestActivity.kt`)

`AppCompatActivity` 상속(프로젝트 관례, `setContent` 사용 가능하며 커스텀 View의 AppCompat 컨텍스트 요구도 충족). `internal class`. 패키지는 `{namespace}.test`. **ViewModel/Hilt는 쓰지 않는다** — 하네스는 상태 없는 데모다.

골격(두 유형 공통):

```kotlin
internal class {Component}TestActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            {Theme} {
                {Component}TestScreen()
            }
        }
    }
}
```

- `setContent`는 `androidx.activity.compose.setContent` import. `setContentView(R.layout...)`를 쓰지 않는다.
- `AppCompatActivity`가 대상 모듈에서 안 잡히면 `androidx.activity.ComponentActivity`로 대체한다 — Compose 전용 하네스엔 충분하다(창 테마는 manifest `android:theme`가 지정, 8단계 참고).
- `{Theme}`는 3단계에서 정한 `HeyDealerTheme` 또는 `RevoltTheme`.
- 제어 `Button` / 관찰 `Text` 등 Compose Material 컴포넌트는 **대상 모듈이 이미 쓰는 것(`androidx.compose.material` vs `material3`)에 맞춘다** — 같은 모듈의 기존 Composable에서 import를 확인한다.

#### View 대상 — `{Component}TestScreen()`

대상을 `remember`로 한 번 만들어 리스너를 배선하고, `AndroidView`로 얹는다. 버튼에서 그 인스턴스의 setter를 직접 호출한다 (`AndroidView` 안에서 만들면 버튼이 인스턴스에 접근할 수 없으므로 밖에서 `remember`).

```kotlin
@Composable
private fun {Component}TestScreen() {
    val context = LocalContext.current
    var lastCompleted by remember { mutableStateOf("onCompleted: -") }
    val target = remember {
        {Component}(context).apply {
            setOnCompletedListener { value -> lastCompleted = "onCompleted: $value" }
        }
    }
    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text("{ticket_id} {Component}")
        AndroidView(factory = { target })
        Text(lastCompleted)                                                   // 관찰: 리스너마다 Text 1개
        Button(onClick = { target.setCarNumber("34나5678") }) { Text("setCarNumber") }  // 제어: setter마다 버튼 1개
        Button(onClick = { target.clear() }) { Text("clear") }
    }
}
```

- 리스너별로 관찰 상태(`var xxx by remember { mutableStateOf(...) }`) + `Text` 1개.
- setter/clearer별로 `Button` 1개, `onClick`에서 `target.xxx(...)` 직접 호출.
- getter가 있으면 별도 관찰 상태에 `target.getXxx().toString()`(또는 대표 필드)을 읽어 넣는 버튼으로 시연.
- 초기값은 setter 버튼으로 시연한다. `apply {}` 안에서 seed하면 attach 이전 호출이라 View 구현에 따라 안 먹을 수 있다.
- 대상이 화면 폭을 채워야 하면 `AndroidView(factory = { target }, modifier = Modifier.fillMaxWidth())`.
- `AbstractComposeView` 기반 View도 결국 View이므로 동일하게 `AndroidView`로 얹으면 된다 (setContent 트리 안이라 lifecycle owner가 이미 주입됨).

#### Compose 대상 — `{Component}TestScreen()`

대상을 직접 호출한다. 값 파라미터는 `remember` 상태로 hoisting해 버튼으로 바꾸고, 콜백 파라미터는 관찰 상태를 갱신한다.

```kotlin
@Composable
private fun {Component}TestScreen() {
    var value by remember { mutableStateOf("1000000") }
    var enabled by remember { mutableStateOf(true) }
    var lastSubmit by remember { mutableStateOf("onSubmit: -") }
    Column(
        modifier = Modifier
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text("{ticket_id} {Component}")
        {Component}(
            value = value,
            onValueChange = { value = it },
            onSubmit = { lastSubmit = "onSubmit: $it" },
            enabled = enabled,
        )
        Text("value = $value")                                    // 관찰: 값 상태
        Text(lastSubmit)                                          // 관찰: 콜백 결과
        Button(onClick = { enabled = !enabled }) { Text("toggle enabled") }  // 제어: Boolean 파라미터
        Button(onClick = { value = "" }) { Text("clear value") }             // 제어: 값 파라미터
    }
}
```

- 값 파라미터(`String`/`Boolean`/`Int` 등) → `remember` 상태 + 바꾸는 버튼.
- 콜백 파라미터(`(...) -> Unit`) → 인자를 `$var` 문자열로 풀어 관찰 `Text`에 표시.
- 데이터 객체를 넘기는 콜백이면 `.toString()` 또는 대표 필드를 노출.

### 7. AndroidManifest 생성/병합

기존에 `{module}/src/debug/AndroidManifest.xml`이 없으면 신규 생성:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application>
        <activity
            android:name=".test.{Component}TestActivity"
            android:exported="true"
            android:label="{Label}"
            android:theme="@style/AppTheme">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

- `{Label}`: `{ticket_id} Test` (티켓 있으면) 또는 `{Component} Test`
- `android:theme`는 프로젝트 공통 테마(`Theme.AppCompat` 계열)를 따름 (`@style/AppTheme`가 일반적). `AppCompatActivity`는 AppCompat 계열 테마가 필요하므로 main AndroidManifest에서 쓰는 테마를 참고한다.
- 이미 파일이 있으면 `<application>` 하위에 `<activity>` 블록만 삽입 (인덴트 맞춰서)

### 8. 빌드 검증

순차 실행:

1. `./gradlew :{module}:compileDebugKotlin --no-daemon` — 컴파일 에러 확인
2. `Unresolved reference 'XXX'`면 1단계 분석을 다시 해서 import/시그니처(또는 Composable 파라미터)를 재점검
3. `Cannot access 'AbstractComposeView' ... supertype`, `AndroidView`/Compose 심볼 미해결이면 Compose 플러그인이 없는 모듈 — 2단계로 돌아가 다른 모듈을 선택
4. `setContent` 미해결이면 모듈에 `activity-compose`가 없다 — **모듈을 바꾸지 말고** `{module}/build.gradle.kts`에 `debugImplementation(libs.androidx.activity.compose)`를 추가한다 (debug 전용이라 릴리스 무영향, libs alias 없으면 좌표 직접). 하네스가 `setContentView` 대신 `setContent`를 쓰면서 새로 생긴 요구사항이다
5. `AppCompatActivity` 미해결이면 모듈에 appcompat이 없다 — 6단계 골격의 base를 `androidx.activity.ComponentActivity`로 대체하면 된다 (activity-compose가 이미 제공). 또는 `debugImplementation`으로 appcompat 추가
6. `Button`/`Text` 미해결이면 `material` ↔ `material3` import 불일치 — 대상 모듈 관례에 맞춰 교정
7. `./gradlew :app:processDevDebugManifest --no-daemon` — manifest 머지 (app 모듈에 flavor가 있으면 해당 flavor명 사용)
8. 머지된 매니페스트에서 Activity + LAUNCHER intent-filter가 포함됐는지 확인:
   - `grep -A 5 "{Component}TestActivity" app/build/intermediates/merged_manifests/*/processDev*Manifest/AndroidManifest.xml`

### 9. 실행 안내

사용자에게 아래를 전달:

```
./gradlew :app:install{Variant}   # 기기 설치
```

설치 후 기기의 앱 서랍에서 `{Label}` 아이콘 탭으로 실행.

또는 adb shell로 직접 실행:

```
adb shell am start -n {applicationId}/{module_namespace}.test.{Component}TestActivity
```

## 주의사항

- **Kotlin 파일은 반드시 `cat > file << 'EOF'` heredoc으로 작성**한다 (IDE 자동 포맷터가 파일을 변형하지 않도록).
- **커밋하지 않는다**. 파일 생성까지만 수행하고, 커밋 여부는 사용자가 결정한다.
- **MAIN/LAUNCHER intent-filter는 `src/debug/`에만** 둔다. 릴리스 빌드에 섞이지 않도록 `src/debug/AndroidManifest.xml`에만 작성한다.
- **`android:exported="true"`는 필수**다 (API 31+에서 launcher 필요 조건).
- **하네스는 Compose 전용**이다. `setContentView(R.layout...)`/`findViewById`/XML 레이아웃 파일을 만들지 않는다. View 대상도 `AndroidView`로 얹는다.
- **app 모듈 의존성을 늘리지 않는다**. 이미 존재하는 모듈 경계 안에서 해결이 안 되면 사용자에게 확인한 뒤 모듈 선택을 조정한다.
- 컴포넌트 공개 API/파라미터가 매우 많으면 대표적인 것(setter/파라미터 2~3개, clearer/토글 1개)만 배치하고, 나머지는 사용자에게 추가할지 묻는다.

## 결과 보고 형식

파일 생성 완료 후 아래를 요약 제공:

- 생성된 파일 목록 (경로)
- 판별한 타깃 유형(View / Composable)과 적용한 하네스 패턴
- 모듈 선택 사유 (왜 그 모듈인지 1줄)
- 앱 서랍 라벨 / 실행 방법
- 빌드 검증 결과
- 다음 단계 (기기 설치 명령)
