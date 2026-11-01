"""Stage deadlines and cancellation own the entire subprocess group."""
import contextlib
import os
import signal
import subprocess
import threading
import time


class Cancelled(RuntimeError):
    pass


class StageTimeout(RuntimeError):
    pass


class Runner:
    def __init__(self, timeout=3600, grace=2):
        if timeout is not None and timeout <= 0:
            raise ValueError('stage timeout must be positive')
        self.timeout = timeout
        self.grace = grace
        self.cancelled = threading.Event()
        self._active = set()
        self._lock = threading.RLock()

    def check_cancelled(self):
        if self.cancelled.is_set():
            raise Cancelled('pipeline cancelled')

    def cancel(self):
        self.cancelled.set()
        with self._lock:
            processes = list(self._active)
        for process in processes:
            self._signal(process, signal.SIGTERM)

    @staticmethod
    def _signal(process, sig):
        try:
            if getattr(process, "owns_group", True):
                os.killpg(process.pid, sig)
            else:
                os.kill(process.pid, sig)
        except ProcessLookupError:
            pass
        except PermissionError as error:
            # macOS can return EPERM for an already-reaped process group.
            # A live child still requires successful cancellation.
            try:
                process.wait(timeout=.1)
            except subprocess.TimeoutExpired:
                raise error

    def _stop(self, process):
        self._signal(process, signal.SIGTERM)
        try:
            process.wait(timeout=self.grace)
        except subprocess.TimeoutExpired:
            pass
        # Grandchildren can survive after their immediate parent has exited.
        self._signal(process, signal.SIGKILL)
        process.wait()

    def run(self, argv, *, cwd=None, env=None, capture=False, timeout=None, log=None):
        if self.cancelled.is_set():
            raise Cancelled('pipeline cancelled before starting a stage')
        deadline = self.timeout if timeout is None else timeout
        # Nested toolkit supervisors inherit the outer stage's group. Otherwise
        # a hard timeout could kill an intermediate supervisor before it kills
        # its separately-sessioned grandchildren.
        owns_group = os.environ.get('TW_SUPERVISED_GROUP') != '1'
        child_env = dict(os.environ if env is None else env, TW_SUPERVISED_GROUP='1',
                         TUNGSTEN_INHERIT_PROCESS_GROUP='1')
        process = subprocess.Popen(list(map(str, argv)), cwd=cwd, env=child_env,
                                   start_new_session=owns_group,
                                   stdout=subprocess.PIPE if capture or log else None,
                                   stderr=subprocess.PIPE if capture else subprocess.STDOUT)
        process.owns_group = owns_group
        with self._lock:
            self._active.add(process)
        reader = None
        if log:
            def copy_log():
                for block in iter(lambda: process.stdout.read1(65536), b''):
                    log.write(block); log.flush()
                    # Keep CLI output visible without buffering an entire render log.
                    import sys
                    sys.stdout.buffer.write(block); sys.stdout.buffer.flush()
            reader = threading.Thread(target=copy_log, daemon=True)
            reader.start()
        started = time.monotonic()
        try:
            while True:
                if self.cancelled.is_set():
                    raise Cancelled(f'cancelled: {argv[0]}')
                remaining = None if deadline is None else deadline - (time.monotonic() - started)
                if remaining is not None and remaining <= 0:
                    raise StageTimeout(f'stage exceeded {deadline:g}s: {argv[0]}')
                interval = min(.1, remaining) if remaining is not None else .1
                try:
                    if capture:
                        stdout, stderr = process.communicate(timeout=interval)
                    else:
                        process.wait(timeout=interval)
                        stdout = stderr = None
                    break
                except subprocess.TimeoutExpired:
                    continue
            if self.cancelled.is_set():
                raise Cancelled(f'cancelled: {argv[0]}')
            if process.returncode:
                raise subprocess.CalledProcessError(process.returncode, argv, stdout, stderr)
            if reader:
                reader.join(timeout=self.grace)
                if reader.is_alive():
                    self._signal(process, signal.SIGKILL)
                    reader.join(timeout=self.grace)
            if owns_group:
                self._signal(process, signal.SIGKILL)
            return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)
        except BaseException:
            self._stop(process)
            if reader:
                reader.join(timeout=self.grace)
            raise
        finally:
            with self._lock:
                self._active.discard(process)
            if process.stdout:
                process.stdout.close()
            if process.stderr:
                process.stderr.close()

    @contextlib.contextmanager
    def signals(self):
        previous = {}
        def interrupted(signum, frame):
            self.cancel()
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, interrupted)
        try:
            yield self
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
