"""Bounded supervisor. Never signals any process except its own Popen children."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid


def stop(child):
    if child.poll() is not None:
        return
    child.terminate()
    try:
        child.wait(timeout=2)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait(timeout=2)


def supervise(child, heartbeat, duration, startup_grace=20, stall_limit=8):
    start = time.monotonic()
    observed_heartbeat = False
    while child.poll() is None:
        now = time.monotonic()
        if now - start >= duration:
            stop(child)
            return "lifetime-limit"
        try:
            age = time.time() - heartbeat.stat().st_mtime
            observed_heartbeat = True
        except FileNotFoundError:
            age = now - start
        if (observed_heartbeat and age > stall_limit) or (not observed_heartbeat and age > startup_grace):
            stop(child)
            return "heartbeat-timeout"
        time.sleep(0.1)
    return "app-exited"


def self_test():
    with tempfile.TemporaryDirectory(prefix="space-trial-watchdog-") as temp:
        hb = Path(temp) / "heartbeat"
        other = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
        try:
            child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
            assert supervise(child, hb, 3, startup_grace=0.2) == "heartbeat-timeout"
            assert child.poll() is not None and other.poll() is None
            hb.write_text("alive")
            child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(20)"])
            assert supervise(child, hb, 0.3) == "lifetime-limit"
            assert child.poll() is not None and other.poll() is None
            child = subprocess.Popen([sys.executable, "-c", "pass"])
            assert supervise(child, hb, 3) == "app-exited"
        finally:
            stop(other)
    print("PASS: missing heartbeat, lifetime limit, normal exit; unrelated child untouched")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--seconds", type=int, default=600)
    parser.add_argument("--display-id", type=int, help="Physical display ID observed from NSScreen, not a Space ID")
    parser.add_argument("--placement-delay-ms", type=int, choices=(0, 500), default=0)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not 30 <= args.seconds <= 900:
        parser.error("--seconds must be between 30 and 900")
    if args.display_id is not None and not 0 < args.display_id <= 0xFFFFFFFF:
        parser.error("--display-id must be a positive UInt32 physical display ID")
    root = Path(__file__).resolve().parents[2]
    build = root / ".build/visible-space-trial.noindex"
    token = str(uuid.uuid4())
    run_dir = Path(tempfile.mkdtemp(prefix="space-trial-run-"))
    app_dir = Path.home() / "Library/Containers/io.github.ethznn.spacetransitiontrial/Data/Library/Application Support/SpaceTransitionTrial" / token
    metadata = {"token": token, "runDirectory": str(run_dir), "appDirectory": str(app_dir)}
    metadata["requestedPhysicalDisplayID"] = args.display_id
    metadata["placementDelayMilliseconds"] = args.placement_delay_ms
    app = observer = None
    try:
        with (run_dir / "observer.jsonl").open("wb") as observer_log, (run_dir / "app-stdio.log").open("wb") as app_log:
            observer = subprocess.Popen([str(build / "ObserveSpaceState"), str(min(900, args.seconds + 5))], stdout=observer_log, stderr=app_log)
            app_arguments = [str(build / "SpaceTransitionTrial.app/Contents/MacOS/SpaceTransitionTrial"), token]
            if args.display_id is not None:
                app_arguments.append(str(args.display_id))
            app_environment = dict(os.environ, SPACE_TRIAL_PLACEMENT_DELAY_MS=str(args.placement_delay_ms))
            app = subprocess.Popen(app_arguments, stdout=app_log, stderr=app_log, env=app_environment)
            metadata.update({"appPID": app.pid, "observerPID": observer.pid})
            (run_dir / "session.json").write_text(json.dumps(metadata))
            print(json.dumps(metadata), flush=True)
            reason = supervise(app, app_dir / "heartbeat", args.seconds)
            print(json.dumps({"ended": reason, "exitCode": app.returncode}), flush=True)
    finally:
        if app is not None:
            stop(app)
        if observer is not None:
            stop(observer)


if __name__ == "__main__":
    main()
