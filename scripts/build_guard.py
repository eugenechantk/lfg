#!/usr/bin/python3
"""Bounded macOS build supervisor. No third-party dependencies."""
import argparse
import ctypes
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


class RUsage(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_ubyte * 16)] + [
        (name, ctypes.c_uint64) for name in (
            'user', 'system', 'idle', 'interrupts', 'pageins', 'wired',
            'resident', 'footprint', 'birth', 'exit')]


LIB = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
LIB.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
LIB.proc_pid_rusage.restype = ctypes.c_int


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
    result = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,pgid='], capture_output=True, text=True, timeout=5, check=True)
    return {int(p): (int(parent), int(group)) for line in result.stdout.splitlines() for p, parent, group in [line.split()]}


class Job:
    def __init__(self, process):
        self.process = process
        self.known = {}
        info = usage(process.pid)
        if info:
            self.known[process.pid] = info['birth']

    def sample(self):
        table = processes()
        live = {}
        for pid, birth in self.known.items():
            info = usage(pid)
            if info and info['birth'] == birth:
                live[pid] = info
        candidates = set(live)
        candidates.update(pid for pid, (_, group) in table.items() if group == self.process.pid)
        changed = True
        while changed:
            new = {pid for pid, (parent, _) in table.items() if parent in candidates}
            changed = not new.issubset(candidates)
            candidates.update(new)
        for pid in candidates:
            info = usage(pid)
            if info is None:
                if pid in table:
                    # A process can exit between ps and libproc; distinguish that race.
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        continue
                    raise RuntimeError('Cannot account for live job process %s' % pid)
                continue
            self.known[pid] = info['birth']
            live[pid] = info
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
                if footprint >= limit:
                    reason = 'job physical footprint exceeded limit'
                elif diagnostics == 'on-failure' and log_size() > log_limit:
                    reason = 'CoreSimulator logs exceeded diagnostics budget'
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
