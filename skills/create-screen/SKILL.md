---
name: create-screen
description: Figma URL을 받아 HeyDealer Compose Screen을 생성
argument-hint: "[screen_name] [figma_url]"
disable-model-invocation: true
---

# /create-screen

Figma URL을 기반으로 HeyDealer 디자인 시스템을 따르는 Compose Screen을 생성합니다.

사용자 입력: $ARGUMENTS

## 입력

- Screen 이름 (필수) - 예: `DropZeroParticipate`, `MarketNotificationList`
- Figma URL (필수)

## 생성 파일 (의존성 순서)

1. `{ScreenName}UiState.kt` - UiState data class
2. `{ScreenName}UiAction.kt` - UiAction sealed interface
3. `{ScreenName}ViewModel.kt` - ViewModel
4. `{ScreenName}Screen.kt` - Screen Composable + Preview
5. `{ScreenName}Activity.kt` - Activity

---

## 템플릿

### 1. UiState (`{ScreenName}UiState.kt`)

```kotlin
package kr.co.prnd.heydealer.feature.{domain}.{feature}

data class {ScreenName}UiState(
    // 필요한 필드 추가
) {
    companion object {
        val Default = {ScreenName}UiState()
    }
}
```

### 2. UiAction (`{ScreenName}UiAction.kt`)

```kotlin
package kr.co.prnd.heydealer.feature.{domain}.{feature}

sealed interface {ScreenName}UiAction {
    // 필요한 액션 추가
}
```

### 3. ViewModel (`{ScreenName}ViewModel.kt`)

```kotlin
package kr.co.prnd.heydealer.feature.{domain}.{feature}

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class {ScreenName}ViewModel @Inject constructor(
    // dependencies
) : ViewModel() {

    private val _uiState = MutableStateFlow({ScreenName}UiState.Default)
    val uiState: StateFlow<{ScreenName}UiState> = _uiState.asStateFlow()

    fun onItemClick(itemId: String) {
        // handle item click
    }

    fun onRefresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true) }
            // refresh logic
            _uiState.update { it.copy(isRefreshing = false) }
        }
    }

    // Activity로 전달할 이벤트
    sealed interface Event {
        // data object ShowNextScreen : Event
    }
}
```

### 4. Screen (`{ScreenName}Screen.kt`)

```kotlin
package kr.co.prnd.heydealer.feature.{domain}.{feature}

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kr.co.prnd.design.component.HeyDealerScaffold
import kr.co.prnd.design.component.HeyDealerBackToolbar
import kr.co.prnd.design.theme.HeyDealerTheme

/**
 * @FigmaScreen("FIGMA_URL_HERE")
 */
@Composable
internal fun {ScreenName}Screen(viewModel: {ScreenName}ViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val onAction: ({ScreenName}UiAction) -> Unit = remember(viewModel) {
        { action ->
            when (action) {
                // Handle actions
            }
        }
    }

    {ScreenName}Screen(
        uiState = uiState,
        onAction = onAction,
    )
}

@Composable
private fun {ScreenName}Screen(
    uiState: {ScreenName}UiState,
    onAction: ({ScreenName}UiAction) -> Unit,
) {
    HeyDealerScaffold(
        topBar = {
            HeyDealerBackToolbar()
        },
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .padding(innerPadding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
        ) {
            // 화면 내용
        }
    }
}

@Preview(showBackground = true, name = "기본 상태")
@Composable
private fun Preview() {
    HeyDealerTheme {
        {ScreenName}Screen(
            uiState = {ScreenName}UiState(),
            onAction = {},
        )
    }
}

@Preview(showBackground = true, name = "로딩 상태")
@Composable
private fun LoadingPreview() {
    HeyDealerTheme {
        {ScreenName}Screen(
            uiState = {ScreenName}UiState(isLoading = true),
            onAction = {},
        )
    }
}
```

### 5. Activity (`{ScreenName}Activity.kt`)

```kotlin
package kr.co.prnd.heydealer.feature.{domain}.{feature}

import android.content.Context
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import dagger.hilt.android.AndroidEntryPoint
import kr.co.prnd.design.theme.HeyDealerTheme
import kr.co.prnd.heydealer.analytics.Screen
import kr.co.prnd.heydealer.feature.{domain}.{feature}.{ScreenName}ViewModel.Event
import kr.co.prnd.ui.ActivityTemplate
import kr.co.prnd.ui.LibraryComposeActivity

@AndroidEntryPoint
internal class {ScreenName}Activity :
    LibraryComposeActivity<{ScreenName}ViewModel, Event>(
        Screen.{SCREEN_NAME},
    ) {

    override val viewModel: {ScreenName}ViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyEdgeToEdge()

        setContent {
            HeyDealerTheme {
                {ScreenName}Screen(viewModel)
            }
        }
    }

    override fun handleEvent(event: Event) {
        when (event) {
            // Handle events from ViewModel
        }
    }

    companion object : ActivityTemplate<{ScreenName}Activity>()
}
```

---

## UiState/UiAction 가이드

### UiState 프로퍼티 종류

| 용도 | 프로퍼티 | 타입 |
|------|----------|------|
| 로딩 | `isLoading` | `Boolean` |
| 새로고침 | `isRefreshing` | `Boolean` |
| 초기화 완료 | `isInitialized` | `Boolean` |
| 에러 | `errorMessage` | `String?` |
| 리스트 | `items` | `List<T>` |
| 선택 항목 | `selectedItem` | `T?` |
| 입력값 | `inputText` | `String` |
| 유효성 | `isValidInput` | `Boolean` (computed) |

### UiAction 네이밍

| 이벤트 | 네이밍 패턴 |
|--------|-------------|
| 클릭 | `On{Element}Click` |
| 변경 | `On{Element}Change` |
| 제출 | `OnSubmit` |
| 새로고침 | `OnRefresh` |
| 삭제 | `On{Element}Delete` |

---

## 참조 문서

- `../../../rules/heydealer/component-mapping.md` - 컴포넌트 매핑
- `../../../rules/heydealer/design-tokens.md` - 디자인 토큰
- `../../../rules/heydealer/example/compose-screen-example.md` - 코드 예시
