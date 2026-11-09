#!/usr/bin/env python3
"""Serial guarded SSA experiment; wait for reserve before every workload."""
from pathlib import Path
import argparse,hashlib,json,os,re,runpy,shlex,subprocess,sys,time
from memory_policy import read_system,reason as system_reason
P=Path(__file__).resolve().parent
ROOT=P.parents[3]
GUARD=P/'memory_guard.py'
OUT=Path('/private/tmp/tungsten-ssa-normalize-20261109')
SIZES='8192,12288,16384,16385,24576,32768,32769,65536,65537,131072'

def write_status(**data):
    OUT.mkdir(exist_ok=True)
    data['updated_epoch']=time.time()
    temp=OUT/'STATUS.tmp';temp.write_text(json.dumps(data,indent=2)+'\n')
    temp.replace(OUT/'STATUS.json')

def wait_reserve(stage):
    good=0;last_log=0
    while good<3:
        try:
            state=read_system();free=state['estimated_headroom_bytes']
            veto=system_reason(state,reserve_bytes=18*2**30)
        except Exception as error:
            state={};free=0;veto='system memory telemetry failed: '+str(error)
        good=good+1 if veto is None else 0
        write_status(state='waiting_for_reserve',stage=stage,
                     available_bytes=free,launch_reserve_bytes=18*2**30,
                     guard_reserve_bytes=16*2**30,stable_samples=good,
                     memory=state,veto=veto)
        if time.monotonic()-last_log>=60 or good==3:
            print(f'RESERVE stage={stage} estimated_gib={free/2**30:.2f} stable={good}/3 veto={veto}',flush=True)
            last_log=time.monotonic()
        if good<3:time.sleep(2)

def guarded(stage,command,env=None):
    previous=[int(f.name[len(stage)+1:-len('-guard.json')])
              for f in OUT.glob(stage+'-*-guard.json')
              if f.name[len(stage)+1:-len('-guard.json')].isdigit()]
    attempt=max(previous,default=0)
    while True:
        attempt+=1;wait_reserve(stage)
        stem=f'{stage}-{attempt}';report=OUT/(stem+'-guard.json')
        log=OUT/(stem+'.log')
        argv=[sys.executable,'-B',str(GUARD),'--report',str(report),
              '--limit-gib','1','--sample-seconds','.1','--timeout-seconds','600','--',*command]
        write_status(state='running',stage=stage,attempt=attempt,command=command,log=str(log))
        print('RUN',stage,'attempt',attempt,flush=True)
        with log.open('w') as f:
            result=subprocess.run(argv,cwd=ROOT,env=env,stdout=f,stderr=subprocess.STDOUT)
        receipt=json.loads(report.read_text())
        print('FINISH',stage,receipt['status'],receipt['reason'],flush=True)
        if result.returncode==0:return log
        if str(receipt.get('reason','')).startswith('system memory ') and 'telemetry failed' not in str(receipt.get('reason','')):continue
        write_status(state='failed',stage=stage,attempt=attempt,guard=receipt)
        raise SystemExit(result.returncode or 1)

def profile():
    return json.loads((OUT/'PROFILE.json').read_text())

def build_check(fused):
    meta=profile();cc=meta['cc'];flags=shlex.split(meta['flags'])
    def pkg_flags(option):
        flags=[]
        for package in ['oniguruma','gmp']:
            result=subprocess.run(['pkg-config',option,package],text=True,capture_output=True)
            if result.returncode and package=='gmp':raise RuntimeError(result.stderr)
            if result.returncode==0:flags.extend(shlex.split(result.stdout))
        return flags
    cflags=pkg_flags('--cflags');libs=pkg_flags('--libs')
    runtime=ROOT/'runtime'
    companions=['event_kqueue.c','terminal_input.c','tls_stub.c','aks.c','metal.m','graphics.m','hid_bridge.m']
    frameworks=['Metal','Foundation','AppKit','QuartzCore','CoreGraphics','IOKit','CoreFoundation','Accelerate']
    command=[cc,*flags,*cflags,'-DHAVE_GMP',f'-DBN_SSA_NORMALIZE_RECOMPOSE_FUSED={fused}',
             str(P/'check.c'),*[str(runtime/n) for n in companions],*libs,
             *[x for fw in frameworks for x in ['-framework',fw]],'-o',str(OUT/f'check-{fused}')]
    print(shlex.join(command),flush=True)
    subprocess.run(command,cwd=ROOT,check=True)

def run_benchmark(rounds=9,target_ms=110,sizes=SIZES,output='BENCHMARK.json'):
    meta=profile();os.environ['CC']=meta['cc']
    ns=runpy.run_path(str(ROOT/'benchmarks/big_math/run_variant_ab.py'))
    main=ns['main'];main.__globals__['DEFAULT_CFLAGS']=meta['flags']
    sys.argv=['benchmarks/big_math/run_variant_ab.py','--label','ssa-normalize-recompose-fusion',
              '--operations','mul,sqr','--sizes',sizes,
              '--baseline-extra-flags=-DBN_SSA_NORMALIZE_RECOMPOSE_FUSED=0',
              '--candidate-extra-flags=-DBN_SSA_NORMALIZE_RECOMPOSE_FUSED=1',
              '--rounds',str(rounds),'--target-ms',str(target_ms),'--output',str(OUT/output)]
    raise SystemExit(main())

def main():
    OUT.mkdir(exist_ok=True)
    ap=argparse.ArgumentParser();ap.add_argument('--build-check',type=int);ap.add_argument('--benchmark',action='store_true');ap.add_argument('--replicate',action='store_true');ap.add_argument('--rounds',type=int,default=9);ap.add_argument('--target-ms',type=float,default=110);ap.add_argument('--sizes',default=SIZES);ap.add_argument('--output',default='BENCHMARK.json')
    args=ap.parse_args()
    if args.build_check is not None:build_check(args.build_check);return
    if args.benchmark:run_benchmark(args.rounds,args.target_ms,args.sizes,args.output);return
    source=json.loads((P/'SOURCE.json').read_text())
    assert hashlib.sha256(GUARD.read_bytes()).hexdigest()==source['guard_sha256']
    assert hashlib.sha256((P/'memory_policy.py').read_bytes()).hexdigest()==source['memory_policy.py_sha256']
    expected=json.loads((P/'SOURCE.json').read_text())['experiment_runtime_sha256']
    assert hashlib.sha256((ROOT/'runtime/runtime.c').read_bytes()).hexdigest()==expected,'runtime changed'
    if args.replicate:
        guarded('benchmark-replication',[sys.executable,'-B',str(P/'experiment.py'),'--benchmark',
                 '--rounds','15','--target-ms','200',
                 '--sizes','8192,16384,24576,32768,32769,65536,131072',
                 '--output','BENCHMARK-REPLICATION.json'])
        data=json.loads((OUT/'BENCHMARK-REPLICATION.json').read_text())
        write_status(state='completed',replication_summary=data['summary'],benchmark=str(OUT/'BENCHMARK-REPLICATION.json'))
        print('COMPLETED_REPLICATION',json.dumps(data['summary']),flush=True)
        return
    log=guarded('release-profile',[str(ROOT/'benchmarks/big_math/run.sh'),'--profile'])
    line=next(x for x in log.read_text().splitlines() if '|' in x and not x.startswith('Memory guard:'))
    cc,flags=line.split('|',1)
    assert '-O3' in flags and '-flto' in flags and '-O0' not in flags
    (OUT/'PROFILE.json').write_text(json.dumps({'cc':cc,'flags':flags},indent=2)+'\n')
    for fused in [0,1]:
        guarded(f'build-check-{fused}',[sys.executable,'-B',str(P/'experiment.py'),'--build-check',str(fused)])
        guarded(f'correctness-{fused}',[str(OUT/f'check-{fused}')])
    guarded('benchmark',[sys.executable,'-B',str(P/'experiment.py'),'--benchmark'])
    bench=json.loads((OUT/'BENCHMARK.json').read_text())
    write_status(state='completed',benchmark_summary=bench['summary'],benchmark=str(OUT/'BENCHMARK.json'))
    print('COMPLETED',json.dumps(bench['summary']),flush=True)

if __name__=='__main__':main()
