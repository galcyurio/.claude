---
paths:
  - "**/*Test.kt"
  - "**/src/test/**/*.kt"
  - "**/src/androidTest/**/*.kt"
---

# Kotlin 테스트 코드 작성

> 이 규칙은 테스트 파일을 열 때만 로드된다. 커밋 규칙은 `~/.claude/references/commit-rules.md`, Compose 화면 패턴은 `~/.claude/rules/kotlin-compose.md`를 따른다.

## 테스트 코드 스타일

### 함수명과 구조

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

### ViewModel 테스트

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

### 사용 라이브러리

| 용도 | 라이브러리 |
|---|---|
| Mocking | **MockK** — `mockk`, `mockk(relaxed = true)`, `spyk`, `mockkObject`, `every`, `coEvery`, `verify`, `verify(exactly = N)`, `ofType<>()`, `withArg` |
| Assertion | **Truth** — `com.google.common.truth.Truth.assertThat` |
| Coroutines | `kotlinx.coroutines.test.runTest` |
| Runner | JUnit 4 (`@Before`) 또는 JUnit 5 (`@BeforeEach`) — 모듈에 따라 다름 |
| Robolectric | `RobolectricTest` 베이스 (필요한 모듈에서만) |

## 스냅샷 테스트

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

## 테스트 데이터 패턴

- **Fixture**: `*/test/.../fixture/` 디렉토리에 모은다. `XxxFixture`, `XxxEntityFixture` 등.
- **Fake 객체**: Mock 대신 동작을 흉내내는 Fake를 우선 고려한다 (`FakeTradeLocalDataSource`, `FakeTradeRemoteDataSource`, `FakeCarRepository`).
- **Subject + SubjectFactory**: 복잡한 도메인 객체는 `XxxSubject` + `XxxSubjectFactory`로 생성.
- 간단한 경우 `private fun createXxx(...)` factory function으로 본문에 둠.
- `mock` 대신 `spy` 선호 — 부분 stub만 필요한 케이스에서 명시적.

## 패키지 배치

각 모듈의 `src/test/{java|kotlin}/` 안에서:

- `domain/src/test/.../usecase/` — UseCase 테스트
- `domain/src/test/.../fixture/` — 도메인 fixture
- `domain/src/test/.../model/` — 순수 도메인 모델 테스트
- `data/src/test/.../impl/` — Repository 구현체 테스트
- `data/src/test/.../fixture/` — Fake DataSource, Entity fixture
- `analytics/src/test/.../` — Analytics 구현체 테스트 (`XxxImplTest`)
- `feature/src/test/.../` 또는 `ui/src/test/.../` — ViewModel, State, Model 테스트
- `design/src/test/kotlin/.../component/` — Compose 컴포넌트 스냅샷 테스트

## 정책

- **Gradle `testFixtures` 기능은 비활성화**하고, fixture는 `src/test/` 안에 둔다 (HDA-20489).
- Robolectric을 쓰는 케이스는 `RobolectricTest` 베이스 클래스를 사용 (HDA-20307).
- 스냅샷 이미지는 압축(tinypng) 적용하지 않고, CI exclude 경로에 등록한다.
