"""Conservative macOS launch/run policy; estimates are not physically free RAM.

Only half the bounded file-backed candidate pool earns reclaim credit. Anonymous
inactive and compressed pages earn none. Pressure/swap checks independently veto
that estimate. Userspace pressure constants are 1/2/4 (XNU event_private.h).
"""
import re,subprocess,sys,time
from decimal import Decimal

GIB=2**30
POLICY_ID='macos-filebacked-half-pressure-swap-v1'
PRESSURE_NORMAL=1
MIN_IMMEDIATE=512*2**20
MAX_SWAP_GROWTH=256*2**20
MAX_SWAPOUT_GROWTH=64*2**20

def parse(vm,sysctl):
    def count(label):
        match=re.search(r'^'+re.escape(label)+r':\s*(\d+)\.',vm,re.M)
        if not match:raise ValueError('missing VM counter: '+label)
        return int(match.group(1))
    match=re.search(r'page size of (\d+) bytes',vm)
    if not match:raise ValueError('missing VM page size')
    page=int(match.group(1))
    if page not in (4096,16384):raise ValueError('unexpected VM page size')
    pages={k:count(v) for k,v in {
        'free':'Pages free','speculative':'Pages speculative','purgeable':'Pages purgeable',
        'inactive':'Pages inactive','file_backed':'File-backed pages',
        'compressed':'Pages occupied by compressor','swapouts':'Swapouts'}.items()}
    match=re.search(r'^kern\.memorystatus_vm_pressure_level:\s*(\d+)\s*$',sysctl,re.M)
    if not match:raise ValueError('missing kernel pressure level')
    level=int(match.group(1))
    # Unknown levels fail closed in reason(), rather than being called normal.
    match=re.search(r'^vm\.swapusage:.*?\bused\s*=\s*([\d.]+)([KMGT])',sysctl,re.M)
    if not match:raise ValueError('missing swap usage')
    swap=int(Decimal(match.group(1))*(1024**('KMGT'.index(match.group(2))+1)))
    immediate=page*(pages['free']+pages['speculative']+pages['purgeable'])
    # This is deliberately a discounted heuristic, not an assertion that the
    # inactive/file-backed intersection or every file page is immediately clean.
    candidate=max(0,min(pages['inactive'],pages['file_backed'])
                  -pages['speculative']-pages['purgeable'])*page
    credit=candidate//2
    return dict(policy=POLICY_ID,observed_monotonic=time.monotonic(),page_bytes=page,
                pages=pages,pressure_level=level,immediate_bytes=immediate,
                reclaim_candidate_bytes=candidate,reclaim_credit_bytes=credit,
                estimated_headroom_bytes=immediate+credit,swap_used_bytes=swap,
                swapout_bytes=pages['swapouts']*page,
                compressed_resident_bytes=pages['compressed']*page)

def read_system():
    if sys.platform!='darwin':raise RuntimeError('macOS memory policy requires Darwin')
    vm=subprocess.check_output(['/usr/bin/vm_stat'],text=True,timeout=3)
    ctl=subprocess.check_output(['/usr/sbin/sysctl','kern.memorystatus_vm_pressure_level',
                                 'vm.swapusage'],text=True,timeout=3)
    return parse(vm,ctl)

def reason(now,baseline=None,reserve_bytes=16*GIB):
    if now['pressure_level']!=PRESSURE_NORMAL:
        return 'system memory pressure is not normal: '+str(now['pressure_level'])
    if now['immediate_bytes']<MIN_IMMEDIATE:
        return 'system memory immediate reserve below 512 MiB'
    if now['estimated_headroom_bytes']<reserve_bytes:
        return 'system memory estimated headroom below reserve'
    if baseline is not None:
        if now['swap_used_bytes']-baseline['swap_used_bytes']>=MAX_SWAP_GROWTH:
            return 'system memory swap usage grew by at least 256 MiB'
        if now['swapout_bytes']-baseline['swapout_bytes']>=MAX_SWAPOUT_GROWTH:
            return 'system memory wrote at least 64 MiB of swap'
    return None
