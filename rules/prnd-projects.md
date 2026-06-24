# PRND Android 프로젝트

`~/dev/` 하위가 PRND 주요 Android 프로젝트들이다. 사용자가 "모든 프로젝트", "전체 프로젝트", "주요 프로젝트"라고 하면 아래 10개를 의미한다.

| 역할 | 디렉토리 |
|---|---|
| 고객 | `heydealer-android` |
| 딜러 | `heydealer-for-dealer-android` |
| 딜러-콜 | `heydealer-call-android` |
| 평가사 | `heydealer-inspector-android` |
| 평가사-콜 | `heydealer-inspector-call-android` |
| 리볼트 | `revolt-android` |
| 테크베이-공업사 | `techbay-reconditioning-android` |
| 테크베이-어드민 | `techbay-admin-android` |
| 테크베이-콜 | `techbay-call-android` |
| 라이브러리 | `prnd-android-library` (공통 서브모듈) |

- 절대경로: `/Users/olaf/dev/<디렉토리>`
- `-2`/`-3` 접미사 디렉토리(예: `heydealer-android-2`, `revolt-android-2`)는 worktree/복제본이므로 원본과 구분한다.
- 공통: 패키지 `kr.co.prnd`, 내부 문서 `docs.prnd.co.kr`.
- 디자인 시스템은 앱마다 다르다 — 같은 피처라도 `revolt`↔`heydealer`는 다를 수 있으므로 cross-app 시각 불일치를 결함으로 보고하지 않는다.
