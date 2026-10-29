#!/usr/bin/python3
"""Bounded macOS build supervisor. No third-party dependencies."""
import argparse
import ctypes
import errno
import fcntl
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import time

MIB = 1024 ** 2
DEFAULT_LIMIT = 12 * 1024 * MIB
DISCOVERY_GRACE = 30.0


class RUsage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_ubyte * 16)] + [
        (name, ctypes.c_uint64) for name in (
            'user', 'system', 'idle', 'interrupts', 'pageins', 'wired',
            'resident', 'footprint', 'birth', 'exit')]


class BSDShortInfo(ctypes.Structure):
    # SDK sys/proc_info.h: struct proc_bsdshortinfo (64 bytes on macOS).
    _fields_ = [(name, ctypes.c_uint32) for name in ('pid', 'ppid', 'pgid', 'status')]
    _fields_ += [('comm', ctypes.c_char * 16)]
    _fields_ += [(name, ctypes.c_uint32) for name in
                ('flags', 'uid', 'gid', 'ruid', 'rgid', 'svuid', 'svgid', 'reserved')]


LIB = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
LIB.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
LIB.proc_pid_rusage.restype = ctypes.c_int
LIB.proc_listallpids.argtypes = [ctypes.c_void_p, ctypes.c_int]
LIB.proc_listallpids.restype = ctypes.c_int
LIB.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
LIB.proc_pidinfo.restype = ctypes.c_int


def usage(pid):
    info = RUsage()
    if LIB.proc_pid_rusage(pid, 0, ctypes.byref(info)) != 0:
        return None
    return {'footprint': info.footprint, 'birth': info.birth}


def prepare_flowdeck(args, env):
    args = list(args)
    # Skip option values when finding commands/metadata: a scheme named
    # 'discover' or an app argument '--help' must not disable supervision.
    value_options = {'-c', '--config', '-p', '--project', '-w', '--workspace',
                     '-s', '--scheme', '-C', '--configuration', '-S', '--simulator',
                     '-D', '--device', '-d', '--derived-data-path', '--test-targets',
                     '--test-cases', '--plan', '--only', '--skip', '--xcodebuild-options',
                     '--xcodebuild-env', '--launch-options', '--launch-env'}
    words = []
    flags = set()
    i = 0
    while i < len(args):
        token = args[i]
        if token in value_options:
            i += 2
            continue
        if token.startswith('-'):
            flags.add(token.split('=', 1)[0])
        else:
            words.append(token)
        i += 1
    if not args or flags.intersection(('--help', '-h', '--examples', '-e')) or words[:1] == ['help']:
        return args, False, None
    if not words and flags.intersection(('--interactive', '-i')):
        raise ValueError('Interactive builds cannot select diagnostics safely; use explicit build/run/test commands')
    action = words[0] if words else None
    if action not in ('build', 'run', 'test') or (action == 'test' and len(words) > 1 and words[1] in ('discover', 'plans')):
        return args, False, None
    if action != 'test':
        return args, True, None
    indices = [i for i, x in enumerate(args) if x == '--xcodebuild-options' or x.startswith('--xcodebuild-options=')]
    if len(indices) > 1:
        raise ValueError('Use one --xcodebuild-options argument')
    value = ''
    index = indices[0] if indices else None
    equals = index is not None and '=' in args[index]
    if index is not None:
        if equals:
            value = args[index].split('=', 1)[1]
        elif index + 1 < len(args) and not args[index + 1].startswith('--'):
            value = args[index + 1]
        else:
            raise ValueError('--xcodebuild-options requires a value')
    tokens = shlex.split(value)
    explicit = []
    for i, token in enumerate(tokens):
        if token == '-collect-test-diagnostics':
            explicit.append(tokens[i + 1] if i + 1 < len(tokens) else '')
        elif token.startswith('-collect-test-diagnostics='):
            explicit.append(token.split('=', 1)[1])
    if len(explicit) > 1:
        raise ValueError('Specify diagnostics mode only once')
    mode = explicit[0] if explicit else env.get('LFG_TEST_DIAGNOSTICS', 'never')
    if mode not in ('never', 'on-failure'):
        raise ValueError('Diagnostics must be never or on-failure')
    if explicit:
        return args, True, mode
    value = (value + ' -collect-test-diagnostics ' + mode).strip()
    if index is None:
        args.append('--xcodebuild-options=' + value)
    elif equals:
        args[index] = '--xcodebuild-options=' + value
    else:
        args[index + 1] = value
    return args, True, mode


def state_dir():
    path = Path(os.environ.get('LFG_BUILD_GUARD_STATE', '~/.local/state/lfg-build-guard')).expanduser()
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    return path


def write_json(path, value):
    tmp = path.with_name(path.name + '.' + str(os.getpid()) + '.tmp')
    tmp.write_text(json.dumps(value, indent=2) + '\n')
    os.chmod(tmp, 0o600)
    tmp.replace(path)


def event(state, kind, **data):
    path = state / 'events.jsonl'
    if path.exists() and path.stat().st_size > MIB:
        for n in (2, 1):
            older = state / ('events.jsonl.' + str(n))
            if older.exists():
                older.replace(state / ('events.jsonl.' + str(n + 1)))
        path.replace(state / 'events.jsonl.1')
    with path.open('a') as f:
        f.write(json.dumps(dict(time=time.time(), event=kind, **data)) + '\n')
    os.chmod(path, 0o600)


def processes():
    # Apple libproc.c returns PID counts here, not buffer bytes. Grow on a full
    # buffer rather than silently accepting a truncated process snapshot.
    ctypes.set_errno(0)
    capacity = LIB.proc_listallpids(None, 0) + 64
    for _ in range(3):
        if not 64 < capacity <= 1024 * 1024:
            raise OSError(ctypes.get_errno() or errno.EIO, 'Cannot size native process list')
        pids = (ctypes.c_int * capacity)()
        ctypes.set_errno(0)
        count = LIB.proc_listallpids(pids, ctypes.sizeof(pids))
        if count <= 0:
            raise OSError(ctypes.get_errno() or errno.EIO, 'Cannot enumerate native processes')
        if count < capacity:
            return {pid: info for pid in pids[:count] if pid > 0
                    if (info := process_info(pid)) is not None}
        capacity *= 2
    raise RuntimeError('Native process list kept growing; snapshot is incomplete')


def process_info(pid):
    info = BSDShortInfo()
    ctypes.set_errno(0)
    size = LIB.proc_pidinfo(pid, 13, 0, ctypes.byref(info), ctypes.sizeof(info))
    if size == ctypes.sizeof(info) and info.pid == pid:
        return info.ppid, info.pgid
    error = ctypes.get_errno()
    if error in (errno.ESRCH, errno.ENOENT):
        return None  # Normal exit between enumeration and metadata lookup.
    raise OSError(error or errno.EIO, 'Cannot inspect native process %s' % pid)


class Job:
    def __init__(self, process):
        self.process = process
        self.known = {}
        self.discovery_error = None
        info = usage(process.pid)
        if info:
            self.known[process.pid] = info['birth']

    def sample(self):
        try:
            table = processes()
            self.discovery_error = None
        except Exception as error:
            # Keep measuring the birth-checked owned set during bounded discovery
            # degradation. Never replace current footprints with stale values.
            table = {}
            self.discovery_error = str(error)
        live = {}
        for pid, birth in self.known.items():
            info = usage(pid)
            if info and info['birth'] == birth:
                live[pid] = info
            elif info is None:
                if process_info(pid) is not None:
                    raise RuntimeError('Cannot account for live job process %s' % pid)
        root = self.process.pid
        if root not in live and (root not in self.known or not live) and self.process.poll() is None:
            # Popen still owns this unreaped child: a PID cannot be recycled
            # while that original child is alive. Acquire its birth only here,
            # never from a later process table after Popen reports exit.
            info = usage(root)
            if (info is None or self.process.poll() is not None or
                    (root in self.known and info['birth'] != self.known[root])):
                raise RuntimeError('Cannot account for live job root %s' % root)
            self.known[root] = info['birth']
            live[root] = info

        def birth_matches(pid):
            info = usage(pid)
            return info is not None and info['birth'] == self.known[pid]

        # Expand only from validated owned nodes. A candidate rejected for
        # changed ancestry or birth must never authorize its own descendants.
        remaining = set(table) - set(live)
        while remaining:
            adopted = set()
            for pid in sorted(remaining):
                parent, group = table[pid]
                anchor = parent if parent in live else root if root in live and group == root else None
                if anchor is None or not birth_matches(anchor):
                    continue
                info = usage(pid)
                if info is None:
                    if process_info(pid) is not None:
                        raise RuntimeError('Cannot account for live job process %s' % pid)
                    continue
                if pid in self.known and info['birth'] != self.known[pid]:
                    continue
                if process_info(pid) != table[pid]:
                    continue
                again = usage(pid)
                if (again is None or again['birth'] != info['birth'] or
                        not birth_matches(anchor)):
                    continue
                self.known[pid] = again['birth']
                live[pid] = again
                adopted.add(pid)
            if not adopted:
                break
            remaining.difference_update(adopted)
        return sum(info['footprint'] for info in live.values())

    def signal(self, sig):
        # Each PID is rechecked by kernel birth identity before signalling.
        for pid, birth in list(self.known.items()):
            info = usage(pid)
            if info and info['birth'] == birth:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass

    def cleanup(self, grace):
        try:
            self.sample()
        except Exception:
            pass
        self.signal(signal.SIGTERM)
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline:
            self.process.poll()
            try:
                self.sample()
            except Exception:
                pass
            self.signal(signal.SIGTERM)
            alive = False
            for pid, birth in list(self.known.items()):
                info = usage(pid)
                alive = alive or bool(info and info['birth'] == birth and info['footprint'])
            if not alive:
                break
            time.sleep(.025)
        self.signal(signal.SIGKILL)
        self.process.wait(timeout=5)


def log_size():
    root = Path(os.environ.get('LFG_SIMULATOR_LOG_DIR', '~/Library/Logs/CoreSimulator')).expanduser()
    total = 0
    for name in ('CoreSimulator.log', 'CoreSimulator.prev.log'):
        try:
            total += (root / name).stat().st_size
        except FileNotFoundError:
            pass
    return total


def supervise(command, limit=DEFAULT_LIMIT, interval=1.0, grace=3.0, diagnostics=None, log_limit=250 * MIB):
    state = state_dir()
    cancelled = [0]
    old_handlers = {}
    for sig in (signal.SIGINT, signal.SIGTERM):
        old_handlers[sig] = signal.signal(sig, lambda signum, frame: cancelled.__setitem__(0, signum))
    lock = (state / 'job.lock').open('a')
    job = None
    record = None
    try:
        announced = False
        while True:
            if cancelled[0]:
                return 128 + cancelled[0]
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if not announced:
                    print('Build guard: waiting for the active build/test job.', file=sys.stderr)
                    announced = True
                time.sleep(.1)
        if (state / 'blocked.json').exists():
            print('Build guard: blocked after a resource failure. Inspect lfg-build-guard status, then deliberately reset.', file=sys.stderr)
            return 75
        if diagnostics == 'on-failure' and log_size() > log_limit:
            print('Build guard: CoreSimulator logs exceed the diagnostics budget; archive inactive logs or run with diagnostics never.', file=sys.stderr)
            return 78
        proc = subprocess.Popen(command, start_new_session=True)
        job = Job(proc)
        record = dict(pid=proc.pid, supervisorPid=os.getpid(), command=Path(command[0]).name,
                      cwd=os.getcwd(), started=time.time(), limitBytes=limit, diagnostics=diagnostics,
                      session=os.environ.get('CLAUDE_SESSION_ID') or os.environ.get('CODEX_THREAD_ID'), peakBytes=0, status='running')
        event(state, 'start', **record)
        warned = False
        discovery_failed_at = None
        result = 0
        while True:
            reason = None
            if cancelled[0]:
                result = 128 + cancelled[0]
                break
            try:
                footprint = job.sample()
                record['footprintBytes'] = footprint
                record['peakBytes'] = max(record['peakBytes'], footprint)
                if job.discovery_error is not None:
                    if discovery_failed_at is None:
                        discovery_failed_at = time.monotonic()
                        event(state, 'discovery_degraded', error=job.discovery_error)
                    record.update(discoveryHealthy=False, discoveryError=job.discovery_error,
                                  discoveryUnhealthySeconds=time.monotonic() - discovery_failed_at)
                else:
                    if discovery_failed_at is not None:
                        event(state, 'discovery_recovered', unhealthySeconds=time.monotonic() - discovery_failed_at)
                    discovery_failed_at = None
                    record.update(discoveryHealthy=True, discoveryUnhealthySeconds=0)
                    record.pop('discoveryError', None)
                if footprint >= limit:
                    reason = 'job physical footprint exceeded limit'
                elif diagnostics == 'on-failure' and log_size() > log_limit:
                    reason = 'CoreSimulator logs exceeded diagnostics budget'
                elif discovery_failed_at is not None and time.monotonic() - discovery_failed_at >= DISCOVERY_GRACE:
                    reason = 'process discovery unhealthy for 30 seconds: ' + job.discovery_error
            except Exception as error:
                reason = 'memory monitoring failed: ' + str(error)
            if reason:
                write_json(state / 'blocked.json', dict(record, reason=reason, failed=time.time()))
                print('Build guard: stopping owned job: ' + reason, file=sys.stderr)
                result = 75
                break
            if not warned and footprint >= 4096 * MIB:
                print('Build guard: job physical footprint passed 4 GiB.', file=sys.stderr)
                event(state, 'warning', footprintBytes=footprint)
                warned = True
            write_json(state / 'status.json', record)
            code = proc.poll()
            if code is not None:
                result = code if code >= 0 else 128 - code
                break
            time.sleep(interval)
        job.cleanup(grace)
        job = None
        record.update(status='finished', finished=time.time(), exitCode=result)
        write_json(state / 'status.json', record)
        event(state, 'finish', **record)
        return result
    finally:
        if job:
            job.cleanup(grace)
        lock.close()
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    flow = sub.add_parser('flowdeck')
    flow.add_argument('--vendor', required=True)
    flow.add_argument('args', nargs=argparse.REMAINDER)
    run = sub.add_parser('run')
    run.add_argument('--limit-mib', type=float, default=12288)
    run.add_argument('--interval', type=float, default=1)
    run.add_argument('--grace', type=float, default=3)
    run.add_argument('--diagnostics', choices=['never', 'on-failure'])
    run.add_argument('--log-limit-bytes', type=int, default=250 * MIB)
    run.add_argument('args', nargs=argparse.REMAINDER)
    sub.add_parser('status')
    sub.add_parser('reset', help='Clear the breaker after inspecting and resolving its cause')
    options = parser.parse_args(argv)
    if options.action in ('status', 'reset'):
        state = state_dir()
        if options.action == 'status':
            print(json.dumps({name: json.loads((state / (name + '.json')).read_text()) if (state / (name + '.json')).exists() else None for name in ('status', 'blocked')}, indent=2))
        else:
            with (state / 'job.lock').open('a') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    parser.error('Cannot reset while a job is running')
                (state / 'blocked.json').unlink(missing_ok=True)
                event(state, 'reset')
        return 0
    args = options.args[1:] if options.args[:1] == ['--'] else options.args
    if options.action == 'flowdeck':
        args, heavy, mode = prepare_flowdeck(args, os.environ)
        if not heavy:
            os.execv(options.vendor, [options.vendor] + args)
        return supervise([options.vendor] + args, diagnostics=mode)
    if not args:
        parser.error('run requires a command after --')
    if not (0 < options.limit_mib <= 12288 and .01 <= options.interval <= 1 and 0 <= options.grace <= 10 and options.log_limit_bytes > 0):
        parser.error('Invalid guard limits: maximum 12288 MiB; sample .01–1 seconds; grace 0–10 seconds')
    return supervise(args, int(options.limit_mib * MIB), options.interval, options.grace, options.diagnostics, options.log_limit_bytes)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        print('Build guard: ' + str(exc), file=sys.stderr)
        sys.exit(78)
