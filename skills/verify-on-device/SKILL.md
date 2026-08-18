---
name: verify-on-device
description: 이미 설치된 앱을 실기기/에뮬레이터에서 조작하고 그 화면을 스크린샷 또는 영상으로 남겨 확인하는 스킬. 사용자가 'verify-on-device', '기기에서 확인해', '실기기에서 확인해', '동작하는지 확인해', '스크린샷 찍어', '화면 캡처해', '캡처해서 보여줘', '녹화해', '영상으로 녹화해', '동작 녹화해서 보여줘', '시연 영상 만들어', 'screenrecord' 등을 요청할 때 이 스킬을 사용해야 한다. **앱 빌드·설치(installDevDebug/installPrdQa)와 테스트 화면 생성(create-test-screen)은 이 스킬 밖이다** — 설치가 끝난 앱을 조작·캡처해 확인하는 단계만 담당한다.
argument-hint: "[스크린샷|녹화] [시나리오 설명] [저장 위치]"
---

# Verify On Device

## Overview

기기에서 앱을 직접 조작하고 그 화면을 스크린샷 또는 영상으로 남겨 구현이 의도대로 동작하는지 확인한다. 빌드·설치는 이 스킬 밖이며, 설치가 끝난 상태에서 시작한다. 원칙 둘.

1. **녹화는 조작과 같은 Bash 호출 안에서 시작하고 끝낸다.** 나누면 호출 간 지연이 앞부분을 정지 화면으로 낭비하고 시나리오 뒤쪽이 잘린다.
2. **탭 좌표와 조작 횟수는 녹화 전에 스크린샷으로 확정한다.** 본 녹화에서 처음 시도하면 빗나간 탭이 그대로 영상에 남는다.

## 0. 사전 확인

```bash
adb devices -l
adb shell input keyevent KEYCODE_WAKEUP
```

- 기기가 없으면 사용자에게 알리고 종료한다. **에뮬레이터를 임의로 부팅하지 않는다.**
- 2대 이상이면 어느 기기를 쓸지 확인하고 이후 모든 명령에 `adb -s <serial>`을 붙인다.
- 화면이 꺼져 있으면 녹화가 검은 프레임으로 채워진다. `KEYCODE_WAKEUP`으로 깨우고, 잠금(PIN/패턴)이 걸려 있으면 사용자에게 해제를 요청한다.
- 앱을 띄우려면 설치 변종에 맞는 패키지를 쓴다: DevDebug = `<applicationId>.debug`, PrdQa = `<applicationId>.qa`. 접미사가 틀리면 "Activity does not exist"가 뜬다.
- **기기를 다른 작업/세션이 함께 쓰고 있으면 녹화를 시작하기 전에 사용자에게 확인한다.** 아래 `pkill -INT screenrecord`는 기기 전역이라 남의 녹화까지 끊는다.

## 1. 저장 위치

| 구분 | 위치 |
|---|---|
| **최종 결과물** — 사용자가 열어볼 스크린샷·영상 | **항상 `~/Downloads/`** |
| 사용자가 경로를 직접 지정한 경우 | 그 경로와 그 파일명을 그대로 쓴다 |
| 중간 산출물 — 좌표 확정용 스크린샷, 검증용 추출 프레임 | 세션 scratchpad |

- 최종 결과물을 scratchpad에 두지 않는다. 사용자가 직접 열어봐야 하는 파일이므로 손이 닿는 곳에 있어야 한다.
- 중간 산출물은 상대 경로로 만들면 프로젝트 저장소가 오염되니 반드시 scratchpad를 명시한다.
- 파일명은 `{티켓ID}_{용도}.{png,mp4}` 형태로 짓는다(예: `hda22556_test.mp4`).
- 결과물 경로는 응답에서 **절대 경로를 별도 라인으로** 출력한다.

## 2. 스크린샷

```bash
# 결과물로 남길 스크린샷
adb shell screencap -p /sdcard/shot.png && adb pull /sdcard/shot.png ~/Downloads/<이름>.png
# 좌표 확정용(중간 산출물)
adb shell screencap -p /sdcard/shot.png && adb pull /sdcard/shot.png <scratchpad>/shot.png
```

Read 도구로 확인한다. Read 결과의 `original 1080x2340, displayed at 923x2000. Multiply coordinates by 1.17`에서 **배율**을 얻어, 이미지에서 읽은 좌표에 곱한 값을 `input tap`에 넣는다. 표시 좌표를 그대로 쓰면 엉뚱한 곳을 누른다.

## 3. 좌표와 조작 횟수 확정 (녹화 전 필수)

목록 항목처럼 **한 단계 들어가야 보이는 좌표**는 미리 알 수 없다. 본 녹화 전에 시나리오를 한 번 걸어보며 스크린샷으로 좌표를 확정하고, 확인이 끝나면 `am force-stop`으로 초기 상태로 되돌린다.

특히 다단계 UI에서 **`KEYCODE_BACK` 한 번이 무엇을 하는지 확인한다** — 시트가 닫히는 대신 이전 단계로만 돌아가는 경우가 많고, 그러면 닫으려면 단계 수만큼 눌러야 한다. 이 횟수를 모르면 영상이 "열린 채"로 끝난다.

## 4. 녹화

**한 Bash 호출 안에서** 띄우고, 조작하고, 끊는다. 이 환경에서 foreground `sleep`은 정상 동작하므로 아래 형태를 그대로 쓴다(우회 불필요).

```bash
adb shell pkill -INT screenrecord            # 남은 녹화 프로세스 정리
adb shell rm -f /sdcard/rec.mp4              # 옛 파일을 pull해 오판하는 것 방지
adb shell am force-stop <pkg>                # 초기 상태에서 시작
adb shell am start -n <pkg>/<activity>; sleep 3

adb shell screenrecord --time-limit 60 --bit-rate 6000000 /sdcard/rec.mp4 &
REC=$!
sleep 2
adb shell pidof screenrecord                 # 빈 출력이면 녹화가 안 떴다

adb shell input tap 257 695; sleep 3          # 시나리오 조작
adb shell input tap 278 540; sleep 3
adb shell input keyevent KEYCODE_BACK; sleep 2

adb shell pkill -INT screenrecord            # SIGINT여야 파일이 정상 마무리된다
wait $REC 2>/dev/null
sleep 2
adb pull /sdcard/rec.mp4 <저장경로>
```

- `--time-limit`은 시나리오보다 넉넉하게(최대 180초) 주고, 실제 길이는 `pkill -INT`가 결정한다.
- 목표 길이는 `sleep` 합계로 맞춘다. `adb shell` 왕복이 호출당 0.2~0.5초씩 더해지므로 실제 길이는 합계보다 조금 길다.
- 조작 사이 `sleep`은 전환 애니메이션보다 길게. 2~3초가 기본이고, 확인시켜야 할 상태는 3~4초 머문다.
- `adb shell input swipe`를 같은 체인에서 연속 실행하면 간헐적으로 전혀 전달되지 않는다 — 사이에 `sleep 2` 이상을 두고 반영됐는지 캡처로 확인한다.

## 5. 검증 (건너뛰지 않는다)

파일이 생겼다고 시나리오가 담긴 것이 아니다.

```bash
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 <파일>
ffmpeg -v error -ss 12 -i <파일> -frames:v 1 <scratchpad>/f12.png -y
```

- **길이**: 시나리오 소요 시간과 맞는지 본다. `--time-limit`에 가까우면 `pkill`이 안 먹은 것, 크게 짧으면 조기 종료다.
- **핵심 프레임**: 확인시켜야 할 순간(선택 강조 여부, 전환 후 상태)의 프레임을 뽑아 Read로 눈으로 본다. 프레임이 전부 초기 화면이면 탭 좌표가 빗나갔다.
- 애니메이션 자체를 봐야 하면 `ffmpeg -i x.mp4 -vf fps=15 f%03d.png`로 구간을 다발 추출한다.
- 잘렸거나 정지 구간이 길면 **재녹화한다.** 잘린 영상을 그대로 넘기지 않는다.
- 끝나면 기기 쪽 임시 파일을 지운다: `adb shell rm -f /sdcard/shot*.png /sdcard/rec.mp4`

## Quick Reference

| 목적 | 명령 |
|---|---|
| 기기 확인 / 깨우기 | `adb devices -l` / `adb shell input keyevent KEYCODE_WAKEUP` |
| 스크린샷 | `adb shell screencap -p /sdcard/x.png` → `adb pull` (결과물은 `~/Downloads/`) |
| 녹화 시작 | `adb shell screenrecord --time-limit N --bit-rate 6000000 /sdcard/x.mp4 &` |
| 녹화 시작 확인 | `adb shell pidof screenrecord` |
| 녹화 종료 | `adb shell pkill -INT screenrecord` |
| 탭 / 키 | `adb shell input tap X Y` / `adb shell input keyevent KEYCODE_BACK` |
| 길이 확인 | `ffprobe -v error -show_entries format=duration ...` |
| 프레임 1장 / 다발 | `ffmpeg -ss T -i x.mp4 -frames:v 1 f.png -y` / `-vf fps=15 f%03d.png` |

## Common Mistakes

| 실수 | 결과 | 대응 |
|---|---|---|
| 녹화 시작과 조작을 별도 Bash 호출로 나눔 | 앞 10초 이상이 정지 화면, 뒤쪽 조작 누락 | 한 호출에서 `&` + `pkill -INT` |
| foreground `sleep`이 막혀 있다고 보고 우회를 만듦 | 불필요한 background 실행으로 중간 출력을 못 봄 | 이 환경에서 foreground `sleep`은 정상 동작한다 |
| 기기 쪽 옛 파일을 지우지 않음 | 녹화가 실패했는데 지난 영상을 pull해 검증을 통과시킴 | 녹화 전 `adb shell rm -f` |
| 본 녹화에서 좌표를 처음 시도 | 빗나간 탭이 영상에 남음 | §3으로 좌표를 먼저 확정 |
| `KEYCODE_BACK` 횟수를 확인 없이 1회로 가정 | 다단계 UI가 닫히지 않고 영상이 어정쩡하게 끝남 | §3에서 단계 수를 세어 확정 |
| `--time-limit` 만료로 종료를 대신함 | 마지막 조작이 잘림 | `pkill -INT`로 명시적 종료 |
| 표시 좌표를 그대로 `input tap`에 사용 | 엉뚱한 위치를 누름 | Read가 알려준 배율을 곱한다 |
| 파일 크기만 보고 성공 판정 | 비어 있거나 잘린 영상을 전달 | `ffprobe` 길이 + 핵심 프레임 확인 |
| 앱을 이어서 실행한 상태로 녹화 | 앞선 조작 상태가 남아 시나리오가 어긋남 | `am force-stop` 후 재시작 |
| 결과물 영상·스크린샷을 scratchpad에 남김 | 사용자가 찾아 열기 어렵다 | 결과물은 항상 `~/Downloads/` |
| 공유 기기에서 `pkill -INT screenrecord` 실행 | 다른 세션의 녹화까지 끊김 | §0에서 기기 점유를 먼저 확인 |
