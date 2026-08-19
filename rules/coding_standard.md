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

## 커밋 규칙

커밋 단위 분리, 커밋 메시지 표현, 테스트 커밋 규칙은 `~/.claude/rules/git.md`로 옮겼다.

## Android Compose 코드 패턴

Kotlin 파일(`**/*.kt`)을 열 때 자동 로드되는 `~/.claude/rules/kotlin-compose.md`로 옮겼다. Activity 골격, Screen 함수 2단계 분리, UiAction 네이밍, Preview 다중 작성, Composable 파일 내부 구성, 패키지 배치가 거기 있다.

## 테스트 코드 스타일

테스트 파일을 열 때 자동 로드되는 `~/.claude/rules/kotlin-test.md`로 옮겼다. 함수명·given/when/then 구조, ViewModel 테스트, 사용 라이브러리, 스냅샷 테스트, 테스트 데이터 패턴, 패키지 배치, 정책이 거기 있다.
