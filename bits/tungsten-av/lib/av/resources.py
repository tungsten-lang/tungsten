"""Conservative memory/disk budgets shared by doctor, plan and execution."""
import dataclasses
import math
import os
import pathlib
import resource
import shutil
import subprocess
import re
import sys


def memory_available():
    if sys.platform.startswith('linux'):
        try:
            values=dict(line.split(':',1) for line in pathlib.Path('/proc/meminfo').read_text().splitlines())
            return int(values['MemAvailable'].split()[0])*1024
        except (OSError,KeyError,ValueError): pass
    try:
        import ctypes
        libc=ctypes.CDLL(None); count=ctypes.c_size_t(8); result=ctypes.c_uint64()
        if libc.sysctlbyname(b'hw.memsize',ctypes.byref(result),ctypes.byref(count),None,0)==0:
            physical=result.value
            output=subprocess.run(['/usr/bin/vm_stat'],capture_output=True,text=True,timeout=2,check=True).stdout
            page=int(re.search(r'page size of (\d+) bytes',output)[1])
            counts=[int(re.search(r'Pages '+name+r':\s+(\d+)',output)[1]) for name in ('free','inactive','speculative')]
            return min(physical//2,sum(counts)*page)
    except (OSError,AttributeError,subprocess.SubprocessError,TypeError): pass
    return 2*1024**3


def existing_parent(path):
    path=pathlib.Path(path)
    while not path.exists(): path=path.parent
    return path


@dataclasses.dataclass
class Budget:
    settings: dict
    available_bytes: int | None=None
    cpus: int | None=None

    def choose(self,width,height,source_width=None,source_height=None):
        available=self.available_bytes if self.available_bytes is not None else memory_available()
        limit=min(available,int(self.settings.get('memory_mb',available/1024**2*.65)*1024**2))
        pixels=width*height; source=(source_width or width)*(source_height or height)
        # Decoder/encoder buffers, CPU/Metal scratch, plus bridge/runtime overhead.
        per_job=int(16*source+16*pixels+128*1024**2)
        if per_job>limit: raise ValueError(f'memory budget too small: need approximately {math.ceil(per_job/1024**2)} MiB per job')
        requested=int(self.settings.get('jobs',min(self.cpus or os.cpu_count() or 1,8)))
        jobs=max(1,min(requested,limit//per_job,self.cpus or os.cpu_count() or 1))
        decode=min(int(self.settings.get('decode_ahead',6)),max(1,(limit-128*1024**2)//max(4*source,1)//jobs))
        return dict(jobs=jobs,animation_jobs=min(int(self.settings.get('animation_jobs',jobs)),jobs),
                    decode_ahead=decode,segments_ahead=int(self.settings.get('segments_ahead',3)),
                    memory_budget_mb=limit//1024**2,estimated_memory_per_job_mb=math.ceil(per_job/1024**2))

    def disk(self,path,needed):
        free=shutil.disk_usage(existing_parent(path)).free
        reserve=int(self.settings.get('disk_reserve_mb',1024)*1024**2)
        return dict(free_bytes=free,estimated_bytes=int(needed),reserve_bytes=reserve,ok=free>=needed+reserve)


def child_peak_rss():
    value=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return int(value if sys.platform=='darwin' else value*1024)
