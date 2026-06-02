---
name: create-composable-with-view
description: HeyDealer 또는 Revolt 테마의 AbstractComposeView 와 내부 Composable 함수를 함께 생성하는 스킬. 사용자가 'create-composable-with-view', 'ComposeView 만들어', 'XML에서 쓸 수 있는 composable', 'AbstractComposeView 추가', 'View로 감싼 composable', 'ComposeView 골격 추가' 등을 요청할 때 이 스킬을 사용해야 한다.
argument-hint: "[name] [target_dir_or_fqcn]"
---

# /create-composable-with-view

HeyDealer 또는 Revolt 테마의 `AbstractComposeView` 클래스 + 내부 `Composable` 함수 + `@Preview`를 한 파일에 생성한다. XML 레이아웃에서 참조 가능한 형태다.

사용자 입력: $ARGUMENTS

## 입력

- **name** (필수): PascalCase 컴포넌트 이름. 생성되는 클래스는 `{name}View`가 된다. 예) name=`CarNumberPlateField` → 클래스 `CarNumberPlateFieldView`
- **target_dir_or_fqcn** (필수): 디렉터리 절대경로 또는 FQCN

입력이 부족하면 `AskUserQuestion`으로 보완한다.

## 실행 단계

### 1. 입력 파싱

`$ARGUMENTS`에서 `name`과 `target` 추출. 다음 4가지 형식을 모두 허용:

| 입력 형태 | 해석 |
|----------|------|
| `MyButton app/.../foo/` | name = `MyButton`, target_dir 그대로 |
| `MyButton kr.co.prnd.heydealer.foo` | name = `MyButton`, package에서 디렉터리 역추론 |
| `kr.co.prnd.heydealer.foo.MyButton` | FQCN으로 해석. name + package 동시 추출 |
| `MyButton` (위치 미지정) | `AskUserQuestion`으로 위치 질문 |

자연어 입력으로 진입한 경우, 컨텍스트에 `Activity`·`화면`·`Screen` 단어가 있으면 다른 스킬 사용을 안내. `View`·`XML`·`ComposeView` 단어가 없으면 `AskUserQuestion`으로 종류 확인.

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

생성 대상 `{target_dir}/{name}.kt`가 이미 존재하면 `AskUserQuestion`으로 덮어쓰기 확인.
파일명은 `{name}.kt`이며, 클래스명은 `{name}View`다 (예: name=`Foo` → 파일 `Foo.kt`, 클래스 `FooView`).

### 6. 템플릿 로드 + 치환

- `~/.claude/skills/create-composable-with-view/templates/{Theme}.kt.template` 읽기
- `${NAME}` → `name`, `${PACKAGE_NAME}` → 추론 패키지
- `Write` 도구로 `{target_dir}/{name}.kt` 저장

### 7. 자동 커밋

생성된 파일을 자동으로 커밋한다.

1. **Issue ID 추출**: `git branch --show-current` 결과에서 `HDA-\d+` 정규식 추출
2. **추출 실패 시**: `AskUserQuestion`으로 Issue ID 입력 (옵션: "직접 입력" / "없이 진행")
3. **staging**: `git add`는 생성된 파일 절대경로만 지정 (working tree의 다른 변경 보호)
4. **commit**: 메시지 형식
   - Issue ID 있음: `HDA-XXX feat: 골격 구현을 추가한다`
   - Issue ID 없음: `feat: 골격 구현을 추가한다`
   - Claude Code 기본 Co-Authored-By trailer를 추가한다
5. 커밋 실패 시 에러 보고, staged 상태 유지

### 8. 결과 보고

- 생성된 파일 절대경로
- 추론된 테마/패키지
- 생성된 클래스명(`{name}View`)과 함수명(`{name}`) 안내
- 생성된 커밋 hash (단축 형식)

## 에러 처리

| 케이스 | 처리 |
|--------|------|
| `name`/`target` 누락 | `AskUserQuestion`으로 보완 |
| FQCN 마지막 세그먼트가 PascalCase 아님 | 에러: "FQCN 형식이 올바르지 않습니다: {입력}" |
| `target_dir` 미존재 | `AskUserQuestion`으로 생성/변경/중단 확인 |
| 테마 추론 실패/충돌 | `AskUserQuestion`으로 테마 확인 |
| 패키지 추론 실패 | `AskUserQuestion`으로 패키지 직접 입력 |
| 파일 충돌 | `AskUserQuestion`으로 덮어쓰기 확인 |
| 템플릿 파일 없음 | 에러: "템플릿 파일을 찾을 수 없습니다: {경로}" |
| `name` non-PascalCase | 경고 후 그대로 사용 |
| Issue ID 추출 실패 | `AskUserQuestion`으로 직접 입력 또는 "없이 진행" |
| git 커밋 실패 (hook 등) | 에러 보고, staged 상태 유지 |

## 주의사항

- **`git add`는 정확히 생성된 파일 절대경로만 지정**한다. working tree의 다른 변경을 보호한다.
- 파일명은 `{name}.kt`, 클래스명은 `{name}View`다. 사용자가 혼동할 수 있으므로 결과 보고에 명시한다.
- 커밋 메시지는 `~/.claude/rules/git-commit-message.md` 규칙을 따른다.
