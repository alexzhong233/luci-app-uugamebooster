#!/usr/bin/env python3
"""Explain what the status page would say, from a uu-detect output.

The page's "Ready" comes from two things only: the core is running, and it has
an established connection to NetEase's control servers. It used to also want
/tmp/uu/activate_status to be non-empty, which is a link snapshot the core
writes once at first bind and never again - so an OEM build under emulation,
where that file is never written at all, sat at "Registering..." forever while
the app was boosting happily.

This script feeds the controller's own patterns with the output of a given
machine, so the difference between the two rules can be shown without a router:

    ./uu-detect > /tmp/det.txt
    python3 tools/check-status-phase.py /tmp/det.txt

With no argument it uses the shape this plugin's vendor build reports under
emulation, which is the case that used to be wrong.
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "luci-app-uugamebooster", "luasrc", "controller",
                   "uuplugin.lua")

# The rules have to be lifted from the controller, not retyped: a copy that
# drifts from the real one would keep saying "ready" long after the page
# stopped agreeing.
REQUIRED = [
    'e.running = det:match("ours=(%d+)") ~= nil',
    'e.cloud = det:match("cloud=([^\\r\\n]*)")',
    'e.ready = (e.running and e.cloud ~= nil)',
]

SAMPLES = {
    # What this plugin's vendor build reports when it is emulated: emulated
    # process, cloud up, a device being boosted, and no activate_status at all.
    "oem-emulated": """\
ours=1873
build=oem-emulated
dnat=
foreign=
openclash=
ua3f=
homeproxy=
nikki=
coexist=openclash:0 nikki:0 homeproxy:0 ua3f:0
boosted=192.168.88.126
blocked=
listmode=all
listips=
cloud=42.186.73.19:443
activated=
""",
}


def parse_kv(text):
    out = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            out[key.strip()] = value
    return out


def phase(text, require_activated=False):
    kv = parse_kv(text)
    running = bool(re.match(r"^\d+$", kv.get("ours", "")))
    cloud = kv.get("cloud") or None
    activated = kv.get("activated") or None

    if not running:
        return "stopped"
    if cloud is None:
        return "starting"
    if require_activated and activated is None:
        return "starting"
    return "ready"


def main():
    src = io.open(LUA, encoding="utf-8").read()
    missing = [rule for rule in REQUIRED if rule not in src]
    if missing:
        print("!! 判据变了，先更新这个脚本再信它的结论：")
        for rule in missing:
            print("   ", rule)
        return 2

    if len(sys.argv) > 1:
        text = io.open(sys.argv[1], encoding="utf-8").read()
        print(f"{sys.argv[1]}: {phase(text)}")
        return 0

    bad = 0
    print("== 现在的判据：running + cloud")
    for name, text in SAMPLES.items():
        got = phase(text)
        ok = got == "ready"
        bad += 0 if ok else 1
        print(f"  {'ok  ' if ok else 'FAIL'} {name}: {got}")
        print(f"       activate_status: {parse_kv(text).get('activated') or '(空)'}"
              f"  cloud: {parse_kv(text).get('cloud') or '(未连)'}")

    print()
    print("== 2.4 及更早的判据：还要 activate_status 非空")
    for name, text in SAMPLES.items():
        print(f"  {name}: {phase(text, require_activated=True)}"
              "   <- 这就是「永远卡在正在注册」")

    print()
    print("结论：" + ("现在的判据不受 activate_status 影响" if not bad
                    else "有场景不通过，见上面的 FAIL"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
