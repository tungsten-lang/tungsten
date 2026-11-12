#!/usr/bin/env python3
"""Fingerprint a git clone's .git directory so a test session can prove it changed nothing.

usage: clone_fingerprint.py CLONE [CLONE ...]

Prints one JSON object per clone: the number of files under .git/objects, the newest mtime (ns)
under .git/objects, `git count-objects -v`, the promisor settings, and a SHA-256 over the sorted
(relative path, size, mtime_ns) triples of EVERY file under .git. Run it before and after a
session (with GIT_NO_LAZY_FETCH=1 exported): equal output means no fetch, no new object, no
touched ref, index or config.
"""
import hashlib
import json
import os
import subprocess
import sys


def fingerprint(clone):
    git_dir = os.path.join(clone, '.git')
    entries, objects, newest = [], 0, 0
    for root, _, names in os.walk(git_dir):
        for name in names:
            path = os.path.join(root, name)
            stat = os.lstat(path)
            entries.append((os.path.relpath(path, git_dir), stat.st_size, stat.st_mtime_ns))
            if os.path.relpath(path, git_dir).startswith('objects' + os.sep):
                objects += 1
                newest = max(newest, stat.st_mtime_ns)
    entries.sort()
    env = dict(os.environ, GIT_NO_LAZY_FETCH='1')

    def git(*args):
        done = subprocess.run(['git', '-C', clone, *args], capture_output=True, text=True, env=env)
        return done.stdout.strip()

    return dict(clone=clone, object_files=objects, newest_object_mtime_ns=newest,
                git_files=len(entries),
                sha256=hashlib.sha256(json.dumps(entries).encode()).hexdigest(),
                count_objects=git('count-objects', '-v').replace('\n', '; '),
                promisor=git('config', 'remote.origin.promisor'),
                filter=git('config', 'remote.origin.partialclonefilter'))


if __name__ == '__main__':
    for path in sys.argv[1:]:
        print(json.dumps(fingerprint(path)))
