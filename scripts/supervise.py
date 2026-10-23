#!/usr/bin/env python3
"""Bound a Linux command's lifetime; stream logs and observe real process activity.

Exit 124 means stalled/timed out (retryable), 75 means low disk (needs intervention).
Only the new command session is terminated; the workflow lock remains in its parent.
"""
import argparse
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time


def activity(session):
    """Read counters without walking a potentially huge source tree."""
    result = {}
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
            if int(stat[3]) != session or stat[0] == 'Z':
                continue
            io = dict(line.split(':', 1) for line in (entry / 'io').read_text().splitlines())
            # starttime prevents confusing a reused PID with the original process.
            result[(entry.name, stat[19])] = (
                int(stat[11]) + int(stat[12]),
                sum(int(io.get(key, 0)) for key in ('rchar', 'wchar', 'read_bytes', 'write_bytes')),
            )
        except (OSError, ValueError, IndexError, ProcessLookupError):
            continue
    return result


def made_progress(before, after, ticks, interval=30):
    if before.keys() != after.keys():
        return True
    cpu = sum(max(0, after[key][0] - before[key][0]) for key in after)
    io = sum(max(0, after[key][1] - before[key][1]) for key in after)
    return cpu >= max(1, int(ticks * min(0.25, interval * 0.01))) or io >= 4096


def stop_group(process, grace):
    # The leader can exit while a child still holds stdout open: kill the session
    # group even in that case, before allowing a retry to touch the same repos.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        process.wait()
        return
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.05)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


class Interrupted(Exception):
    def __init__(self, signum):
        self.signum = signum


def supervise(args):
    paths = args.path or ['.']
    log = open(args.log, 'wb', buffering=0) if args.log else None

    def emit(data):
        if log:
            log.write(data)
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()

    def message(value):
        emit((f'[watchdog] {value}\n').encode())

    def low_disk():
        for path in paths:
            free = shutil.disk_usage(path).free / (1024 ** 3)
            if free < args.reserve_gb:
                message(f'LOW DISK: {path}: {free:.1f} GiB free; reserve {args.reserve_gb:g} GiB. Downloads preserved; free space before resuming.')
                return True
        return False

    process = None
    previous_handlers = {}
    try:
        if low_disk():
            return 75
        for signum in (signal.SIGTERM, signal.SIGINT):
            def interrupted(number, frame):
                raise Interrupted(number)
            previous_handlers[signum] = signal.signal(signum, interrupted)
        process = subprocess.Popen(args.command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True, env=dict(os.environ, PYTHONUNBUFFERED='1',
                                                                   GIT_TERMINAL_PROMPT='0'))
        started = last_progress = time.monotonic()
        next_check = started + args.interval
        previous = activity(process.pid)
        ticks = os.sysconf('SC_CLK_TCK')
        eof = False
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                for key, _ in selector.select(max(0, min(1, next_check - time.monotonic()))):
                    chunk = os.read(key.fd, 65536)
                    if chunk:
                        emit(chunk)
                        # Log chatter alone cannot hide a stuck fetch. Progress is
                        # based on the command session's CPU and I/O counters.
                    else:
                        selector.unregister(key.fileobj)
                        eof = True
                code = process.poll()
                if code is not None and eof:
                    return code if code >= 0 else 128 - code
                now = time.monotonic()
                if now < next_check:
                    continue
                current = activity(process.pid)
                if made_progress(previous, current, ticks, args.interval):
                    last_progress = now
                previous = current
                next_check = now + args.interval
                if low_disk():
                    return 75
                idle = now - last_progress
                elapsed = now - started
                free = min(shutil.disk_usage(path).free for path in paths) / (1024 ** 3)
                message(f'running {elapsed:.0f}s; {len(current)} processes; idle {idle:.0f}s; {free:.1f} GiB free')
                if idle >= args.idle_timeout or elapsed >= args.max_seconds:
                    message('TIMEOUT: no meaningful activity or attempt time limit reached; stopping command group before retry.')
                    return 124
    except Interrupted as error:
        message('Interrupted; stopping command group. Downloads preserved.')
        return 128 + error.signum
    finally:
        # Ignore repeated stop signals while cleaning up the owned child group.
        for signum in previous_handlers:
            signal.signal(signum, signal.SIG_IGN)
        if process is not None:
            stop_group(process, args.stop_grace)
            process.stdout.close()
        if log:
            log.close()
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--idle-timeout', type=float, default=600)
    parser.add_argument('--max-seconds', type=float, default=43200)
    parser.add_argument('--interval', type=float, default=30)
    parser.add_argument('--stop-grace', type=float, default=5)
    parser.add_argument('--reserve-gb', type=float, default=5)
    parser.add_argument('--path', action='append')
    parser.add_argument('--log')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command[:1] == ['--']:
        args.command.pop(0)
    if not args.command or any(value <= 0 for value in
                               (args.idle_timeout, args.max_seconds, args.interval, args.stop_grace)) or args.reserve_gb < 0:
        parser.error('provide a command and positive time limits; reserve must be nonnegative')
    try:
        return supervise(args)
    except OSError as error:
        print(f'[watchdog] Cannot supervise command: {error}', file=sys.stderr)
        return 73


if __name__ == '__main__':
    sys.exit(main())
