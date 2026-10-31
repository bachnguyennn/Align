#!/usr/bin/env python3
"""Print an xcodebuild -destination string for an available iPhone simulator.

    python3 scripts/ci/pick-simulator.py --project Align.xcodeproj --scheme Align

Strategy (avoids hardcoding device names that differ between runner images):
1. Ask xcodebuild which destinations the scheme can actually use (-showdestinations) and pick
   the iPhone simulator with the newest OS. This respects the selected Xcode's SDK.
2. Fall back to `xcrun simctl list devices available -j`, restricted to iOS runtimes not newer
   than the selected Xcode's iphonesimulator SDK.

Prints e.g. `platform=iOS Simulator,id=1A2B...` on stdout; diagnostics go to stderr.
Exits 1 if nothing suitable is found.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

PLACEHOLDER = "placeholder"


def log(msg: str) -> None:
    print(msg, file=sys.stderr)


def version_tuple(text: str) -> tuple[int, ...]:
    return tuple(int(p) for p in re.findall(r"\d+", text))


def from_showdestinations(project: str | None, scheme: str | None) -> str | None:
    if not scheme:
        return None
    cmd = ["xcodebuild", "-showdestinations", "-scheme", scheme]
    if project:
        cmd += ["-project", project]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=300).stdout
    except (OSError, subprocess.TimeoutExpired) as exc:
        log(f"showdestinations failed: {exc}")
        return None
    # Only consider the eligible section.
    out = out.split("Ineligible destinations", 1)[0]
    candidates = []
    for block in re.findall(r"\{([^{}]*)\}", out):
        fields = {}
        for part in block.split(","):
            if ":" in part:
                key, _, value = part.partition(":")
                fields[key.strip()] = value.strip()
        if fields.get("platform") != "iOS Simulator":
            continue
        dev_id, name, os_ver = fields.get("id", ""), fields.get("name", ""), fields.get("OS", "")
        if not dev_id or PLACEHOLDER in dev_id.lower() or not name.startswith("iPhone") or not os_ver:
            continue
        candidates.append((version_tuple(os_ver), name, dev_id))
    if not candidates:
        log("showdestinations returned no concrete iPhone simulators")
        return None
    best_os = max(c[0] for c in candidates)
    newest = [c for c in candidates if c[0] == best_os]
    _, name, dev_id = newest[0]
    log(f"Selected via showdestinations: {name} (iOS {'.'.join(map(str, best_os))}) id={dev_id}")
    return dev_id


def from_simctl() -> str | None:
    try:
        sdk = subprocess.run(
            ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
            capture_output=True, text=True, timeout=60,
        ).stdout.strip()
        data = json.loads(
            subprocess.run(
                ["xcrun", "simctl", "list", "devices", "available", "-j"],
                capture_output=True, text=True, timeout=120,
            ).stdout
        )
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        log(f"simctl fallback failed: {exc}")
        return None
    sdk_v = version_tuple(sdk) if sdk else None
    candidates = []
    for runtime, devices in data.get("devices", {}).items():
        m = re.search(r"SimRuntime\.iOS-([\d-]+)$", runtime)
        if not m:
            continue
        rt_v = tuple(int(p) for p in m.group(1).split("-"))
        # Runtimes newer than the SDK's major.minor may not be usable by this Xcode.
        if sdk_v and rt_v[:2] > sdk_v[:2]:
            continue
        for dev in devices:
            if dev.get("isAvailable", True) and dev.get("name", "").startswith("iPhone"):
                candidates.append((rt_v, dev["name"], dev["udid"]))
    if not candidates:
        log(f"simctl found no available iPhone simulators (SDK {sdk or 'unknown'})")
        return None
    candidates.sort(key=lambda c: c[0], reverse=True)
    rt_v, name, udid = candidates[0]
    log(f"Selected via simctl: {name} (iOS {'.'.join(map(str, rt_v))}) id={udid}")
    return udid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project")
    parser.add_argument("--scheme")
    args = parser.parse_args()
    dev_id = from_showdestinations(args.project, args.scheme) or from_simctl()
    if not dev_id:
        return 1
    print(f"platform=iOS Simulator,id={dev_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
