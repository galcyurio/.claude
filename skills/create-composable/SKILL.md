---
name: create-composable
description: HeyDealer 또는 Revolt 테마의 Composable 함수와 @Preview 를 생성하는 스킬. 사용자가 'create-composable', 'Composable 만들어', 'composable 추가', 'compose 컴포넌트 만들어', '컴포저블 생성', '골격 구현 추가' 등을 요청할 때 이 스킬을 사용해야 한다. Activity나 ViewModel이 필요한 화면 생성에는 사용하지 않는다 (create-compose-screen 사용).
argument-hint: "[name] [target_dir_or_fqcn]"
---

# /create-composable

HeyDealer 또는 Revolt 테마의 Composable 함수 1개와 `@Preview` 를 생성한다.

사용자 입력: $ARGUMENTS

## 입력

- **name** (필수): PascalCase 컴포넌트 이름. 예) `MyButton`, `CarNumberPlateField`
- **target_dir_or_fqcn** (필수): 디렉터리 절대경로 또는 FQCN. 예) `app/feature/market/src/main/kotlin/kr/co/prnd/heydealer/market/foo/`, `kr.co.prnd.heydealer.market.foo.MyButton`

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

자연어 입력(`골격 구현 추가` 등)으로 진입한 경우, 컨텍스트에 `View`·`Activity`·`화면`·`Screen` 같은 단어가 있으면 다른 스킬을 사용하도록 안내 후 종료. 모호하면 `AskUserQuestion`으로 종류(Composable / View / Screen) 확인.

### 2. target 정규화

- FQCN(점 포함 + 마지막 세그먼트가 PascalCase) → 디렉터리로 변환 + `name` 자동 추출
- 디렉터리 경로 → 그대로 사용
- 존재하지 않으면 `AskUserQuestion`으로 생성/변경/중단 확인

### 3. 테마 추론

- 경로에 `heydealer` 또는 `HeyDealer` 포함 → HeyDealer
- 경로에 `revolt` 또는 `Revolt` 포함 → Revolt
- 둘 다 매칭 또는 둘 다 매칭 안 됨 → `AskUserQuestion`으로 테마 확인

### 4. 패키지 추론

`src/main/kotlin/` 또는 `src/main/java/` 아래 경로를 점으로 연결. 추론 실패 시 `AskUserQuestion`으로 직접 입력 요청.

### 5. 파일 충돌 검사

생성 대상 `{target_dir}/{name}.kt`가 이미 존재하면 `AskUserQuestion`으로 덮어쓰기 확인.

### 6. 템플릿 로드 + 치환

- `~/.claude/skills/create-composable/templates/{Theme}.kt.template` 읽기 (`{Theme}`는 `HeyDealer` 또는 `Revolt`)
- `${NAME}` → `name`, `${PACKAGE_NAME}` → 추론 패키지
- `Write` 도구로 `{target_dir}/{name}.kt` 저장

### 7. 자동 커밋

생성된 파일을 자동으로 커밋한다.

1. **Issue ID 추출**: `git branch --show-current` 실행 후 결과에서 `HDA-\d+` 정규식 추출
2. **추출 실패 시**: `AskUserQuestion`으로 Issue ID 입력 받기. 옵션은 "직접 입력 (HDA-XXX)" / "Issue ID 없이 진행" 2가지.
3. **staging**: `git add`는 생성된 파일의 절대경로만 지정한다 (working tree의 다른 변경은 staging하지 않는다)
4. **commit**: 메시지 형식
   - Issue ID 있음: `HDA-XXX feat: 골격 구현을 추가한다`
   - Issue ID 없음: `feat: 골격 구현을 추가한다`
   - 본문에 `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer 추가
5. 커밋 실패 시 (pre-commit hook 등) 에러를 보고하고 staged 상태 유지

### 8. 결과 보고

- 생성된 파일 절대경로
- 추론된 테마/패키지
- 생성된 커밋 hash (단축 형식, `git rev-parse --short HEAD`)

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
| `name` non-PascalCase | 경고 후 그대로 사용 (자동 변환 없음) |
| Issue ID 추출 실패 | `AskUserQuestion`으로 직접 입력 또는 "없이 진행" |
| git 커밋 실패 (hook 등) | 에러 보고, staged 상태 유지, 사용자가 후속 처리 |

## 주의사항

- **`git add`는 정확히 생성된 파일 절대경로만 지정**한다. `git add .`이나 `git add -A`를 쓰지 않는다. working tree의 다른 변경을 보호하기 위함이다.
- `${NAME}`·`${PACKAGE_NAME}` placeholder는 정확히 그 형태로 등장한다. 다른 변수는 치환하지 않는다.
- 커밋 메시지는 `~/.claude/rules/git-commit-message.md` 규칙을 따른다.
