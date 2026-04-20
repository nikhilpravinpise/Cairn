"""S1 device feasibility harness — RAM / CPU sampler via adb.

Samples `dumpsys meminfo <pkg>` and `top -n 1 -p <pid>` at 1 Hz while the
operator runs vision prompts on the device. Operator presses Enter at the start
and end of each prompt; timestamps get embedded into the sampled trace so we
can compute TTFT and decode rate per prompt post-hoc (paired with stopwatch
measurements in the device UI if the APK doesn't expose them).

Fails loud if adb / device / package are missing.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any


def _adb(*args: str, device: str | None = None) -> str:
    if not shutil.which("adb"):
        sys.exit("adb not found on PATH. brew install android-platform-tools")
    cmd = ["adb"]
    if device:
        cmd += ["-s", device]
    cmd += list(args)
    out = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return out.stdout


def _require_device(device: str | None) -> str:
    listing = _adb("devices").strip().splitlines()[1:]
    devices = [ln.split()[0] for ln in listing if ln.strip() and "device" in ln]
    if device:
        if device not in devices:
            sys.exit(f"device {device!r} not connected. seen: {devices}")
        return device
    if len(devices) != 1:
        sys.exit(f"expected exactly one device; got {devices}. pass --device <serial>")
    return devices[0]


def _pid_of(pkg: str, device: str) -> int | None:
    try:
        out = _adb("shell", "pidof", pkg, device=device).strip()
    except subprocess.CalledProcessError:
        return None
    if not out:
        return None
    try:
        return int(out.split()[0])
    except ValueError:
        return None


_MEMINFO_RSS_RE = re.compile(r"^\s*TOTAL(?: PSS)?:\s+(\d+)", re.MULTILINE)
_MEMINFO_JAVA_RE = re.compile(r"Native Heap\s+(\d+)")


def _sample_meminfo(pkg: str, device: str) -> dict[str, Any]:
    try:
        out = _adb("shell", "dumpsys", "meminfo", pkg, device=device)
    except subprocess.CalledProcessError as e:
        return {"error": str(e)}
    total = _MEMINFO_RSS_RE.search(out)
    native = _MEMINFO_JAVA_RE.search(out)
    return {
        "total_pss_kb": int(total.group(1)) if total else None,
        "native_heap_kb": int(native.group(1)) if native else None,
    }


def _sample_top(pid: int, device: str) -> dict[str, Any]:
    try:
        out = _adb("shell", "top", "-n", "1", "-p", str(pid), "-b", device=device)
    except subprocess.CalledProcessError as e:
        return {"error": str(e)}
    for line in out.splitlines():
        parts = line.split()
        if parts and parts[0].isdigit() and int(parts[0]) == pid:
            # order on Android top: PID USER PR NI VIRT RES SHR S %CPU %MEM ...
            try:
                return {
                    "cpu_pct": float(parts[8]),
                    "mem_pct": float(parts[9]),
                    "res_kb": _size_to_kb(parts[5]),
                }
            except (IndexError, ValueError):
                return {"raw": line}
    return {}


def _size_to_kb(s: str) -> int | None:
    s = s.strip().upper()
    if not s:
        return None
    if s.endswith("K"):
        return int(float(s[:-1]))
    if s.endswith("M"):
        return int(float(s[:-1]) * 1024)
    if s.endswith("G"):
        return int(float(s[:-1]) * 1024 * 1024)
    try:
        return int(float(s))
    except ValueError:
        return None


def main() -> None:
    ap = argparse.ArgumentParser(description="S1 device feasibility adb harness")
    ap.add_argument("--device", default=None, help="adb device serial (optional if 1 attached)")
    ap.add_argument("--pkg", required=True, help="package id of the LLM app")
    ap.add_argument("--out", required=True, type=Path, help="output JSON file")
    ap.add_argument("--duration", type=int, default=120, help="seconds to sample")
    ap.add_argument("--hz", type=float, default=1.0)
    args = ap.parse_args()

    device = _require_device(args.device)
    pid = _pid_of(args.pkg, device)
    if pid is None:
        sys.exit(f"package {args.pkg!r} not running on {device}. launch it first.")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    samples: list[dict[str, Any]] = []
    markers: list[dict[str, Any]] = []
    stop = threading.Event()

    def marker_thread() -> None:
        print("press Enter at the START of each vision prompt, then again at END.", file=sys.stderr)
        n = 0
        while not stop.is_set():
            try:
                input()
            except EOFError:
                return
            n += 1
            kind = "start" if n % 2 == 1 else "end"
            markers.append({"t": time.time(), "kind": kind, "prompt_no": (n + 1) // 2})
            print(f"  marker {kind} prompt {(n + 1) // 2}", file=sys.stderr)

    signal.signal(signal.SIGINT, lambda *_: stop.set())
    t = threading.Thread(target=marker_thread, daemon=True)
    t.start()

    t0 = time.time()
    period = 1.0 / args.hz
    while time.time() - t0 < args.duration and not stop.is_set():
        ts = time.time()
        sample = {
            "t": ts,
            "meminfo": _sample_meminfo(args.pkg, device),
            "top": _sample_top(pid, device),
        }
        samples.append(sample)
        time.sleep(max(0.0, period - (time.time() - ts)))

    stop.set()
    args.out.write_text(
        json.dumps(
            {
                "started_utc": dt.datetime.fromtimestamp(t0, dt.UTC).isoformat(),
                "device": device,
                "pkg": args.pkg,
                "pid": pid,
                "samples": samples,
                "markers": markers,
            },
            indent=2,
        ),
        encoding="utf-8",
    )
    print(f"wrote {args.out} ({len(samples)} samples, {len(markers)} markers)")


if __name__ == "__main__":
    main()
