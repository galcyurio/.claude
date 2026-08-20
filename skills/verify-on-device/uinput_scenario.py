#!/usr/bin/env python3
"""시나리오 DSL을 adb shell uinput 용 JSON 스트림으로 변환한다.

사용법:
    python3 uinput_scenario.py <width>x<height> < scenario.txt > touch.json

시나리오 DSL (한 줄에 하나, '#' 주석 허용):
    tap X Y [hold_ms]              기본 hold 250ms
    swipe X1 Y1 X2 Y2 [dur_ms]     기본 400ms
    key NAME                       BACK, HOME, ENTER, TAB, ESC, DPAD_*, VOLUME_*
    wait MS
"""
import json, sys

DEV_ID = 1
SLOT, TRACKING_ID, POS_X, POS_Y, PRESSURE = 47, 57, 53, 54, 58
BTN_TOUCH = 330
EV_KEY, EV_ABS, EV_SYN = 1, 3, 0

# Linux input event code (Generic.kl 이 Android 키로 매핑한다)
KEYS = {
    "BACK": 158, "HOME": 172, "ENTER": 28, "TAB": 15, "ESC": 1,
    "DPAD_UP": 103, "DPAD_DOWN": 108, "DPAD_LEFT": 105, "DPAD_RIGHT": 106,
    "VOLUME_UP": 115, "VOLUME_DOWN": 114,
}


def register(w, h):
    def abs_info(code, mx):
        return {"code": code, "info": {"value": 0, "minimum": 0, "maximum": mx,
                                       "fuzz": 0, "flat": 0, "resolution": 0}}
    return {
        "id": DEV_ID, "command": "register",
        "name": "Verify Touchscreen",
        # vid/pid는 /system/usr/keylayout/Vendor_*.kl 과 매칭되지 않는 값을 쓴다.
        # 매칭되면 그 레이아웃이 Generic.kl 을 밀어내고 key 명령이 전부 무시된다.
        "vid": 26985, "pid": 1, "bus": "usb", "port": "usb:1",
        "configuration": [
            {"type": 100, "data": [EV_KEY, EV_ABS]},   # UI_SET_EVBIT
            {"type": 101, "data": [BTN_TOUCH] + sorted(KEYS.values())},  # UI_SET_KEYBIT
            {"type": 103, "data": [SLOT, POS_X, POS_Y, TRACKING_ID, PRESSURE]},
            {"type": 110, "data": [1]},                # UI_SET_PROPBIT: INPUT_PROP_DIRECT
        ],
        "abs_info": [abs_info(SLOT, 9), abs_info(POS_X, w - 1), abs_info(POS_Y, h - 1),
                     abs_info(TRACKING_ID, 65535), abs_info(PRESSURE, 255)],
    }


def inject(events):
    return {"id": DEV_ID, "command": "inject", "events": events}


def delay(ms):
    return {"id": DEV_ID, "command": "delay", "duration": ms}


class Scenario:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.tid = 0
        self.out = [register(w, h), delay(1500)]   # InputReader가 디바이스를 잡을 시간

    def _down(self, x, y):
        self.tid += 1
        return inject([EV_ABS, SLOT, 0, EV_ABS, TRACKING_ID, self.tid,
                       EV_KEY, BTN_TOUCH, 1, EV_ABS, POS_X, x, EV_ABS, POS_Y, y,
                       EV_ABS, PRESSURE, 128, EV_SYN, 0, 0])

    def _move(self, x, y):
        return inject([EV_ABS, SLOT, 0, EV_ABS, POS_X, x, EV_ABS, POS_Y, y, EV_SYN, 0, 0])

    def _up(self):
        return inject([EV_ABS, SLOT, 0, EV_ABS, TRACKING_ID, -1,
                       EV_KEY, BTN_TOUCH, 0, EV_SYN, 0, 0])

    def tap(self, x, y, hold=250):
        self.out += [self._down(x, y), delay(hold), self._up()]

    def swipe(self, x1, y1, x2, y2, dur=400):
        steps = max(2, dur // 16)
        self.out.append(self._down(x1, y1))
        for i in range(1, steps + 1):
            t = i / steps
            self.out += [delay(dur // steps),
                         self._move(round(x1 + (x2 - x1) * t), round(y1 + (y2 - y1) * t))]
        self.out.append(self._up())

    def key(self, name):
        code = KEYS.get(name.upper())
        if code is None:
            raise SystemExit(f"알 수 없는 키 {name!r} — 지원: {', '.join(sorted(KEYS))}")
        self.out += [inject([EV_KEY, code, 1, EV_SYN, 0, 0]), delay(60),
                     inject([EV_KEY, code, 0, EV_SYN, 0, 0])]

    def wait(self, ms):
        self.out.append(delay(ms))


def main():
    w, h = (int(v) for v in sys.argv[1].split("x"))
    sc = Scenario(w, h)
    for lineno, raw in enumerate(sys.stdin, 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        cmd, *args = line.split()
        if cmd == "key":
            sc.key(args[0])
            continue
        nums = [int(a) for a in args]
        if cmd == "tap":
            sc.tap(*nums)
        elif cmd == "swipe":
            sc.swipe(*nums)
        elif cmd == "wait":
            sc.wait(*nums)
        else:
            sys.exit(f"{lineno}행: 알 수 없는 명령 {cmd!r}")
    sc.wait(500)
    for obj in sc.out:
        print(json.dumps(obj, ensure_ascii=False))


if __name__ == "__main__":
    main()
