#!/usr/bin/env python3
"""Fast public-REPL contracts: self-hosted launch, history, and recovery."""

from __future__ import annotations

import os
import pty
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WIT = ROOT / "bin" / "wit"
TUNGSTEN = ROOT / "bin" / "tungsten"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
HOMEBREW_CACHE = ROOT / "build" / "cache" / "repl-contracts" / "homebrew"


def fail(message: str, output: str = "") -> None:
    if output:
        print(output, file=sys.stderr)
    raise SystemExit(message)


def run_pipe(command: list[str], source: str, home: Path) -> tuple[int, str]:
    home.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(
        {"HOME": str(home), "NO_COLOR": "1", "HOMEBREW_CACHE": str(HOMEBREW_CACHE)}
    )
    result = subprocess.run(
        command,
        input=source,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        cwd=ROOT,
        check=False,
        timeout=20,
    )
    return result.returncode, ANSI.sub("", result.stdout)


def recall_seeded_history(home: Path) -> str:
    home.mkdir(parents=True, exist_ok=True)
    (home / ".tungsten_history").write_text("40 + 2\n", encoding="utf-8")
    pid, fd = pty.fork()
    if pid == 0:
        env = os.environ.copy()
        env.update(
            {"HOME": str(home), "NO_COLOR": "1", "HOMEBREW_CACHE": str(HOMEBREW_CACHE)}
        )
        os.execve(str(WIT), [str(WIT)], env)

    output = bytearray()

    def drain(seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    output.extend(os.read(fd, 8192))
                except OSError:
                    return

    try:
        drain(1.2)
        os.write(fd, b"\x1b[A\n")
        drain(0.4)
        os.write(fd, b"\x04")
        drain(0.3)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        os.waitpid(pid, 0)
    return ANSI.sub("", output.decode("utf-8", "replace"))


def cold_checkout_contract(tmp: Path) -> None:
    fake_root = tmp / "cold"
    fake_bin = fake_root / "bin"
    fake_commands = fake_bin / "commands"
    fake_commands.mkdir(parents=True)
    shutil.copy2(WIT, fake_bin / "wit")
    shutil.copy2(TUNGSTEN, fake_bin / "tungsten")
    shutil.copy2(ROOT / "bin" / "commands" / "config.sh", fake_commands / "config.sh")
    shutil.copy2(ROOT / "VERSION", fake_root / "VERSION")
    for command in ([str(fake_bin / "wit")], [str(fake_bin / "tungsten"), "console"]):
        result = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
            timeout=5,
        )
        if result.returncode != 1 or "run bin/tungsten bootstrap" not in result.stdout:
            fail(f"cold {' '.join(command)} did not require the self-hosted bootstrap", result.stdout)


def main() -> int:
    if not (ROOT / "bin" / "tungsten-compiler").exists():
        fail("core REPL contract requires bin/tungsten-compiler")

    with tempfile.TemporaryDirectory(
        prefix="tungsten-repl-core-", ignore_cleanup_errors=True
    ) as raw_tmp:
        tmp = Path(raw_tmp)
        home = tmp / "home"
        home.mkdir()

        status, output = run_pipe(
            [str(WIT)],
            "1 + 1\ncamelCase = 1\n2 + 3\n1 / 0\n3 + 4\n",
            home,
        )
        if status != 0:
            fail(f"wit exited {status}", output)
        for expected in ("=> 2", "E_LEX_INVALID_IDENTIFIER", "=> 5", "=> 7"):
            if expected not in output:
                fail(f"wit output missed {expected!r}", output)
        if "error:" not in output:
            fail("runtime error was not formatted", output)

        history = (home / ".tungsten_history").read_text(encoding="utf-8")
        for line in ("1 + 1", "camelCase = 1", "2 + 3", "1 / 0", "3 + 4"):
            if line not in history:
                fail(f"history missed {line!r}", history)

        console_status, console_output = run_pipe(
            [str(TUNGSTEN), "console"], "20 + 22\n", tmp / "console-home"
        )
        if console_status != 0 or "=> 42" not in console_output:
            fail("tungsten console did not use the self-hosted REPL", console_output)

        recalled = recall_seeded_history(tmp / "history-home")
        if "=> 42" not in recalled:
            fail("Up-arrow did not recall persisted history", recalled)

        cold_checkout_contract(tmp)

    ruby_router = (ROOT / "bin" / "tungsten.rb").read_text(encoding="utf-8")
    if "implementations/ruby/exe/ruby-tungsten" in ruby_router:
        fail("Ruby router still launches the interactive runtime")

    print("core REPL contracts: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
