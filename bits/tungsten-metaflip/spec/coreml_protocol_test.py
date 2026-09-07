#!/usr/bin/env python3
"""Focused mocked-helper protocol and fail-fast CLI integration checks.

Every subprocess has a three-second wall limit and no GPU is launched. The
same file is an executable mock helper when invoked with the --serve protocol.
"""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


def atomic_write(path, body):
    temporary = path.with_suffix(path.suffix + ".mocktmp")
    temporary.write_text(body)
    temporary.replace(path)


def mock_helper():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--workers")
    parser.add_argument("--compute")
    parser.add_argument("--serve", nargs=2, required=True)
    parser.add_argument("--poll-us")
    options = parser.parse_args()
    request, response = map(Path, options.serve)
    directory = request.parent
    (directory / "mock.pid").write_text(str(os.getpid()))
    mode = options.model
    if mode == "crash":
        (directory / "mock.done").write_text("crashed")
        return 17
    stop = Path(str(request) + ".stop")
    seen = ""
    deadline = time.monotonic() + 2.5
    while time.monotonic() < deadline and not stop.exists():
        body = request.read_text() if request.exists() else ""
        if body and body != seen and mode != "timeout":
            seen = body
            header = body.splitlines()[0].split("\t")
            epoch, count = int(header[1]), int(header[2])
            if mode == "stale":
                epoch -= 1
            if mode == "future":
                epoch += 1
            score = {"junk": "1junk", "nan": "NaN", "inf": "1e999", "limit": "1000000000"}.get(mode)
            lines = [f"epoch\t{epoch}\t{count}"]
            for index in range(count):
                lines.append(f"{index}\t{score if score is not None else index + 0.25}")
            atomic_write(response, "\n".join(lines) + "\n")
        time.sleep(0.005)
    (directory / "mock.done").write_text("stopped" if stop.exists() else "expired")
    return 0


def bounded_run(command):
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        out, err = process.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise AssertionError(f"Process exceeded three seconds: {command}")
    return process.returncode, out, err


class CoreMLProtocolTests(unittest.TestCase):
    def test_mocked_protocol_and_cleanup(self):
        for mode in ("valid", "stale", "future", "junk", "nan", "inf", "limit", "corrupt", "snapshot", "timeout", "crash"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix="metaflip-coreml-protocol-", dir=OPTIONS.scratch) as directory:
                pid_path = Path(directory) / "mock.pid"
                try:
                    code, out, err = bounded_run([OPTIONS.protocol_bin, directory, str(Path(__file__).resolve()), mode])
                    self.assertEqual(code, 0, out + err)
                    self.assertIn("PASS CoreML protocol " + mode, out)
                    self.assertTrue(pid_path.exists(), out + err)
                    pid = int(pid_path.read_text())
                    try:
                        os.kill(pid, 0)
                    except ProcessLookupError:
                        pass
                    else:
                        self.fail(f"Mock helper {pid} leaked after {mode}")
                    self.assertTrue((Path(directory) / "mock.done").exists())
                finally:
                    # A failed coordinator assertion must not leave the owned
                    # mock child behind while its temporary directory is removed.
                    if pid_path.exists():
                        try:
                            os.kill(int(pid_path.read_text()), signal.SIGTERM)
                        except ProcessLookupError:
                            pass

    def test_cli_rejects_unsupported_coreml_configuration_before_workers(self):
        base = [OPTIONS.fleet_bin, "--tensor", "5x5", "-J", "1", "--no-gpu", "--quiet", "--secs", "1", "--coreml-model", "mock-model", "--coreml-helper", str(Path(__file__).resolve())]
        cases = [(["--tensor", "4x4"], "5x5 only"), (["--coreml-workers", "3"], "1, 2, or 4"), (["--coreml-workers", "2junk"], "integer"), (["--coreml-compute", "all"], "cpuAndNeuralEngine or cpuOnly")]
        for arguments, message in cases:
            with self.subTest(arguments=arguments):
                code, out, err = bounded_run(base + arguments)
                self.assertEqual(code, 2, out + err)
                self.assertIn(message, out + err)
                self.assertNotIn("METAFLIP_COREML batches=", out + err)


if __name__ == "__main__":
    if "--serve" in sys.argv:
        sys.exit(mock_helper())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--protocol-bin", required=True)
    parser.add_argument("--fleet-bin", required=True)
    parser.add_argument("--scratch", required=True, help="Existing ignored worktree scratch directory")
    OPTIONS = parser.parse_args()
    unittest.main(argv=[sys.argv[0]], verbosity=2)
