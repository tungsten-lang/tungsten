"""Content-bound release bundles, activated by one atomic current symlink."""
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import shutil
import uuid


def sha256(path):
    h = hashlib.sha256()
    with pathlib.Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    with pathlib.Path(path).open('w') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write('\n'); stream.flush(); os.fsync(stream.fileno())


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def link_atomic(target, path):
    tmp = path.with_name('.' + path.name + '.' + uuid.uuid4().hex)
    try:
        tmp.symlink_to(os.path.relpath(target, path.parent.resolve()))
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


class BundlePublisher:
    def __init__(self, directory, verify, check_cancelled=None):
        self.directory = pathlib.Path(directory).resolve()
        self.verify = verify
        self.check_cancelled = check_cancelled or (lambda: None)

    def publish(self, entries, provenance):
        """entries: {source, destination, role}. verify checks each staged copy.

        Readers requiring several files must resolve current once and read that
        immutable directory. Existing filename aliases follow current.
        """
        if not entries:
            raise ValueError('release requires at least one file')
        entries = [dict(e, source=pathlib.Path(e['source']).absolute(),
                        destination=pathlib.Path(e['destination']).absolute()) for e in entries]
        # Pin a source release once: stage must not mix aliases opened across
        # an upstream current-pointer switch during a multi-file copy.
        snapshots = {}
        for entry in entries:
            source=entry['source']
            entry['destination']=entry['destination'].parent.resolve()/entry['destination'].name
            if source.is_symlink():
                target=pathlib.Path(os.path.normpath(str(source.parent.resolve()/os.readlink(source))))
                pointer=target.parent
                if pointer.name=='current' and pointer.is_symlink() and (pointer/'manifest.json').exists():
                    if pointer not in snapshots:
                        resolved=pointer.resolve()
                        manifest=json.loads((resolved/'manifest.json').read_text())
                        snapshots[pointer]=(resolved,{item['name']:item['sha256'] for item in manifest['files']})
                    resolved,hashes=snapshots[pointer]
                    if target.name not in hashes: raise ValueError('source is absent from its release manifest')
                    entry['source']=resolved/target.name
                    entry['expected_sha256']=hashes[target.name]
                    entry['source_release']=str(resolved)
        destinations = [str(e['destination']) for e in entries]
        if len(set(destinations)) != len(entries):
            raise ValueError('duplicate release destinations')
        self.directory.mkdir(parents=True, exist_ok=True)
        with (self.directory / '.publish.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return self._publish(entries, provenance)

    def _publish(self, entries, provenance):
        directory = self.directory
        current = directory / 'current'
        identity = hashlib.sha256(json.dumps(sorted(str(e['destination']) for e in entries)).encode()).hexdigest()
        if current.is_symlink():
            previous = json.loads((current / 'manifest.json').read_text())
            if previous['mapping'] != identity:
                raise ValueError('release destination set changed; use a new release directory')
        elif current.exists():
            raise ValueError('current must be a symlink')
        release_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:12]
        candidate = directory / ('.candidate-' + release_id)
        candidate.mkdir()
        activated = False
        changed = []
        legacy = directory / ('legacy-' + release_id)
        try:
            files = []
            for i, entry in enumerate(entries):
                self.check_cancelled()
                src = entry['source']
                if not src.is_file() or src.stat().st_size == 0:
                    raise ValueError(f'missing release source: {src}')
                name = f'{i:02d}-{entry["destination"].name}'
                path = candidate / name
                before = sha256(src)
                if entry.get('expected_sha256',before)!=before:
                    raise ValueError('source differs from its release manifest')
                shutil.copyfile(src, path)
                if sha256(path) != before or sha256(src) != before:
                    raise ValueError(f'source changed during copy: {src}')
                with path.open('rb') as stream:
                    os.fsync(stream.fileno())
                files.append(dict(name=name, source=str(src), destination=str(entry['destination']),
                                  role=entry['role'], sha256=before, bytes=path.stat().st_size,
                                  source_release=entry.get('source_release')))
            # All selected outputs exist in the candidate before any checks run.
            for entry, item in zip(entries, files):
                self.check_cancelled()
                reports = candidate / (item['name'] + '.checks')
                reports.mkdir()
                result = self.verify(candidate / item['name'], entry, reports)
                if not result or not result.get('ok'):
                    raise ValueError(f'verification failed: {entry["source"]}')
                item['verification'] = result
            for item in files:
                if sha256(candidate / item['name']) != item['sha256']:
                    raise ValueError('candidate changed during verification')
            report_hashes = {str(p.relative_to(candidate)): sha256(p) for p in sorted(candidate.rglob('*'))
                             if p.is_file() and p.parent != candidate}
            write_json(candidate / 'manifest.json', dict(schema=1, release=release_id, mapping=identity,
                       provenance=provenance, files=files, reports=report_hashes))
            for path in candidate.rglob('*'):
                if path.is_file():
                    with path.open('rb') as stream: os.fsync(stream.fileno())
            for path in sorted(candidate.rglob('*'),reverse=True):
                if path.is_dir(): sync_dir(path)
            sync_dir(candidate)
            final = directory / release_id
            candidate.rename(final)
            sync_dir(directory)
            # Snapshot pre-bundle publications so first installation keeps their bytes.
            if not current.is_symlink():
                legacy.mkdir()
                old_files = []
                for entry, item in zip(entries, files):
                    dest = entry['destination']
                    if dest.exists():
                        shutil.copyfile(dest, legacy / item['name'])
                        old_files.append(dict(name=item['name'], sha256=sha256(legacy / item['name'])))
                        with (legacy/item['name']).open('rb') as stream: os.fsync(stream.fileno())
                write_json(legacy / 'manifest.json', dict(schema=1, legacy=True, mapping=identity, files=old_files))
                sync_dir(legacy)
                link_atomic(legacy, current)
            for entry, item in zip(entries, files):
                dest = entry['destination']
                target = current / item['name']
                if dest.is_symlink() and os.readlink(dest) == os.path.relpath(target,dest.parent.resolve()):
                    continue
                dest.parent.mkdir(parents=True, exist_ok=True)
                # Remember the exact previous directory entry for rollback on setup failure.
                backup = dest.with_name('.' + dest.name + '.before-' + release_id)
                existed = os.path.lexists(dest)
                if dest.is_symlink(): backup.symlink_to(os.readlink(dest))
                elif existed:
                    try: os.link(dest, backup)
                    except OSError: shutil.copyfile(dest, backup)
                changed.append((dest, backup, existed))
                link_atomic(target, dest)
                sync_dir(dest.parent)
            self.check_cancelled()
            link_atomic(final, current)
            activated = True
            sync_dir(directory)
            return final
        finally:
            if not activated:
                for dest, backup, existed in reversed(changed):
                    if existed: os.replace(backup, dest)
                    else: dest.unlink(missing_ok=True)
            else:
                for _, backup, existed in changed:
                    if existed: backup.unlink(missing_ok=True)
            if candidate.exists(): shutil.rmtree(candidate)
