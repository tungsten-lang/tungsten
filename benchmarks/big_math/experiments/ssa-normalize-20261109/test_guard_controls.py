import json,subprocess,sys
from pathlib import Path
P=Path(__file__).resolve().parent
O=Path('/private/tmp/tungsten-ssa-normalize-20261109/guard-controls');O.mkdir(exist_ok=True)
for name,limit,timeout,program,expected in [
 ('rss',.04,8,'import time; x=bytearray(64*2**20); time.sleep(6)','resident memory limit'),
 ('timeout',1,.25,'import time; time.sleep(6)','time bound exceeded')]:
    report=O/(name+'.json')
    result=subprocess.run([sys.executable,'-B',str(P/'memory_guard.py'),'--report',str(report),
                           '--limit-gib',str(limit),'--sample-seconds','.1','--timeout-seconds',str(timeout),
                           '--',sys.executable,'-c',program],capture_output=True,text=True)
    data=json.loads(report.read_text())
    assert result.returncode!=0 and expected in data['reason'],data
    assert not data['signal_errors'],data
    print('PASS_GUARD_CONTROL',name,data['peak_sampled_rss_bytes'],data['reason'],flush=True)
print('PASS_ACTUAL_RSS_AND_TIMEOUT_CONTROLS')
