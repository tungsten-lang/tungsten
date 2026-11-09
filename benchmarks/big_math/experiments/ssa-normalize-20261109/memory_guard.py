"""Sample only this command's process tree, with owned-process identity checks.
Codex-assisted, Apache-2.0. macOS RSS is sampled, so peaks can overshoot.
16 GiB estimated headroom reserve plus kernel pressure/swap vetoes; 1 GiB default cap.
"""
import argparse,hashlib,json,os,re,signal,subprocess,sys,time
from pathlib import Path
from memory_policy import read_system,reason as system_reason,POLICY_ID

def snapshot():
    ps=subprocess.run(['ps','-axo','pid=,ppid=,pgid=,rss=,stat=,lstart='],capture_output=True,text=True,check=True)
    rows={}
    for line in ps.stdout.splitlines():
        items=line.split(maxsplit=5)
        if len(items)==6:
            pid,parent,group,rss=map(int,items[:4]);rows[pid]=(parent,group,rss,items[4],items[5])
    return rows

def main(a):
    cmd=a.command[1:]if a.command[:1]==['--']else a.command
    assert cmd and a.limit_gib>0 and a.sample_seconds>=.05
    limit=int(a.limit_gib*2**30);a.report.parent.mkdir(parents=True,exist_ok=True)
    start=time.monotonic();owned={};peak=samples=0;reason=None;signal_errors=[]
    reserve=16*2**30;initial=latest=None;system_samples=0;minimum_headroom=minimum_immediate=None
    system_due=0.;child=None
    try:
        initial=latest=read_system();system_samples=1
        reason=system_reason(initial,reserve_bytes=reserve)
    except Exception as error:reason='system memory telemetry failed: '+str(error)
    if reason is not None:
        report=dict(status='STOPPED',returncode=None,reason=reason,peak_sampled_rss_bytes=0,
                    limit_bytes=limit,system_reserve_bytes=reserve,seconds=time.monotonic()-start,
                    command=cmd,system_initial=initial,system_policy=POLICY_ID,
                    guard_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
        a.report.write_text(json.dumps(report,indent=2)+'\n');print('Memory guard:',json.dumps(report),flush=True)
        raise SystemExit(143)
    minimum_headroom=initial['estimated_headroom_bytes'];minimum_immediate=initial['immediate_bytes']
    child=subprocess.Popen(cmd,start_new_session=True)
    def discover(rows):
        current={pid for pid,identity in owned.items()if pid in rows and rows[pid][4]==identity}
        if child.pid in rows and child.poll()is None and child.pid not in owned:
            current.add(child.pid)
        while True:
            expanded=current|{pid for pid,row in rows.items()if row[0]in current and (pid not in owned or owned[pid]==row[4])}
            if expanded==current:break
            current=expanded
        for pid in current:owned.setdefault(pid,rows[pid][4])
        return current
    def signal_live(sig):
        rows=snapshot();current=discover(rows);live={pid for pid in current if not rows[pid][3].startswith('Z')};done=set()
        for group in sorted({rows[pid][1]for pid in live}):
            members={pid for pid,row in rows.items()if row[1]==group and not row[3].startswith('Z')}
            # A remembered group is never enough: recheck the live leader and every
            # live member immediately before signalling. Otherwise use owned PIDs.
            if group not in live or not members<=live:continue
            try:os.killpg(group,sig);done|=members
            except ProcessLookupError:pass
            except PermissionError as e:signal_errors.append(dict(target='group',id=group,signal=int(sig),error=str(e)))
        for pid in sorted(live-done):
            fresh=snapshot()
            if pid not in fresh or fresh[pid][4]!=owned[pid]or fresh[pid][3].startswith('Z'):continue
            try:os.kill(pid,sig)
            except ProcessLookupError:pass
            except PermissionError as e:signal_errors.append(dict(target='pid',id=pid,signal=int(sig),error=str(e)))
    def terminate():
        signal_live(signal.SIGTERM)
        try:child.wait(timeout=.7)
        except subprocess.TimeoutExpired:pass
        signal_live(signal.SIGKILL)
        deadline=time.monotonic()+1
        while time.monotonic()<deadline:
            rows=snapshot();live=[pid for pid in discover(rows)if not rows[pid][3].startswith('Z')]
            if not live:return []
            time.sleep(.05)
        return live
    try:
        while child.poll()is None:
            rows=snapshot();current=discover(rows)
            rss=sum(rows[pid][2]for pid in current)*1024;peak=max(peak,rss);samples+=1
            if time.monotonic()>=system_due:
                try:
                    latest=read_system();system_samples+=1
                    minimum_headroom=min(minimum_headroom,latest['estimated_headroom_bytes'])
                    minimum_immediate=min(minimum_immediate,latest['immediate_bytes'])
                    reason=system_reason(latest,initial,reserve_bytes=reserve)
                except Exception as error:reason='system memory telemetry failed: '+str(error)
                system_due=time.monotonic()+.5
            expired=a.timeout_seconds>0 and time.monotonic()-start>a.timeout_seconds
            if rss>limit or reason is not None or expired:
                reason='process tree exceeded resident memory limit'if rss>limit else reason if reason is not None else'time bound exceeded'
                survivors=terminate()
                if survivors:reason+='; owned processes survived termination: '+str(survivors)
                break
            time.sleep(a.sample_seconds)
    except BaseException:
        terminate();raise
    try:code=child.wait(timeout=1)
    except subprocess.TimeoutExpired:code=143
    report=dict(status='PASS'if code==0 and reason is None else'STOPPED',returncode=code,reason=reason,peak_sampled_rss_bytes=peak,limit_bytes=limit,hard_data_limit_bytes=None,system_reserve_bytes=reserve,system_policy=POLICY_ID,system_initial=initial,system_final=latest,system_samples=system_samples,system_sample_seconds=.5,minimum_estimated_headroom_bytes=minimum_headroom,minimum_immediate_bytes=minimum_immediate,samples=samples,sample_seconds=a.sample_seconds,seconds=time.monotonic()-start,command=cmd,guard_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),signal_errors=signal_errors,identity_check='PID and ps start time; live group leader and complete member check before group signals')
    a.report.write_text(json.dumps(report,indent=2)+'\n');print('Memory guard:',json.dumps(report),flush=True);raise SystemExit(0 if report['status']=='PASS'else code if code>0 else 143)
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--report',type=Path,required=True);ap.add_argument('--limit-gib',type=float,default=1);ap.add_argument('--sample-seconds',type=float,default=.1);ap.add_argument('--timeout-seconds',type=float,default=0);ap.add_argument('command',nargs=argparse.REMAINDER);main(ap.parse_args())
