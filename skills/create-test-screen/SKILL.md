---
name: create-test-screen
description: UI 컴포넌트/View를 수동 QA하기 위한 테스트 전용 Activity를 앱 서랍에 별도 아이콘으로 추가한다. 사용자가 'create-test-screen', '테스트 화면 만들어줘', '컴포넌트 테스트 화면', '수동 QA 화면', 'QA용 Activity', '테스트 Activity' 등 수동 테스트 전용 컴포넌트 Activity 생성을 요청할 때 이 스킬을 사용해야 한다. 프로덕션 화면 생성에는 사용하지 않는다(프로덕션 화면은 create-screen 스킬).
argument-hint: "[component_fqcn] [ticket_id]"
disable-model-invocation: true
---

# /create-test-screen

Compose View(`AbstractComposeView` 기반) 또는 일반 커스텀 View를 수동 QA하기 위한 테스트 전용 Activity를 추가한다. 앱 서랍에 별도 아이콘으로 나와 바로 실행할 수 있다. 산출물은 Android 빌드 변종 `debug`(`src/debug/`)에만 포함되어 릴리스 APK에는 섞이지 않는다.

사용자 입력: $ARGUMENTS

## 입력

- **component_fqcn** (필수): 테스트 대상 컴포넌트의 FQCN. 예) `kr.co.prnd.heydealer.core.ui.component.carNumber.CarNumberPlateFieldView`
- **ticket_id** (선택): Jira 이슈 키. 예) `HDA-21109`. 지정 시 Activity/Layout/Launcher label에 접두로 사용.

입력이 부족하면 사용자에게 질문으로 보완한다.

## 역할

단일 화면에 **대상 컴포넌트 1개**를 띄우고, 관찰 가능한 이벤트(리스너/콜백)와 제어 가능한 API(setter/초기화)를 눈으로 확인할 수 있는 UI를 자동 생성한다. Activity는 `debug` 변종에만 포함되며, 앱 서랍에 `{ticket_id} Test` 또는 `{Component} Test` 이름으로 별도 아이콘으로 표시되어 adb 없이 탭 한 번으로 실행할 수 있다.

## 실행 방법

### 1. 대상 컴포넌트 분석

FQCN으로 `.kt` 파일을 찾아 Read하고, 아래를 추출한다:

- **생성자 시그니처**: `@JvmOverloads` 여부, `(Context, AttributeSet?, Int)` 시그니처인지
- **공개 멤버**:
  - `fun setXxx(...)` / `fun getXxx(): T` / `fun clearXxx()` — 제어용 API
  - `fun setOn*Listener(...)` / `var *Listener: ...` — 콜백 배선점
  - `var xxx: Boolean` / `var xxx: T` 등 단독 프로퍼티 setter
- **XML attr** (`R.styleable.{Component}_*` 참조로 유추):
  - `obtainStyledAttributes` 호출에서 읽는 attr들
- **예상 초기 입력값**: 기본 데모용 값. 한국어 도메인이면 예: `"12가3456"`.

이 정보가 없으면 단계별로 축소 — 빈 레이아웃에 컴포넌트만 올리고 공개 API가 없으면 버튼 없이 레이아웃만 생성.

### 2. 대상 모듈 선택

다음 우선순위로 결정:

1. **`feature-common`을 기본 선택**한다. Compose 플러그인(`prnd.android.library.compose`)과 `projects.heydealerCoreUi` 의존성이 이미 걸려 있어 추가 작업 없이 컴파일된다.
2. 대상 컴포넌트가 `feature-common`에서 도달하지 않는 모듈에 있을 경우:
   - 해당 모듈의 의존성을 타고 올라가, Compose 플러그인이 이미 켜진 상류 모듈 중 가장 가까운 후보를 고른다.
   - 후보가 없으면 `feature-common/build.gradle.kts`에 `debugImplementation(projects.xxx)`를 추가한다는 선택지를 사용자에게 제안한다 (단, 릴리스 APK에 영향이 없는지 확인 후 적용).
3. **`app` 모듈에는 두지 않는다**. 앱 모듈은 Compose 플러그인이 적용되지 않는 경우가 많아 `AbstractComposeView` supertype 접근에서 컴파일 실패한다.

모듈을 확정했으면 그 모듈의 `namespace`(build.gradle에서)와 `AndroidManifest.xml` 내 `application` 하위 태그 관례를 확인한다.

### 3. 경로 계산

- **Activity 파일**: `{module}/src/debug/kotlin/{namespace_path}/test/{Component}TestActivity.kt`
- **Layout 파일**: `{module}/src/debug/res/layout/activity_{ticket_slug_or_component_slug}_test.xml`
- **Manifest 파일**: `{module}/src/debug/AndroidManifest.xml` (기존에 있으면 `<application>` 내부에 `<activity>`만 추가)

`src/debug/`는 Android Gradle 변종 소스셋 식별자로, 릴리스 빌드에 포함되지 않도록 보장하기 위해 반드시 이 경로를 사용한다.

**slug 규칙**:
- `ticket_id` 있으면: 소문자화 + `-`를 `_`로 치환. 예) `HDA-21109` → `hda_21109`
- 없으면: 컴포넌트 이름을 snake_case로. 예) `CarNumberPlateFieldView` → `car_number_plate_field_view`

**namespace_path**: `namespace`의 점을 `/`로. 예) `kr.co.prnd.heydealerfordealer.feature.common` → `kr/co/prnd/heydealerfordealer/feature/common`

### 4. 디렉터리 생성

파일 작성 전에 `mkdir -p`로 상위 디렉터리를 만든다.

### 5. Layout 생성 (`activity_{slug}_test.xml`)

ScrollView → LinearLayout(vertical) 골격. 구성:

1. **제목 TextView**: `{ticket_id} {ComponentName}` 또는 컴포넌트 이름만
2. **대상 컴포넌트**: FQCN 그대로. 레이아웃 속성은 최소로.
   - `android:layout_width="wrap_content"`, `android:layout_height="wrap_content"` 기본
   - 컴포넌트가 큰 면적이 필요하면 `match_parent`로 조정
   - XML attr이 있으면 대표 attr 하나를 기본값으로 시연(예: `app:clearFocusOnCompleted="true"`)
3. **관찰 TextView**: 1단계에서 추출한 각 리스너별로 한 개씩. id는 `tv_{listener_snake}`, 초기 text는 `{listenerName}: -`
4. **제어 Button들**: 각 공개 setter/clearer API별로 버튼 1개.
   - id는 `btn_{api_snake}`, text는 API 이름 그대로
   - `android:textAllCaps="false"`로 원문 대소문자 유지
   - `android:layout_width="match_parent"` 세로로 쌓는 배치를 기본값으로 (가로 배치는 버튼 3개 이하이고 label이 짧을 때만 예외 허용)
5. **게터 TextView** (`tv_get`): 현재 값 스냅샷 표시용 (getter가 있을 때만)

배경은 `#E3E6EA` 정도의 밝은 회색 기본.

### 6. Activity 생성 (`{Component}TestActivity.kt`)

`AppCompatActivity` 상속(프로젝트 관례). `internal class`. 패키지는 `{namespace}.test`.

구성:

```kotlin
package {namespace}.test

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import {component_fqcn}
import {module_namespace}.R

internal class {Component}TestActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_{slug}_test)

        val target = findViewById<{Component}>(R.id.{component_snake})
        // 각 관찰 TextView findViewById
        // 각 리스너 배선: target.setOnXxxListener { ... -> tvXxx.text = "onXxx: $...값" }
        // 각 버튼 배선: findViewById<Button>(R.id.btn_xxx).setOnClickListener { target.xxx(...); tvGet.text = "..." }
    }
}
```

- 리스너 시그니처에 따라 `(...) -> Unit`의 인자들을 `$var` 문자열 템플릿으로 풀어 TextView에 표시
- getter 반환형이 데이터 객체(예: `CarNumberModel`)면 `.toString()` 또는 대표 필드 하나(`.fullText` 등)를 노출. 1단계에서 본 데이터 클래스의 눈에 띄는 프로퍼티를 선택
- setter 데모값은 한국어 도메인이면 한국어 샘플, 일반 Boolean/Int면 간단한 고정값

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
- `android:theme`는 프로젝트 공통 테마를 따름 (`@style/AppTheme`가 일반적). main AndroidManifest에서 쓰이는 테마 참고
- 이미 파일이 있으면 `<application>` 하위에 `<activity>` 블록만 삽입 (인덴트 맞춰서)

### 8. 빌드 검증

순차 실행:

1. `./gradlew :{module}:compileDebugKotlin --no-daemon` — 컴파일 에러 확인
2. 에러가 `Unresolved reference 'XXX'`면 1단계 분석을 다시 해서 import/시그니처 재점검
3. 에러가 `Cannot access 'AbstractComposeView' which is a supertype`이면 모듈 선택 잘못 — 2단계로 돌아가 Compose 플러그인이 적용된 모듈을 선택
4. `./gradlew :app:processDevDebugManifest --no-daemon` — manifest 머지 (app 모듈에 flavor가 있으면 해당 flavor명 사용)
5. 머지된 매니페스트에서 Activity + LAUNCHER intent-filter가 포함됐는지 확인:
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

- **Kotlin 파일은 반드시 `cat > file << 'EOF'` heredoc으로 작성**한다 (CLAUDE.md 전역 규칙 — IDE MCP 자동 포맷터 회피).
- **커밋하지 않는다**. 파일 생성까지만 수행하고, 커밋 여부는 사용자가 결정한다.
- **MAIN/LAUNCHER intent-filter는 `src/debug/`에만** 둔다. 릴리스 빌드에 섞이지 않도록 `src/debug/AndroidManifest.xml`에만 작성한다.
- **`android:exported="true"`는 필수**다 (API 31+에서 launcher 필요 조건).
- **프로덕션 리소스와 충돌 금지**: `src/debug/`의 리소스 id/레이아웃 이름이 `src/main/`과 겹치지 않도록 `activity_{slug}_test` 형태를 유지.
- **app 모듈 의존성을 늘리지 않는다**. 이미 존재하는 모듈 경계 안에서 해결이 안 되면 사용자에게 확인한 뒤 모듈 선택을 조정한다.
- 컴포넌트 공개 API가 매우 많으면 대표적인 것(setter 2~3개, clearer 1개)만 배치하고, 나머지는 사용자에게 추가할지 묻는다.

## 결과 보고 형식

파일 생성 완료 후 아래를 요약 제공:

- 생성된 파일 목록 (경로)
- 모듈 선택 사유 (왜 그 모듈인지 1줄)
- 앱 서랍 라벨 / 실행 방법
- 빌드 검증 결과
- 다음 단계 (기기 설치 명령)
