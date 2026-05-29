# 코딩 표준

## TODO 주석 규칙

TODO 주석은 `TODO([issue id, optional]): xxx` 포맷으로 작성한다.

- 작업 맥락(Jira 이슈, PR 설명, 직전 대화 등)에서 **파악된 이슈 ID가 있는 경우에만** 괄호 안에 명시한다.
- 이슈 ID가 확인되지 않으면 비워둔다. 임의로 추정한 ID를 적지 않는다.

| 상황 | 형식 |
|------|------|
| 이슈 ID가 파악되지 않은 경우 | `TODO: xxx` |
| 이슈 ID가 파악된 경우 | `TODO(PROJ-12345): xxx` |

### 예시

```
// TODO: 로그인 기능 추가
// TODO(PROJ-12345): 로그인 기능 추가
```

## 커밋 단위

> 커밋 메시지 형식 자체는 `~/.claude/rules/git-commit-message.md`를 따른다. 이 섹션은 **단위 분리**와 **메시지 표현 패턴**을 보완한다.

### 한 커밋 = 하나의 논리적 변경

- 한 커밋은 **1~3 파일, 수십 라인** 규모를 기본으로 한다.
- 골격(skeleton) 추가나 sealed interface 분리처럼 한 단위가 커도 **단일 논리 단위면 단일 커밋**으로 유지한다.
- 한 PR(Jira 이슈) = 여러 작은 커밋. 큰 변경을 한 커밋에 몰지 않는다.
- **리뷰/디자인 반영 수정도 별도 커밋**으로 분리한다 (예: "디자인에 맞게 색상을 변경한다", "수정 누락된 id를 수정한다").
- **10 파일을 넘는 변경은 의도된 대규모 리팩토링/리네임일 때만** 허용한다.

### Compose/MVI 화면 작업 분리 순서

새 Compose 화면을 추가할 때는 아래 순서로 커밋을 쪼갠다. 각 단계가 독립 커밋이다.

1. **API/DTO 추가** (필요 시 선행) — 아래 "API/DTO 작업 분리" 참고
2. **골격(skeleton) 추가**: Activity + Screen + UiState + UiAction + ViewModel + Manifest 등록 → 한 커밋
3. **텍스트 리소스 추가** (strings.xml 등)
4. **UiState 필드 추가**
5. **UiAction 항목 추가**
6. **UI 본문 구현** (Composable 채우기)
7. **개별 기능 단위로 분리** (edge-to-edge 적용, LazyColumn 전환, 로딩 인디케이터, 페이징 등 각각 별도 커밋)
8. **fix**: 리뷰/디자인 반영, 누락 수정, 엣지 케이스 처리

### API/DTO 작업 분리

서버 API의 요청·응답을 모델링하는 DTO(`Response`/`Request`/`Entity`/`Local`/도메인 모델/`Model`)는 **화면 작업과 분리해 별도 커밋**한다. 한 PR에서 여러 DTO를 다루면 DTO 단위로도 쪼갠다.

분리 단위 — 작업 성격에 맞춰 선택:

- **각 layer 한 번에 추가** (보통): `feat: 각 layer에 X DTO를 추가한다` — Response/Request + Entity + Domain + Model을 묶음
- **layer별 분리** (큰 모델): `feat(API): X Response DTO를 추가한다`, `feat: X 도메인 모델을 추가한다` 식으로 layer별 커밋
- **Mapper만 추가**: `feat(DTO): toDomain(), toData(), toLocal() 함수를 추가한다`
- **필드만 추가/변경**: `feat(DTO): recall 필드를 추가한다`, `feat(API): 예약 상세 DTO에 car, nickname을 추가한다`
- **DTO 선언과 필드 채우기 분리**: `feat: CarDetail DTO 선언하고 최상위 필드들을 추가한다` → 이후 `feat: 하위 DTO들에 Mapper를 추가한다` 식으로 단계적 채움
- **여러 DTO**: 각 DTO마다 별도 커밋

권장 scope:

- `feat(API):` — API 엔드포인트 관점 (Response/Request 추가, 필드 추가)
- `feat(DTO):` — DTO 자체 관점 (Mapper, 공통 필드)
- `feat(post):` / `feat(get):` — HTTP 메서드별 구분이 필요한 경우

> 정의 자체와 layer 간 매핑 규칙은 `~/.android-ai-prompts/rules/common/model-mapping.md`를 따른다. 이 섹션은 **커밋 분리 단위**만 다룬다.

### 사용할 태그

- 기본: `feat`, `refactor`, `fix`, `test` 중에서 선택한다.
- 빌드/CI 설정 변경에 한해 `build`, `ci`를 사용한다.
- `chore`, `docs`, `style`은 거의 사용하지 않는다. 다른 태그로 표현되지 않는 경우에만 쓴다.

### 커밋 메시지 표현

#### 종결어 — "~다" 끝맺음

항상 `~한다` 형태의 명령문체로 끝낸다. 인용/특수 케이스가 아닌 한 예외 없다.

상황별로 다음 종결어를 우선 고려한다:

- 신규 항목 추가: `추가한다`
- 값/상태 변경: `변경한다`
- 불필요한 코드/리소스 정리: `제거한다`
- 버그/오타 수정: `수정한다`
- 화면/요소 노출: `보여준다`, `노출한다`
- 책임/타입 분리: `분리한다`
- 기능 구현: `구현한다`
- 라이브러리/submodule 업데이트: `최신화한다`
- 이벤트/예외 처리: `처리한다`
- 상수/필드 선언: `선언한다`
- 파라미터/이벤트 전달: `전달한다`
- 새 API/도구 채택: `사용한다`
- 위치/책임 이동: `이동한다`, `옮긴다`
- 구조 전환: `마이그레이션한다`, `교체한다`, `대체한다`, `리네임한다`
- 정렬/정리: `정렬한다`, `재정렬한다`, `정리한다`
- 적용/개선: `적용한다`, `개선한다`

#### 범위(scope) 표기

한 이슈 안에서 작업이 큰 묶음으로 나뉘면 `태그(범위):` 형태로 표기한다. 영문/한글, 약어/구절 모두 자유롭게 사용 가능하며 길이 제약 없다.

자주 쓰는 scope 유형:

- 레이어 약어: `feat(UI)`, `feat(API)`, `feat(DTO)`, `refactor(Preview)`
- 한글 도메인: `feat(개인정보 처리방침)`, `feat(구매 기록)`, `feat(출고 정보)`, `feat(은행 선택 팝업)`, `feat(홈 탭)`, `feat(보험 이력)`
- 작업 단계: `refactor(사전 작업)`, `feat(사전 작업)` — 본 작업 전 준비 단계 표시 패턴
- 액션/요소: `feat(복사)`, `feat(여백)`, `feat(툴팁)`, `feat(refresh)`, `feat(boilerplate)`, `feat(loading)`

#### 단순 리네임 표기

식별자/도메인 용어 리네임은 `이전 -> 새 이름` 형태로만 적는다. 식별자, 한글 변수명, 문구, 파일명 모두 동일하게 적용한다.

```
HDA-20309 refactor: isPaymentConsultationRequired -> isPaymentConsultationRequested
HDA-20520 refactor: CardRow -> CardItem
HDA-18944 refactor: GetDefaultCardUseCase -> SubscribeDefaultCardUseCase
HDA-21145 refactor: composeNumberPlateEnabled -> 번호판_Compose_전환_여부
HDA-20224 feat: 세무 대리비 -> 세무 상담비
HDA-19203 feat: 모두보기 -> 모두 보기
HDA-10842 refactor: build_app_by_pr.yml -> build.yml
```

#### 본문(body) 작성 기준

- 기본적으로 **1줄 요약만** 작성한다.
- sealed interface 도입, 구조 변경, 다중 호출처 영향처럼 **의도/배경 설명이 필요할 때만** body를 추가한다.
- body에서는 **변경 이유, 영향 범위, 향후 확장 의도**를 적는다. "어떻게 했는지"가 아니라 "왜 이렇게 했는지"를 남긴다.

## 코드 스타일

### 표현 분리 패턴

- **A 대신 B를 사용한다**: 기존 구현을 대체할 때 우선 고려.
- **불필요한 X를 제거한다**: 미사용 코드/리소스/래퍼는 발견 즉시 별도 커밋으로 정리.
- **X를 호출처로 옮긴다**: 가드/검증 책임을 사용자(호출 측)로 옮겨 내부를 단순화.
- **sealed interface로 분리한다**: 화면 진입 타입, 상태 분기 등을 enum/Boolean 대신 sealed로 표현해 확장 여지를 만든다.
- **A를 B 기반으로 변경한다**: 예) Column → LazyColumn, ViewBinding → Compose, Get*UseCase → Subscribe*UseCase.

### 기획자/유저 관점

기능 단위 커밋은 **사용자가 보게 될 변화** 중심으로 작성한다 (`~/.claude/rules/git-commit-message.md` 규칙과 동일).

- Good: `feat: 알림 모두보기 클릭 시 가격 알림 화면으로 진입한다`
- Bad: `feat: HomeViewModel에 onNotificationSeeAllClick 핸들러를 추가한다`

내부 리팩토링/구조 변경에서만 클래스/함수명을 직접 언급한다.

## Android Compose 코드 패턴

> Android 프로젝트(heydealer, for-dealer, inspector, revolt)에서 공통으로 적용되는 패턴이다. 레이어 구조, ViewModel, Repository, Model 매핑 등 상세 규칙은 `~/.android-ai-prompts/rules/`에 별도 정리되어 있으며 이 섹션은 그 외 화면 골격/네이밍 패턴을 보완한다.

### Activity 골격

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

### Screen 함수 2단계 분리

Composable Screen은 **외부(ViewModel 받는)** 함수와 **내부(uiState/onAction 받는)** 함수로 분리한다. **Preview가 ViewModel 없이 호출할 수 있게** 하기 위함이다.

```kotlin
@Composable
internal fun XxxScreen(viewModel: XxxViewModel) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val onAction: (XxxUiAction) -> Unit = remember(viewModel) {
        { action ->
            when (action) {
                is XxxUiAction.OnItemClick -> viewModel.onItemClick(action.item)
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

### UiAction 네이밍

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

### Preview 다중 작성

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

### Composable 파일 내부 구성

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

### 패키지 배치

Clean Architecture 레이어 안에서 다음 구조를 사용한다.

- `feature/{도메인}/{화면명}/` — Activity, Screen, ViewModel, UiState, UiAction 5종
- `feature/{도메인}/{화면명}/component/` — 화면 전용 작은 컴포넌트
- `feature/{도메인}/section/` — 여러 화면에서 재사용되는 큰 섹션
- `presentation/model/XxxModel.kt` — UI 표현 모델
- `domain/{model, usecase, repository}/`
- `data/{model, source, impl}/`
- `remote/{model, impl}/`, `local/{model, impl}/`

상세 의존성 규칙은 `~/.android-ai-prompts/rules/common/architecture.md`를 따른다.

## 테스트 작성 방식

### 커밋 단위 (TDD 사이클)

테스트가 포함된 PR은 **TDD red-green-refactor 사이클**을 그대로 커밋 히스토리로 남긴다.

- **테스트 케이스 하나 = 한 커밋**으로 분리한다.
- 한 PR 안에서 `test` → `refactor` → `test` → `fix` → `refactor`가 인터리브된다.
- 도메인 변경으로 인한 **"테스트 코드 컴파일 오류 수정"도 별도 `test` 커밋**으로 둔다 (구현 커밋과 묶지 않음).
- 테스트 구조 개선(`given/when` 분리, 클래스명 변경, 불필요한 케이스 제거)도 각각 별도 `test` 커밋.

### 커밋 메시지

#### 새 테스트 케이스 추가

테스트 함수명(요구사항 문장)을 그대로 메시지에 사용한다.

```
HDA-9414 test: 탭이 유저에 의해 클릭되면 클릭 이벤트를 기록한다
HDA-9414 test: 탭이 기본값에 의해 변경되면 클릭 이벤트를 기록하지 않는다
HDA-9414 test: 스크롤을 내려서 아래 컨텐츠가 보이는 상태에서, 화면을 나가면, 체류 시간 이벤트를 기록한다
HDA-10692 test: 처음으로 가져오는 경우와 강제로 새로 가져오는 경우의 테스트 케이스를 추가한다
HDA-18548 test(DAO): Flow로 동기화되는지 확인하는 테스트 케이스를 추가한다
```

- 테스트 함수명과 커밋 메시지가 1:1 대응되는 것이 이상적.
- 여러 케이스를 묶을 때만 `테스트 케이스를 추가한다` 같은 추상화된 표현 사용.
- DAO/UseCase/특정 화면 등 범위가 있으면 `test({범위}):` scope를 활용.

#### 후속/유지보수

```
HDA-15776 test: 테스트 코드 컴파일 에러를 수정한다       # 도메인 변경 후속
HDA-14809 test: 불필요한 테스트 케이스를 제거한다
HDA-11196 test: 사용하지 않는 Fixture를 제거한다
HDA-10531 test: 테스트 코드를 간략하게 변경한다
HDA-9414  test: given, when절을 모두 별도 함수로 분리한다
HDA-9414  test: 구현체에 대한 테스트이므로 이름을 ImplTest로 변경한다
HDA-16530 test: mock 객체로 대신 spy 객체를 사용한다
```

#### 스냅샷 테스트

```
HDA-20384 test: 스냅샷 테스트를 추가한다
HDA-19181 test: RevoltChip 스냅샷 테스트를 추가한다
HDA-16177 test: focused 상태의 스냅샷 테스트를 추가한다
HDA-20596 test: 스냅샷 테스트 이미지를 변경한다
```

- 신규 스냅샷 추가, 상태별 추가, 이미지 변경 모두 **각각 별도 커밋**.

### 테스트 코드 스타일

#### 함수명과 구조

```kotlin
@Test
fun `탭이 유저의 클릭에 의해 변경되면 클릭 이벤트를 기록한다`() {
    // given
    val totalInfoTab = TotalInfoTab.TIMELINE

    // when
    `유저가 탭을 변경한다`(totalInfoTab)

    // then
    verify(exactly = 1) {
        Analytics.event(withArg { actual ->
            val expected = AnalyticsEvent.ClickTotalInfoTab(
                totalInfoTab = totalInfoTab,
                totalInfoHashId = totalInfoHashId,
            )
            assertThat(actual).isEqualTo(expected)
        })
    }
}

private fun `유저가 탭을 변경한다`(totalInfoTab: TotalInfoTab) {
    val tabEvent = TotalInfoTabAnalytics.Event.OnTabChangeByUser(totalInfoTab)
    totalInfoTabAnalytics.onEvent(tabEvent)
}
```

- **테스트 함수명은 한글 백틱** — `X면 Y한다` 형식의 요구사항 문장.
- `// given`, `// when`, `// then` 주석으로 3단 구조를 항상 표시.
- **헬퍼 함수도 한글 백틱**으로 만들어 `// when` 본문이 자연어 문장처럼 읽히게 한다.
- 구현체 테스트 클래스는 `XxxImplTest` 네이밍.

#### ViewModel 테스트

```kotlin
class XxxViewModelTest : ViewModelTest() {
    private lateinit var viewModel: XxxViewModel
    private val xxxUseCase: XxxUseCase = mockk(relaxed = true)

    @Before
    fun setUp() {
        every { xxxUseCase(any(), any()) }.returns(flowOf(DataResource.success(Unit)))
    }

    @Test
    fun `입력한 메모가 있으면, 해당 메모를 노출한다`() {
        // given
        val expected = "가나다라"
        viewModel = createViewModel(memo = expected)

        // when
        val actual = viewModel.memo.value

        // then
        assertThat(actual).isEqualTo(expected)
    }

    private fun createViewModel(
        totalInfoHashId: String = "",
        memo: String? = null,
    ): XxxViewModel { ... }
}
```

- `ViewModelTest`(`kr.co.prnd.test.android.jvm.ViewModelTest`) 베이스 클래스 상속.
- `mockk(relaxed = true)` 기본 사용, 부분 stub이 필요하면 `spyk`로 감싼다 (mock보다 spy 선호).
- `private fun createViewModel(...)` factory function으로 인스턴스 생성을 모은다.

#### 사용 라이브러리

| 용도 | 라이브러리 |
|---|---|
| Mocking | **MockK** — `mockk`, `mockk(relaxed = true)`, `spyk`, `mockkObject`, `every`, `coEvery`, `verify`, `verify(exactly = N)`, `ofType<>()`, `withArg` |
| Assertion | **Truth** — `com.google.common.truth.Truth.assertThat` |
| Coroutines | `kotlinx.coroutines.test.runTest` |
| Runner | JUnit 4 (`@Before`) 또는 JUnit 5 (`@BeforeEach`) — 모듈에 따라 다름 |
| Robolectric | `RobolectricTest` 베이스 (필요한 모듈에서만) |

### 스냅샷 테스트

디자인 시스템 컴포넌트는 스냅샷 테스트로 시각 회귀를 잡는다. 주로 `revolt-android`의 `design` 모듈에서 사용.

```kotlin
class RevoltChipTest : RevoltSnapshotTest("Chip") {
    @Test
    fun default() = capture {
        RevoltChip(text = "chip", selected = false, onClick = {})
    }

    @Test
    fun selected() = capture {
        RevoltChip(text = "chip", selected = true, onClick = {})
    }

    @Test
    fun longText() = capture {
        RevoltChip(text = LoremIpsum(10).values.joinToString(), selected = false, onClick = {})
    }
}
```

- `XxxSnapshotTest("ComponentName")` 베이스 클래스를 상속한다 (`RevoltSnapshotTest`, `HeyDealerSnapshotTest`).
- `capture { ... }` DSL로 Compose 트리를 캡처.
- **스냅샷 테스트 함수명은 영문**(상태/케이스 이름): `default`, `selected`, `focused`, `longText` 등.
- 상태마다 별도 테스트 함수로 쪼갠다.
- 스냅샷 이미지는 tinypng 적용하지 않으며, lint exclude 경로에 등록.

### 테스트 데이터 패턴

- **Fixture**: `*/test/.../fixture/` 디렉토리에 모은다. `XxxFixture`, `XxxEntityFixture` 등.
- **Fake 객체**: Mock 대신 동작을 흉내내는 Fake를 우선 고려한다 (`FakeTradeLocalDataSource`, `FakeTradeRemoteDataSource`, `FakeCarRepository`).
- **Subject + SubjectFactory**: 복잡한 도메인 객체는 `XxxSubject` + `XxxSubjectFactory`로 생성.
- 간단한 경우 `private fun createXxx(...)` factory function으로 본문에 둠.
- `mock` 대신 `spy` 선호 — 부분 stub만 필요한 케이스에서 명시적.

### 패키지 배치

각 모듈의 `src/test/{java|kotlin}/` 안에서:

- `domain/src/test/.../usecase/` — UseCase 테스트
- `domain/src/test/.../fixture/` — 도메인 fixture
- `domain/src/test/.../model/` — 순수 도메인 모델 테스트
- `data/src/test/.../impl/` — Repository 구현체 테스트
- `data/src/test/.../fixture/` — Fake DataSource, Entity fixture
- `analytics/src/test/.../` — Analytics 구현체 테스트 (`XxxImplTest`)
- `feature/src/test/.../` 또는 `ui/src/test/.../` — ViewModel, State, Model 테스트
- `design/src/test/kotlin/.../component/` — Compose 컴포넌트 스냅샷 테스트

### 정책

- **Gradle `testFixtures` 기능은 비활성화**하고, fixture는 `src/test/` 안에 둔다 (HDA-20489).
- Robolectric을 쓰는 케이스는 `RobolectricTest` 베이스 클래스를 사용 (HDA-20307).
- 스냅샷 이미지는 압축(tinypng) 적용하지 않고, CI exclude 경로에 등록한다.
