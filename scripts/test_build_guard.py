"""Small, real-process tests; never launch Xcode or allocate gigabytes."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

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
