#!/usr/bin/env python3
"""Public `bit install` lockfile, checksum, and versioned-prefix contracts."""

from __future__ import annotations

import hashlib
import http.server
import io
import os
import subprocess
import sys
import tarfile
import tempfile
import threading
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TUNGSTEN = ROOT / "bin" / "tungsten"
TEST_COMPILER = ROOT / "build" / "cache" / "bit-install" / "tungsten-compiler"


def fail(message: str, result: subprocess.CompletedProcess[str] | None = None) -> None:
    if result is not None:
        if result.stdout:
            print(result.stdout, file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
    raise SystemExit(message)


def run(
    args: list[str],
    cwd: Path,
    home: Path,
    *,
    expected: int = 0,
) -> subprocess.CompletedProcess[str]:
    home.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.pop("BIT_HOME", None)
    env.update(
        {
            "HOME": str(home),
            "TUNGSTEN_HOME": str(home / ".tungsten"),
            "TUNGSTEN_ROOT": str(ROOT),
            "NO_COLOR": "1",
            "HOMEBREW_CACHE": str(ROOT / "build" / "cache" / "bit-install" / "homebrew"),
        }
    )
    result = subprocess.run(
        [str(TUNGSTEN), *args],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=45,
    )
    if result.returncode != expected:
        fail(
            f"{' '.join(args)} exited {result.returncode}, expected {expected}",
            result,
        )
    return result


def build_test_compiler() -> None:
    """Build the checked-out loader without replacing the developer compiler."""
    TEST_COMPILER.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({"BIT_HOME": str(ROOT / "bits"), "TUNGSTEN_ROOT": str(ROOT)})
    result = subprocess.run(
        [
            str(ROOT / "bin" / "tungsten-compiler"),
            "compile",
            str(ROOT / "compiler" / "tungsten.w"),
            "--out",
            str(TEST_COMPILER),
            "--no-lto",
        ],
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=90,
    )
    if result.returncode != 0:
        fail("could not build current compiler for loader contract", result)


def run_current_compiler(
    args: list[str], cwd: Path, home: Path
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "TUNGSTEN_HOME": str(home / ".tungsten"),
            "BIT_HOME": str(home / ".tungsten" / "bits"),
            "TUNGSTEN_ROOT": str(ROOT),
            "NO_COLOR": "1",
        }
    )
    result = subprocess.run(
        [str(TEST_COMPILER), *args],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=45,
    )
    if result.returncode != 0:
        fail(
            f"current compiler {' '.join(args)} exited {result.returncode}", result
        )
    return result


def write_package(root: Path, name: str, version: str, entry: str, answer: int) -> Path:
    package = root / name
    (package / "lib").mkdir(parents=True)
    (package / "Bitfile").write_text(
        f'name "{name}"\nversion "{version}"\nsummary "fixture {name}"\n',
        encoding="utf-8",
    )
    (package / "lib" / f"{entry}.w").write_text(
        f"-> {entry}_answer\n  {answer}\n", encoding="utf-8"
    )
    return package


def write_archive(path: Path, name: str, version: str, entry: str, answer: int) -> None:
    files = {
        "Bitfile": f'name "{name}"\nversion "{version}"\n',
        f"lib/{entry}.w": f"-> {entry}_answer\n  {answer}\n",
    }
    with tarfile.open(path, "w") as archive:
        for member_name, content in files.items():
            data = content.encode()
            info = tarfile.TarInfo(member_name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def write_traversal_archive(path: Path) -> None:
    with tarfile.open(path, "w") as archive:
        for member_name, content in {
            "Bitfile": 'name "tungsten-escape"\nversion "1.0.0"\n',
            "../escaped.txt": "must not escape\n",
        }.items():
            data = content.encode()
            info = tarfile.TarInfo(member_name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))


def write_link_archive(path: Path) -> None:
    with tarfile.open(path, "w") as archive:
        data = b'name "tungsten-link"\nversion "1.0.0"\n'
        info = tarfile.TarInfo("Bitfile")
        info.size = len(data)
        info.mode = 0o644
        archive.addfile(info, io.BytesIO(data))

        link = tarfile.TarInfo("outside")
        link.type = tarfile.SYMTYPE
        link.linkname = "../outside"
        archive.addfile(link)


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        pass


def serve(directory: Path) -> tuple[http.server.ThreadingHTTPServer, threading.Thread]:
    def handler(*args: object, **kwargs: object) -> QuietHandler:
        return QuietHandler(*args, directory=str(directory), **kwargs)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread


def assert_versioned(root: Path, name: str, version: str) -> Path:
    installed = root / name / version
    if not (installed / "Bitfile").is_file():
        fail(f"missing versioned install {installed}")
    current = root / name / "current"
    if not current.is_symlink() or os.readlink(current) != version:
        fail(f"missing current symlink for {name} {version}")
    return installed


def main() -> int:
    build_test_compiler()
    with tempfile.TemporaryDirectory(prefix="tungsten-bit-install-") as raw_tmp:
        tmp = Path(raw_tmp)
        registry = tmp / "registry"
        write_package(registry, "tungsten-alpha", "1.2.3", "alpha", 40)
        write_package(registry, "tungsten-beta", "3.0.1", "beta", 2)

        project = tmp / "project"
        project.mkdir()
        (project / "Bitfile").write_text(
            f'source "{registry}"\n'
            'bit "tungsten-alpha", "~> 1.2"\n'
            'bit "tungsten-beta", "3.0.1"\n',
            encoding="utf-8",
        )
        (project / "main.w").write_text(
            "use alpha\nuse beta\n<< alpha_answer() + beta_answer()\n",
            encoding="utf-8",
        )
        home = tmp / "home"
        result = run(["bit", "install"], project, home)
        default_root = home / ".tungsten" / "bits"
        assert_versioned(default_root, "tungsten-alpha", "1.2.3")
        assert_versioned(default_root, "tungsten-beta", "3.0.1")
        if f"into {default_root}" not in result.stdout:
            fail("install did not report the default BIT_HOME", result)

        lock = (project / "Bitfile.lock").read_text(encoding="utf-8")
        for expected in (
            'bit "tungsten-alpha", "1.2.3"',
            'bit "tungsten-beta", "3.0.1"',
        ):
            if expected not in lock:
                fail(f"lockfile missed {expected!r}")

        run_result = run_current_compiler(["run", "main.w"], project, home)
        if run_result.stdout.strip() != "42":
            fail("loader did not select locked versioned bits", run_result)
        run_current_compiler(["check", "main.w"], project, home)

        env_result = run(["bit", "env"], project, home)
        if f"bit_home {default_root}" not in env_result.stdout:
            fail("bit env reported the wrong default BIT_HOME", env_result)

        custom_root = tmp / "custom-bits"
        run(["bit", "install", "--dir", str(custom_root)], project, home)
        assert_versioned(custom_root, "tungsten-alpha", "1.2.3")

        system_root = tmp / "system-prefix" / "bits"
        run(
            ["bit", "install", "--system", "--prefix", str(system_root)],
            project,
            home,
        )
        assert_versioned(system_root, "tungsten-beta", "3.0.1")

        nested = tmp / "manifest" / "nested"
        nested.mkdir(parents=True)
        (nested / "Bitfile").write_text(
            f'source "{registry}"\nbit "tungsten-alpha", "1.2.3"\n',
            encoding="utf-8",
        )
        run(
            ["bit", "install", "--bitfile", str(nested / "Bitfile")],
            tmp,
            home,
        )
        if not (nested / "Bitfile.lock").is_file() or (tmp / "Bitfile.lock").exists():
            fail("--bitfile did not place its lockfile beside the manifest")

        deploy = tmp / "deploy"
        deploy.mkdir()
        (deploy / "Bitfile").write_text(
            f'source "{registry}"\nbit "tungsten-alpha", "1.2.3"\n',
            encoding="utf-8",
        )
        deploy_result = run(["bit", "install", "--deploy"], deploy, home, expected=1)
        if "--deploy requires" not in deploy_result.stdout:
            fail("deploy mode accepted a missing lockfile", deploy_result)

        web = tmp / "web"
        web.mkdir()
        archive = web / "tungsten-remote-2.0.0.bit"
        write_archive(archive, "tungsten-remote", "2.0.0", "remote", 99)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        traversal = web / "tungsten-escape-1.0.0.bit"
        write_traversal_archive(traversal)
        traversal_digest = hashlib.sha256(traversal.read_bytes()).hexdigest()
        link_archive = web / "tungsten-link-1.0.0.bit"
        write_link_archive(link_archive)
        link_digest = hashlib.sha256(link_archive.read_bytes()).hexdigest()

        server, thread = serve(web)
        port = server.server_address[1]
        try:
            remote_project = tmp / "remote-project"
            remote_project.mkdir()
            (remote_project / "Bitfile").write_text(
                'bit "tungsten-remote", "2.0.0"\n', encoding="utf-8"
            )
            (remote_project / "Bitfile.lock").write_text(
                'bit "tungsten-remote", "2.0.0", source: "remote", '
                f'path: "http://127.0.0.1:{port}/{archive.name}", sha256: "{digest}"\n',
                encoding="utf-8",
            )
            remote_home = tmp / "remote-home"
            run(["bit", "install", "--no-lock"], remote_project, remote_home)
            remote_root = remote_home / ".tungsten" / "bits"
            remote_install = assert_versioned(remote_root, "tungsten-remote", "2.0.0")
            if (remote_install / ".bit-sha256").read_text().strip() != digest:
                fail("verified remote install did not retain its checksum identity")

            bad_project = tmp / "bad-checksum"
            bad_project.mkdir()
            (bad_project / "Bitfile").write_text(
                'bit "tungsten-remote", "2.0.0"\n', encoding="utf-8"
            )
            (bad_project / "Bitfile.lock").write_text(
                'bit "tungsten-remote", "2.0.0", source: "remote", '
                f'path: "http://127.0.0.1:{port}/{archive.name}", sha256: "{"0" * 64}"\n',
                encoding="utf-8",
            )
            run(["bit", "install", "--no-lock"], bad_project, tmp / "bad-home", expected=1)
            if (tmp / "bad-home" / ".tungsten" / "bits" / "tungsten-remote" / "2.0.0").exists():
                fail("checksum failure left a partial install")

            escape_project = tmp / "escape-project"
            escape_project.mkdir()
            (escape_project / "Bitfile").write_text(
                'bit "tungsten-escape", "1.0.0"\n', encoding="utf-8"
            )
            (escape_project / "Bitfile.lock").write_text(
                'bit "tungsten-escape", "1.0.0", source: "remote", '
                f'path: "http://127.0.0.1:{port}/{traversal.name}", sha256: "{traversal_digest}"\n',
                encoding="utf-8",
            )
            escape_home = tmp / "escape-home"
            run(["bit", "install", "--no-lock"], escape_project, escape_home, expected=1)
            if (escape_home / ".tungsten" / "bits" / "tungsten-escape" / "escaped.txt").exists():
                fail("unsafe archive member escaped its version directory")

            link_project = tmp / "link-project"
            link_project.mkdir()
            (link_project / "Bitfile").write_text(
                'bit "tungsten-link", "1.0.0"\n', encoding="utf-8"
            )
            (link_project / "Bitfile.lock").write_text(
                'bit "tungsten-link", "1.0.0", source: "remote", '
                f'path: "http://127.0.0.1:{port}/{link_archive.name}", sha256: "{link_digest}"\n',
                encoding="utf-8",
            )
            run(
                ["bit", "install", "--no-lock"],
                link_project,
                tmp / "link-home",
                expected=1,
            )
            if (
                tmp
                / "link-home"
                / ".tungsten"
                / "bits"
                / "tungsten-link"
                / "1.0.0"
            ).exists():
                fail("archive link member left a partial install")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        # A verified installed archive is reusable from the lock without a
        # registry query or archive download.
        run(["bit", "install", "--no-lock"], remote_project, remote_home)

        missing_sha = tmp / "missing-sha"
        missing_sha.mkdir()
        (missing_sha / "Bitfile").write_text(
            'bit "tungsten-nohash", "1.0.0"\n', encoding="utf-8"
        )
        (missing_sha / "Bitfile.lock").write_text(
            'bit "tungsten-nohash", "1.0.0", source: "remote", '
            'path: "https://example.invalid/tungsten-nohash.bit"\n',
            encoding="utf-8",
        )
        nohash = run(["bit", "install", "--no-lock"], missing_sha, tmp / "nohash-home", expected=1)
        if "missing sha256" not in nohash.stdout:
            fail("remote install without a checksum was not rejected", nohash)

    print("bit install contracts: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
