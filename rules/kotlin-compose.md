---
paths:
  - "**/*.kt"
---

# Android Compose 코드 패턴

> 이 규칙은 Kotlin 파일(`**/*.kt`)을 열 때만 로드된다. 커밋 단위·커밋 메시지 규칙은 `~/.claude/rules/git.md`, 테스트 코드 스타일은 `~/.claude/rules/kotlin-test.md`를 따른다.

> Android 프로젝트(heydealer, for-dealer, inspector, revolt)에서 공통으로 적용되는 패턴이다. 레이어 구조, ViewModel, Repository, Model 매핑 등 상세 규칙은 `~/.android-ai-prompts/rules/`에 별도 정리되어 있으며 이 섹션은 그 외 화면 골격/네이밍 패턴을 보완한다.

## Activity 골격

Compose Activity는 다음 골격을 따른다.

```kotlin
@AndroidEntryPoint
internal class XxxActivity :
    LibraryComposeActivity<XxxViewModel, Event>(Screen.XXX) {

    override val viewModel: XxxViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyEdgeToEdge(...)

        setContent {
            HeyDealerTheme { // 또는 RevoltTheme
                XxxScreen(viewModel)
            }
        }
    }

    override fun handleEvent(event: Event) {
        // event 처리, 없으면 no-op
    }

    companion object : ActivityTemplate<XxxActivity>()
}
```

- `@AndroidEntryPoint` + `LibraryComposeActivity<VM, Event>` 상속
- `override val viewModel: ... by viewModels()`
- `applyEdgeToEdge(...)` 호출은 기본
- 진입 트랜지션이 다르면 `activityTransition = ActivityTransitionType.BOTTOM_UP` 같이 명시
- `companion object : ActivityTemplate<XxxActivity>()`로 진입점을 통일

## Screen 함수 2단계 분리

Composable Screen은 **외부(ViewModel 받는)** 함수와 **내부(uiState/onAction 받는)** 함수로 분리한다. **Preview가 ViewModel 없이 호출할 수 있게** 하기 위함이다.

```kotlin
@Composable
internal fun XxxScreen(viewModel: XxxViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val onAction: (XxxUiAction) -> Unit = remember(viewModel) {
        { action ->
            when (action) {
                is XxxUiAction.OnItemClick -> viewModel.selectItem(action.item)
                XxxUiAction.OnRefresh -> viewModel.fetch()
            }
        }
    }
    XxxScreen(uiState = uiState, onAction = onAction)
}

@Composable
private fun XxxScreen(
    uiState: XxxUiState,
    onAction: (XxxUiAction) -> Unit,
) {
    // 실제 UI
}
```

- 외부 함수: `internal fun` — uiState collect, onAction 정의
- 내부 함수: `private fun` — 실제 UI 구현
- `onAction`은 `remember(viewModel) { ... }`로 감싸 재구성 최소화
- ViewModel 메서드는 UiAction 이름을 미러링한 `onXxx()`가 **아니라** 행위 동사로 짓는다 (`onItemClick` ❌ → `selectItem` ✅). 상세: `~/.android-ai-prompts/rules/common/viewmodel.md` 메서드 네이밍

## UiAction 네이밍

UiAction은 `internal sealed interface`로 선언하고 `On{이벤트}` 접두사를 사용한다. 데이터가 있으면 `data class`, 없으면 `data object`.

```kotlin
internal sealed interface XxxUiAction {
    data class OnItemClick(val item: ItemModel) : XxxUiAction
    data class OnTextChange(val text: String) : XxxUiAction
    data object OnRefresh : XxxUiAction
    data object OnConfirmClick : XxxUiAction
    data object OnBackClick : XxxUiAction
    data object OnNextPageRequest : XxxUiAction
}
```

자주 쓰는 형태:

- 클릭/누름: `OnXxxClick`
- 값 변경: `OnXxxChange`
- 화면 동작: `OnRefresh`, `OnBackClick`, `OnNextPageRequest`

> ViewModel `Event`(외부로 나가는 신호)는 `~/.android-ai-prompts/rules/common/viewmodel.md`의 `{행위}{대상}{결과}` 네이밍을 따른다. UiAction(사용자 입력)과 Event(결과 신호)는 서로 다른 컨셉이다.

## Preview 다중 작성

한 Composable당 상태별로 Preview를 여러 개 작성한다. 이름은 상태가 드러나도록 짓는다.

```kotlin
@Preview
@Composable
private fun PreviewLoading() { ... }

@Preview
@Composable
private fun PreviewEmpty() { ... }

@Preview
@Composable
private fun Preview() { ... }   // 기본 상태

// 또는 상태 구분이 명확한 경우 번호로
@Preview
@Composable
private fun Preview1() { ... }   // unread
@Preview
@Composable
private fun Preview2() { ... }   // read
```

- `private fun`으로 외부 노출 차단
- Preview 안에서는 하드코딩 텍스트/모델 허용 (`~/.android-ai-prompts/rules/common/string-resource.md` 예외)
- UiState는 `XxxUiState.Default.copy(...)` 패턴으로 변형해 사용

## Composable 파일 내부 구성

한 컴포넌트 파일에는 외부 API + private inner Composable + 다중 Preview를 함께 둔다.

```kotlin
@Composable
fun XxxComponent(...)        // public API

@Composable
private fun Thumbnail(...)   // 내부 부품
@Composable
private fun RedDot(...)      // 내부 부품

@Preview
@Composable
private fun Preview1() { ... }
@Preview
@Composable
private fun Preview2() { ... }
```

내부 부품은 파일 밖에서 쓰일 가능성이 없으면 `private fun`으로 같은 파일에 둔다. 다른 화면에서 재사용될 가능성이 보이면 `feature/.../section/` 또는 `feature/.../component/`로 빼낸다.

### 파일 레벨 상수는 구현 아래·Preview 위에 선언

파일 레벨 `private val`/`private const val` 상수(치수, 키, 기본값 등)는 import 아래 상단이 아니라 **실제 구현(Composable/함수)들 중 가장 아래**, 그리고 **Preview 위**에 선언한다. 파일을 열었을 때 핵심 구현이 먼저 보이고, Preview는 맨 끝에 모이도록 하기 위함이다.

```kotlin
@Composable
fun XxxComponent(...)        // public API
@Composable
private fun XxxPart(...)     // 내부 부품

private val XxxHeight = 200.dp      // 구현 아래, Preview 위
private const val MAX_COUNT = 10

@Preview
@Composable
private fun Preview() { ... }
```

## 패키지 배치

Clean Architecture 레이어 안에서 다음 구조를 사용한다.

- `feature/{도메인}/{화면명}/` — Activity, Screen, ViewModel, UiState, UiAction 5종
- `feature/{도메인}/{화면명}/component/` — 화면 전용 작은 컴포넌트
- `feature/{도메인}/section/` — 여러 화면에서 재사용되는 큰 섹션
- `presentation/model/XxxModel.kt` — UI 표현 모델
- `domain/{model, usecase, repository}/`
- `data/{model, source, impl}/`
- `remote/{model, impl}/`, `local/{model, impl}/`

상세 의존성 규칙은 `~/.android-ai-prompts/rules/common/architecture.md`를 따른다.
