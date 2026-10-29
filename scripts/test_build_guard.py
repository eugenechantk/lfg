"""Small, real-process tests; never launch Xcode or allocate gigabytes."""
import importlib.util
import ctypes
import errno
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace
from unittest.mock import MagicMock

SCRIPT = Path(__file__).with_name('build_guard.py')
spec = importlib.util.spec_from_file_location('build_guard', SCRIPT)
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class OptionsTests(unittest.TestCase):
    def test_default_and_existing_options(self):
        args = ['test', '--only', 'Tests/A', '--xcodebuild-options=-enableCodeCoverage YES']
        out, heavy, mode = guard.prepare_flowdeck(args, {})
        self.assertTrue(heavy)
        self.assertEqual(mode, 'never')
        self.assertIn('-enableCodeCoverage YES', out[-1])
        self.assertIn('-collect-test-diagnostics never', out[-1])
        self.assertEqual(out[:3], args[:3])

    def test_opt_in_and_explicit_override(self):
        out, _, mode = guard.prepare_flowdeck(['test'], {'LFG_TEST_DIAGNOSTICS': 'on-failure'})
        self.assertEqual(mode, 'on-failure')
        args = ['test', '--xcodebuild-options', '-collect-test-diagnostics never -enableCodeCoverage YES']
        out, _, mode = guard.prepare_flowdeck(args, {'LFG_TEST_DIAGNOSTICS': 'on-failure'})
        self.assertEqual(mode, 'never')
        self.assertEqual(out, args)

    def test_metadata_commands_unchanged(self):
        for args in [['--help'], ['test', '--help'], ['test', 'discover'], ['test', 'plans'], ['simulator', 'list'], ['logs', 'abc']]:
            self.assertEqual(guard.prepare_flowdeck(args, {}), (args, False, None))

    def test_invalid_modes_and_ambiguous_options_rejected(self):
        for args, env in [(['test'], {'LFG_TEST_DIAGNOSTICS': 'yes'}),
                          (['test', '--xcodebuild-options'], {}),
                          (['test', '--xcodebuild-options=-collect-test-diagnostics yes'], {}),
                          (['test', '--xcodebuild-options=a', '--xcodebuild-options=b'], {})]:
            with self.assertRaises(ValueError):
                guard.prepare_flowdeck(args, env)

    def test_option_order_and_values_do_not_bypass_guard(self):
        for args in [['--json', 'test'], ['-c', 'test', 'test'], ['-i', 'test'], ['--changelog', 'test'],
                     ['test', '--only', 'discover'], ['run', '--launch-options', '--help']]:
            self.assertTrue(guard.prepare_flowdeck(args, {})[1])
        for args in [['test', '-e'], ['test', '-j', 'discover'],
                     ['test', '-c', 'build', 'plans'], ['help', 'test']]:
            self.assertEqual(guard.prepare_flowdeck(args, {}), (args, False, None))
        with self.assertRaises(ValueError):
            guard.prepare_flowdeck(['--interactive'], {})


class DiscoveryTests(unittest.TestCase):
    def test_native_abi_and_current_process_without_ps(self):
        # Independently confirmed by the SDK C sizeof/offsetof probe.
        self.assertEqual(ctypes.sizeof(guard.BSDShortInfo), 64)
        self.assertEqual([getattr(guard.BSDShortInfo, k).offset for k in
                          ('pid', 'ppid', 'pgid', 'comm', 'flags', 'reserved')], [0, 4, 8, 16, 32, 60])
        with patch.object(guard.subprocess, 'run', side_effect=AssertionError('No ps subprocess')):
            table = guard.processes()
        self.assertEqual(table[os.getpid()], (os.getppid(), os.getpgrp()))

    def test_native_buffer_growth_is_retried_without_truncation(self):
        calls = []
        def listing(buffer, size):
            calls.append(size)
            if buffer is None:
                return 1
            if len(calls) == 2:
                return len(buffer)
            buffer[0] = 4242
            return 1
        with patch.object(guard.LIB, 'proc_listallpids', side_effect=listing), \
             patch.object(guard, 'process_info', return_value=(1, 42)):
            self.assertEqual(guard.processes(), {4242: (1, 42)})
        self.assertEqual(len(calls), 3)

    def test_native_exit_race_is_skipped_but_permission_failure_is_unhealthy(self):
        def missing(*args):
            ctypes.set_errno(errno.ESRCH)
            return 0
        with patch.object(guard.LIB, 'proc_pidinfo', side_effect=missing):
            self.assertIsNone(guard.process_info(4242))
        def denied(*args):
            ctypes.set_errno(errno.EPERM)
            return 0
        with patch.object(guard.LIB, 'proc_pidinfo', side_effect=denied):
            with self.assertRaises(OSError):
                guard.process_info(4242)

    def test_degraded_discovery_measures_current_known_footprint(self):
        values = {100: {'birth': 10, 'footprint': 20}}
        with patch.object(guard, 'usage', side_effect=lambda pid: values.get(pid)):
            job = guard.Job(SimpleNamespace(pid=100))
            values[100]['footprint'] = 500
            with patch.object(guard, 'processes', side_effect=subprocess.TimeoutExpired('ps', 5)):
                self.assertEqual(job.sample(), 500)
        self.assertIsNotNone(job.discovery_error)

    def test_unaccountable_known_live_process_still_fails_closed(self):
        with patch.object(guard, 'usage', return_value={'birth': 10, 'footprint': 20}):
            job = guard.Job(SimpleNamespace(pid=100))
        with patch.object(guard, 'processes', side_effect=TimeoutError()), \
             patch.object(guard, 'usage', return_value=None), \
             patch.object(guard, 'process_info', return_value=(1, 100)):
            with self.assertRaisesRegex(RuntimeError, 'Cannot account'):
                job.sample()

    def test_discovery_grace_requires_an_accounted_owned_process(self):
        with patch.object(guard, 'usage', return_value=None):
            job = guard.Job(SimpleNamespace(pid=100, poll=lambda: None))
            with patch.object(guard, 'processes', side_effect=TimeoutError()):
                with self.assertRaisesRegex(RuntimeError, 'Cannot account'):
                    job.sample()

    def test_reused_root_pid_does_not_adopt_or_signal_foreign_group(self):
        with patch.object(guard, 'usage', return_value={'birth': 10, 'footprint': 20}):
            job = guard.Job(SimpleNamespace(pid=100, poll=lambda: 0))
        with patch.object(guard, 'usage', return_value={'birth': 99, 'footprint': 20}), \
             patch.object(guard, 'processes', return_value={100: (999, 100), 101: (100, 100)}), \
             patch.object(guard.os, 'kill') as kill:
            self.assertEqual(job.sample(), 0)
            job.signal(signal.SIGTERM)
            kill.assert_not_called()
            self.assertEqual(job.known, {100: 10})

    def test_reparented_candidate_is_not_adopted_or_signalled(self):
        values = {100: {'birth': 10, 'footprint': 20}, 101: {'birth': 11, 'footprint': 30}}
        with patch.object(guard, 'usage', side_effect=lambda pid: values.get(pid)):
            job = guard.Job(SimpleNamespace(pid=100))
            with patch.object(guard, 'processes', return_value={100: (1, 100), 101: (100, 100)}), \
                 patch.object(guard, 'process_info', return_value=(999, 999)), \
                 patch.object(guard.os, 'kill') as kill:
                self.assertEqual(job.sample(), 20)
                job.signal(signal.SIGTERM)
                self.assertEqual([call.args[0] for call in kill.call_args_list], [100])

    def test_candidate_birth_change_during_lookup_is_not_adopted(self):
        child_reads = [0]
        def usage(pid):
            if pid == 100:
                return {'birth': 10, 'footprint': 20}
            child_reads[0] += 1
            return {'birth': 11 if child_reads[0] == 1 else 99, 'footprint': 30}
        with patch.object(guard, 'usage', side_effect=usage):
            job = guard.Job(SimpleNamespace(pid=100))
            with patch.object(guard, 'processes', return_value={100: (1, 100), 101: (100, 100)}), \
                 patch.object(guard, 'process_info', return_value=(100, 100)), \
                 patch.object(guard.os, 'kill') as kill:
                self.assertEqual(job.sample(), 20)
                job.signal(signal.SIGTERM)
                self.assertEqual([call.args[0] for call in kill.call_args_list], [100])

    def test_rejected_ancestor_cannot_authorize_descendant(self):
        values = {100: {'birth': 10, 'footprint': 20},
                  101: {'birth': 11, 'footprint': 30},
                  102: {'birth': 12, 'footprint': 40}}
        table = {100: (1, 100), 101: (100, 101), 102: (101, 101)}
        with patch.object(guard, 'usage', side_effect=values.get):
            job = guard.Job(SimpleNamespace(pid=100, poll=lambda: None))
            with patch.object(guard, 'processes', return_value=table), \
                 patch.object(guard, 'process_info', side_effect=lambda pid: (999, 101) if pid == 101 else table[pid]), \
                 patch.object(guard.os, 'kill') as kill:
                self.assertEqual(job.sample(), 20)
                self.assertEqual(job.known, {100: 10})
                job.signal(signal.SIGTERM)
                self.assertEqual([c.args[0] for c in kill.call_args_list], [100])

    def test_unknown_exited_root_cannot_claim_reused_pid_or_group(self):
        with patch.object(guard, 'usage', return_value=None):
            job = guard.Job(SimpleNamespace(pid=100, poll=lambda: 0))
        with patch.object(guard, 'processes', return_value={100: (999, 100), 101: (100, 100)}), \
             patch.object(guard, 'usage', return_value={'birth': 99, 'footprint': 20}), \
             patch.object(guard.os, 'kill') as kill:
            self.assertEqual(job.sample(), 0)
            self.assertEqual(job.known, {})
            job.signal(signal.SIGTERM)
            kill.assert_not_called()

    def test_healthy_empty_snapshot_cannot_hide_unaccountable_live_root(self):
        with patch.object(guard, 'usage', return_value=None):
            job = guard.Job(SimpleNamespace(pid=100, poll=lambda: None))
            with patch.object(guard, 'processes', return_value={}):
                with self.assertRaisesRegex(RuntimeError, 'Cannot account'):
                    job.sample()

    def test_valid_nested_tree_is_fully_accounted(self):
        values = {100: {'birth': 10, 'footprint': 20},
                  101: {'birth': 11, 'footprint': 30},
                  102: {'birth': 12, 'footprint': 40}}
        table = {100: (1, 100), 101: (100, 101), 102: (101, 101)}
        with patch.object(guard, 'usage', side_effect=values.get):
            job = guard.Job(SimpleNamespace(pid=100, poll=lambda: None))
            with patch.object(guard, 'processes', return_value=table), \
                 patch.object(guard, 'process_info', side_effect=table.get):
                self.assertEqual(job.sample(), 90)
                self.assertEqual(job.known, {100: 10, 101: 11, 102: 12})

    def test_known_orphan_can_adopt_after_root_pid_reuse(self):
        values = {100: {'birth': 99, 'footprint': 20},
                  101: {'birth': 11, 'footprint': 30},
                  102: {'birth': 12, 'footprint': 40},
                  103: {'birth': 13, 'footprint': 50}}
        table = {100: (999, 100), 101: (1, 101), 102: (101, 101), 103: (100, 100)}
        job = guard.Job.__new__(guard.Job)
        job.process = SimpleNamespace(pid=100, poll=lambda: 0)
        job.known = {100: 10, 101: 11}
        job.discovery_error = None
        with patch.object(guard, 'usage', side_effect=values.get), \
             patch.object(guard, 'processes', return_value=table), \
             patch.object(guard, 'process_info', side_effect=table.get):
            self.assertEqual(job.sample(), 70)
            self.assertEqual(job.known, {100: 10, 101: 11, 102: 12})


class HealthPolicyTests(unittest.TestCase):
    def supervise(self, samples, exit_after=None, diagnostics=None, log_sizes=None, cancel=False):
        with tempfile.TemporaryDirectory() as temp:
            state = Path(temp)
            clock = [0.0]
            count = [0]
            handlers = {}
            job = SimpleNamespace(discovery_error=None, cleanup=MagicMock())
            def sample():
                item = samples[min(count[0], len(samples) - 1)]
                count[0] += 1
                if isinstance(item, Exception):
                    raise item
                footprint, job.discovery_error = item
                if cancel and count[0] == 1:
                    handlers[signal.SIGTERM](signal.SIGTERM, None)
                return footprint
            job.sample = sample
            process = SimpleNamespace(pid=100, poll=lambda: 0 if exit_after and count[0] >= exit_after else None)
            def install(sig, handler):
                handlers[sig] = handler
                return signal.SIG_DFL
            with patch.object(guard, 'state_dir', return_value=state), \
                 patch.object(guard.subprocess, 'Popen', return_value=process), \
                 patch.object(guard, 'Job', return_value=job), \
                 patch.object(guard.time, 'monotonic', side_effect=lambda: clock[0]), \
                 patch.object(guard.time, 'sleep', side_effect=lambda duration: clock.__setitem__(0, clock[0] + duration)), \
                 patch.object(guard.signal, 'signal', side_effect=install), \
                 patch.object(guard, 'log_size', side_effect=log_sizes or [0] * 100):
                code = guard.supervise(['fake-owned-child'], limit=100, interval=1, diagnostics=diagnostics, log_limit=100)
            status = json.loads((state / 'status.json').read_text())
            blocked = json.loads((state / 'blocked.json').read_text()) if (state / 'blocked.json').exists() else None
            events = [json.loads(line) for line in (state / 'events.jsonl').read_text().splitlines()]
            self.assertEqual(job.cleanup.call_count, 1)
            return code, status, blocked, events, clock[0]

    def test_sustained_failure_has_finite_thirty_second_grace(self):
        code, status, blocked, events, elapsed = self.supervise([(20, 'discovery failed')])
        self.assertEqual(code, 75)
        self.assertEqual(elapsed, 30)
        self.assertIn('unhealthy for 30 seconds', blocked['reason'])
        self.assertFalse(status['discoveryHealthy'])
        self.assertEqual(sum(e['event'] == 'discovery_degraded' for e in events), 1)

    def test_recovery_resets_continuous_failure_window(self):
        samples = [(20, 'failed'), (20, None)] + [(20, 'failed')] * 29 + [(20, None)]
        code, status, blocked, events, elapsed = self.supervise(samples, exit_after=len(samples))
        self.assertEqual(code, 0)
        self.assertIsNone(blocked)
        self.assertTrue(status['discoveryHealthy'])
        self.assertEqual(sum(e['event'] == 'discovery_recovered' for e in events), 2)

    def test_memory_limit_remains_immediate_during_degradation(self):
        code, status, blocked, events, elapsed = self.supervise([(100, 'failed')])
        self.assertEqual(code, 75)
        self.assertEqual(elapsed, 0)
        self.assertIn('footprint exceeded', blocked['reason'])

    def test_diagnostics_limit_remains_immediate_during_degradation(self):
        code, status, blocked, events, elapsed = self.supervise([(20, 'failed')], diagnostics='on-failure', log_sizes=[0, 101])
        self.assertEqual(code, 75)
        self.assertEqual(elapsed, 0)
        self.assertIn('diagnostics budget', blocked['reason'])

    def test_accounting_failure_is_not_given_discovery_grace(self):
        code, status, blocked, events, elapsed = self.supervise([RuntimeError('Cannot account for live job process')])
        self.assertEqual(code, 75)
        self.assertEqual(elapsed, 0)
        self.assertIn('memory monitoring failed', blocked['reason'])

    def test_cancellation_still_stops_owned_job_during_degradation(self):
        code, status, blocked, events, elapsed = self.supervise([(20, 'failed')], cancel=True)
        self.assertEqual(code, 143)
        self.assertIsNone(blocked)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.state = self.root / 'state'
        self.logs = self.root / 'sim-logs'
        self.logs.mkdir()
        self.env = dict(os.environ, LFG_BUILD_GUARD_STATE=str(self.state),
                        LFG_SIMULATOR_LOG_DIR=str(self.logs))
        self.procs = []

    def tearDown(self):
        for p in self.procs:
            if p.poll() is None:
                p.terminate()
                try:
                    p.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    p.kill()
                    p.wait()
            if p.stdout:
                p.stdout.close()
            if p.stderr:
                p.stderr.close()
        self.tmp.cleanup()

    def launch(self, code, limit=256, extra=()):
        cmd = [sys.executable, str(SCRIPT), 'run', '--limit-mib', str(limit),
               '--interval', '.05', '--grace', '.15', *extra, '--', sys.executable, '-c', code]
        p = subprocess.Popen(cmd, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.procs.append(p)
        return p

    def until(self, fn, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if fn():
                return
            time.sleep(.025)
        self.fail('condition timed out')

    def status(self):
        try:
            return json.loads((self.state / 'status.json').read_text())
        except (OSError, ValueError):
            return {}

    def test_native_footprint_and_identity(self):
        a = guard.usage(os.getpid())
        self.assertGreater(a['footprint'], 0)
        self.assertGreater(a['birth'], 0)
        self.assertEqual(a['birth'], guard.usage(os.getpid())['birth'])
        self.assertIsNone(guard.usage(99999999))

    def test_single_discovery_timeout_preserves_real_owned_child(self):
        marker = self.root / 'completed-after-fault'
        original = guard.processes
        injected = [False]
        def discover():
            if not injected[0]:
                injected[0] = True
                raise subprocess.TimeoutExpired(['/bin/ps', '-axo', 'pid=,ppid=,pgid='], 5)
            return original()
        command = [sys.executable, '-c',
                   f'import time,pathlib;time.sleep(.2);pathlib.Path({str(marker)!r}).touch()']
        with patch.dict(os.environ, self.env), patch.object(guard, 'processes', side_effect=discover):
            result = guard.supervise(command, limit=256 * guard.MIB, interval=.01, grace=.1)
        self.assertEqual(result, 0)
        self.assertTrue(marker.exists())
        self.assertFalse((self.state / 'blocked.json').exists())
        events = [json.loads(row) for row in (self.state / 'events.jsonl').read_text().splitlines()]
        self.assertEqual(sum(row['event'] == 'discovery_degraded' for row in events), 1)
        self.assertEqual(sum(row['event'] == 'discovery_recovered' for row in events), 1)

    def test_exit_code_and_streams_preserved(self):
        p = self.launch("import sys; print('normal output'); print('test failure',file=sys.stderr);sys.exit(7)")
        out, err = p.communicate(timeout=8)
        self.assertEqual(p.returncode, 7)
        self.assertIn('normal output', out)
        self.assertIn('test failure', err)
        self.assertFalse((self.state / 'blocked.json').exists())

    def test_child_memory_limit_cleanup_survivor_and_circuit(self):
        childpid = self.root / 'child.pid'
        survivor = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'])
        self.procs.append(survivor)
        child = "import time; x=bytearray(110*1024*1024); time.sleep(30)"
        code = f"import subprocess,sys,time,pathlib;p=subprocess.Popen([sys.executable,'-c',{child!r}]);pathlib.Path({str(childpid)!r}).write_text(str(p.pid));time.sleep(30)"
        p = self.launch(code, limit=80)
        out, err = p.communicate(timeout=10)
        self.assertEqual(p.returncode, 75, err)
        pid = int(childpid.read_text())
        self.until(lambda: guard.usage(pid) is None or guard.usage(pid)['footprint'] == 0)
        self.assertIsNone(survivor.poll())
        self.assertTrue((self.state / 'blocked.json').exists())
        blocked = self.launch("print('SHOULD NOT RUN')")
        out, _ = blocked.communicate(timeout=5)
        self.assertEqual(blocked.returncode, 75)
        self.assertNotIn('SHOULD NOT RUN', out)

    def test_serialization_and_cancel_release(self):
        firstmark = self.root / 'first'
        secondmark = self.root / 'second'
        first = self.launch(f"import pathlib,time;pathlib.Path({str(firstmark)!r}).touch();time.sleep(30)")
        self.until(firstmark.exists)
        second = self.launch(f"import pathlib;pathlib.Path({str(secondmark)!r}).touch()")
        time.sleep(.3)
        self.assertFalse(secondmark.exists())
        first.terminate()
        first.communicate(timeout=8)
        second.communicate(timeout=8)
        self.assertEqual(first.returncode, 143)
        self.assertEqual(second.returncode, 0)
        self.assertTrue(secondmark.exists())

    def test_diagnostic_preflight_and_growth(self):
        (self.logs / 'CoreSimulator.prev.log').write_bytes(b'x' * 2000)
        p = self.launch("print('SHOULD NOT RUN')", extra=['--diagnostics', 'on-failure', '--log-limit-bytes', '1000'])
        out, _ = p.communicate(timeout=5)
        self.assertEqual(p.returncode, 78)
        self.assertNotIn('SHOULD NOT RUN', out)
        (self.logs / 'CoreSimulator.prev.log').unlink()
        log = self.logs / 'CoreSimulator.log'
        p = self.launch(f"import pathlib,time;pathlib.Path({str(log)!r}).write_bytes(b'x'*2000);time.sleep(30)",
                        extra=['--diagnostics', 'on-failure', '--log-limit-bytes', '1000'])
        p.communicate(timeout=8)
        self.assertEqual(p.returncode, 75)

    def test_vendor_arguments_and_default_guarded_limits(self):
        vendor = self.root / 'vendor'
        vendor.write_text('#!/usr/bin/python3\nimport sys,json\nprint(json.dumps(sys.argv[1:]))\n')
        vendor.chmod(0o755)
        cmd = [sys.executable, str(SCRIPT), 'flowdeck', '--vendor', str(vendor), '--', 'test', '--only', 'Tests/A']
        p = subprocess.run(cmd, env=self.env, text=True, capture_output=True, timeout=8)
        self.assertEqual(p.returncode, 0, p.stderr)
        args = json.loads(p.stdout)
        self.assertIn('-collect-test-diagnostics never', args[-1])
        self.assertEqual(self.status()['limitBytes'], 12 * 1024**3)

    def test_observed_detached_child_cleaned_after_parent_exit(self):
        childpid = self.root / 'detached.pid'
        child = "import time;time.sleep(30)"
        code = f"import subprocess,sys,time,pathlib;p=subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True);pathlib.Path({str(childpid)!r}).write_text(str(p.pid));time.sleep(.4)"
        p = self.launch(code)
        p.communicate(timeout=8)
        self.assertEqual(p.returncode, 0)
        pid = int(childpid.read_text())
        self.until(lambda: guard.usage(pid) is None or guard.usage(pid)['footprint'] == 0)

    def test_cancelled_waiter_does_not_stop_active_job(self):
        mark = self.root / 'active'
        first = self.launch(f"import pathlib,time;pathlib.Path({str(mark)!r}).touch();time.sleep(30)")
        self.until(mark.exists)
        second = self.launch("print('SHOULD NOT RUN')")
        time.sleep(.2)
        second.terminate()
        out, _ = second.communicate(timeout=5)
        self.assertEqual(second.returncode, 143)
        self.assertNotIn('SHOULD NOT RUN', out)
        self.assertIsNone(first.poll())

    def test_explicit_reset_clears_breaker(self):
        self.state.mkdir()
        (self.state / 'blocked.json').write_text('{"reason":"fixture"}')
        result = subprocess.run([sys.executable, str(SCRIPT), 'reset'], env=self.env, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        p = self.launch("print('resumed')")
        out, _ = p.communicate(timeout=5)
        self.assertEqual(p.returncode, 0)
        self.assertIn('resumed', out)


if __name__ == '__main__':
    unittest.main()
