#!/usr/bin/env python3
"""Save bounded resource/OOM evidence without collecting environment or credentials."""
from datetime import datetime, timezone
import json
from pathlib import Path
import platform
import shutil
import sys


def read_counters(path):
    try:
        return {line.split()[0]: int(line.split()[1]) for line in Path(path).read_text().splitlines()}
    except (OSError, ValueError, IndexError):
        return {}


def resources(directory):
    memory = {}
    try:
        for line in Path('/proc/meminfo').read_text().splitlines():
            key, value = line.split(':', 1)
            if key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree'):
                memory[key + '_kb'] = int(value.split()[0])
    except (OSError, ValueError):
        pass
    cgroup = {}
    for name in ('memory.max', 'memory.current', 'memory.swap.max', 'memory.swap.current'):
        try:
            cgroup[name] = Path('/sys/fs/cgroup', name).read_text().strip()
        except OSError:
            pass
    return dict(memory=memory, cgroup=cgroup,
                oom_counters=read_counters('/sys/fs/cgroup/memory.events'),
                free_disk_bytes=shutil.disk_usage(directory).free)


def save(path, data):
    path = Path(path)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, indent=2) + '\n')
    temporary.replace(path)


def start(path, profile, action, directory):
    save(path, dict(profile=profile, action=action, source_directory=directory,
                    started_at=datetime.now(timezone.utc).isoformat(),
                    architecture=platform.machine(), before=resources(directory)))


def finish(path, code, stage, jobs, sync_jobs):
    data = json.loads(Path(path).read_text())
    after = resources(data['source_directory'])
    before_oom = data['before']['oom_counters']
    deltas = {key: max(0, value - before_oom.get(key, value))
              for key, value in after['oom_counters'].items()}
    data.update(finished_at=datetime.now(timezone.utc).isoformat(), exit_code=int(code),
                last_stage=stage, jobs=jobs, sync_jobs=sync_jobs, after=after,
                oom_counter_increases=deltas)
    if any(deltas.get(key, 0) for key in ('oom_kill', 'oom_group_kill')):
        data['memory_diagnosis'] = 'A cgroup OOM-kill counter increased during this run.'
    elif int(code) == 137:
        data['memory_diagnosis'] = 'SIGKILL/137: possible OOM or forced stop; no cgroup OOM kill was recorded.'
    else:
        data['memory_diagnosis'] = 'No cgroup OOM kill was observed; this does not rule out VM-level memory pressure.'
    save(path, data)
    print(f'Run report: {path}')
    if int(code):
        print(data['memory_diagnosis'])

if __name__ == '__main__':
    try:
        if sys.argv[1] == 'start':
            start(*sys.argv[2:])
        else:
            finish(*sys.argv[2:])
    except (OSError, ValueError, KeyError) as error:
        sys.exit(f'Cannot write run report: {error}')
