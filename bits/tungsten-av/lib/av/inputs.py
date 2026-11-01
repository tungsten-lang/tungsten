"""Content-addressed, immutable input snapshots and actual toolchain identity."""
import contextlib
import fcntl
import hashlib
import json
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import time
import uuid


def sha256(path):
    h=hashlib.sha256()
    with pathlib.Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): h.update(block)
    return h.hexdigest()


def stamp(path):
    value=pathlib.Path(path).stat()
    return value.st_dev,value.st_ino,value.st_size,value.st_mtime_ns,value.st_ctime_ns


def sync_directory(path):
    fd=os.open(path,os.O_RDONLY)
    try: os.fsync(fd)
    finally: os.close(fd)


def write_json(path,value):
    path=pathlib.Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_name('.'+path.name+'.'+uuid.uuid4().hex)
    try:
        with temp.open('w') as stream:
            json.dump(value,stream,indent=2,allow_nan=False); stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
        os.replace(temp,path); sync_directory(path.parent)
    finally: temp.unlink(missing_ok=True)


def implementation(toolchain, package):
    toolchain,package=pathlib.Path(toolchain),pathlib.Path(package)
    inputs=[toolchain/'bin/tungsten',toolchain/'bin/tungsten-compiler']
    for tree in ('runtime','core','compiler','apps/studio'):
        inputs.extend(p for p in (toolchain/tree).rglob('*') if p.suffix in ('.w','.c','.m','.h','.py'))
    inputs.extend(p for p in package.rglob('*') if p.suffix in ('.w','.py'))
    digest=hashlib.sha256(); files={}
    for path in sorted(set(inputs)):
        label=str(path.relative_to(toolchain)) if path.is_relative_to(toolchain) else 'package/'+str(path.relative_to(package))
        value=sha256(path); files[label]=value
        digest.update(label.encode()+b'\0'+value.encode()+b'\0')
    return dict(sha256=digest.hexdigest(),files=files,platform=sys.platform)


class Snapshots:
    def __init__(self,directory,runner,*,reserve_bytes=0):
        self.directory=pathlib.Path(directory); self.runner=runner; self.reserve_bytes=reserve_bytes

    def seal(self,source):
        source=pathlib.Path(source).resolve()
        self.runner.check_cancelled()
        before=stamp(source); digest=sha256(source)
        if before!=stamp(source): raise ValueError('input changed while hashing: '+str(source))
        self.directory.mkdir(parents=True,exist_ok=True)
        destination=self.directory/(digest+source.suffix.lower())
        with (self.directory/(digest+'.lock')).open('a') as lock:
            started=time.monotonic()
            while True:
                try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB); break
                except BlockingIOError:
                    self.runner.check_cancelled()
                    if self.runner.timeout and time.monotonic()-started>self.runner.timeout: raise TimeoutError('input snapshot lock timed out')
                    time.sleep(.05)
            if destination.exists():
                if sha256(destination)!=digest: raise ValueError('sealed input is corrupt: '+str(destination))
                if before!=stamp(source): raise ValueError('input changed while opening snapshot')
                return dict(source=str(source),path=str(destination),sha256=digest,bytes=before[2],method='reused')
            if shutil.disk_usage(self.directory).free < before[2]+self.reserve_bytes:
                raise ValueError('insufficient free disk for an input snapshot and configured reserve')
            temporary=self.directory/('.'+digest+'.'+uuid.uuid4().hex)
            method='copy'
            try:
                if sys.platform=='darwin':
                    try:
                        self.runner.run(['cp','-c',source,temporary],capture=True); method='clone'
                    except subprocess.CalledProcessError: temporary.unlink(missing_ok=True)
                if not temporary.exists(): shutil.copyfile(source,temporary)
                self.runner.check_cancelled()
                if stamp(source)!=before or sha256(temporary)!=digest: raise ValueError('input changed during snapshot: '+str(source))
                with temporary.open('rb') as stream: os.fsync(stream.fileno())
                temporary.chmod(stat.S_IRUSR|stat.S_IRGRP|stat.S_IROTH)
                os.replace(temporary,destination); sync_directory(self.directory)
            finally: temporary.unlink(missing_ok=True)
        return dict(source=str(source),path=str(destination),sha256=digest,bytes=before[2],method=method)

    def tree(self,paths,asset_root,destination):
        """Freeze explicitly declared assets/data and local Tungsten use graphs."""
        asset_root=pathlib.Path(asset_root).resolve(); destination=pathlib.Path(destination)
        pending=[pathlib.Path(p).resolve() for p in paths]; files={}; directories=set()
        while pending:
            path=pending.pop()
            self.runner.check_cancelled()
            if path.is_dir():
                if path in directories: continue
                directories.add(path)
                pending.extend(p for p in path.iterdir() if p.name not in ('.git','.av','__pycache__'))
                continue
            if path in files: continue
            if not path.is_file(): raise ValueError('declared input is missing: '+str(path))
            files[path]=self.seal(path)
            if path.suffix=='.w':
                import re
                for match in re.finditer(r'^\s*use\s+(?:"([^"]+)"|([\w./-]+))',pathlib.Path(files[path]['path']).read_text(),re.M):
                    target=path.parent/(match[1] or match[2])
                    if target.suffix!='.w': target=pathlib.Path(str(target)+'.w')
                    if target.is_file(): pending.append(target.resolve())
        identity=hashlib.sha256(json.dumps({str(p):item['sha256'] for p,item in files.items()},sort_keys=True).encode()).hexdigest()
        destination=destination/identity
        records=[]; mapping={}
        for path in sorted(files):
            relative=path.relative_to(asset_root) if path.is_relative_to(asset_root) else pathlib.Path('.external')/hashlib.sha256(str(path.parent).encode()).hexdigest()[:16]/path.name
            mapping[str(path)]=str(destination/relative)
        for path,sealed in sorted(files.items()):
            target=pathlib.Path(mapping[str(path)]); target.parent.mkdir(parents=True,exist_ok=True)
            data=None; expected=sealed['sha256']
            if path.suffix=='.w':
                import re
                text=pathlib.Path(sealed['path']).read_text()
                def replace(match):
                    name=match[2] or match[3]; dependency=path.parent/name
                    if dependency.suffix!='.w': dependency=pathlib.Path(str(dependency)+'.w')
                    replacement=mapping.get(str(dependency.resolve()))
                    return match[1]+'"'+replacement[:-2]+'"' if replacement else match[0]
                changed=re.sub(r'(^\s*use\s+)(?:"([^"]+)"|([\w./-]+))',replace,text,flags=re.M)
                if changed!=text: data=changed.encode(); expected=hashlib.sha256(data).hexdigest()
            if target.exists():
                if sha256(target)!=expected: raise ValueError('frozen input tree is corrupt: '+str(target))
            else:
                temporary=target.with_name('.'+target.name+'.'+uuid.uuid4().hex)
                try:
                    if data is not None: temporary.write_bytes(data)
                    else:
                        try: os.link(sealed['path'],temporary)
                        except OSError: shutil.copyfile(sealed['path'],temporary)
                    temporary.chmod(0o444)
                    with temporary.open('rb') as stream: os.fsync(stream.fileno())
                    temporary.replace(target); sync_directory(target.parent)
                finally: temporary.unlink(missing_ok=True)
            records.append(dict(sealed,frozen=str(target),frozen_sha256=expected))
        return records,mapping
