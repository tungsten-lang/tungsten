#!/usr/bin/env python3
"""Record, independently check, and open the first Tungsten Notes experiment."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import uuid
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--science-python',type=Path,help='optional interpreter with h5py, NumPy and PyArrow')
parser.add_argument('--no-open',action='store_true')
args=parser.parse_args()
run_id=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:8]
OUT=ROOT/'build/cache/notes-demo/runs'/run_id
OUT.mkdir(parents=True)

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def command(argv,name,env=None):
    start=time.perf_counter()
    p=subprocess.run([str(a) for a in argv],cwd=ROOT,text=True,capture_output=True,timeout=120,env=env)
    (OUT/(name+'.stdout')).write_text(p.stdout);(OUT/(name+'.stderr')).write_text(p.stderr)
    record={'argv':[str(a) for a in argv],'exit_status':p.returncode,'seconds':time.perf_counter()-start}
    manifest['commands'].append(record)
    if p.returncode:raise RuntimeError(name+' failed: '+p.stdout+p.stderr)
    return p.stdout

manifest={'schema_version':1,'run_id':run_id,'title':'Tungsten Notes numerical sample',
 'started_at':datetime.now(timezone.utc).isoformat(),'status':'running','commands':[],
 'source_files':{},'host':{'platform':platform.platform(),'machine':platform.machine()},
 'seed':None,'randomness':'none','math':'raw i64 polynomial; finite sampled domain [-10,10]',
 'compiler_sha256':sha(ROOT/'bin/tungsten-compiler'),
 'git_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
 'git_status':subprocess.check_output(['git','status','--porcelain'],cwd=ROOT,text=True),
 'provenance_scope':'entry/key sources, git state, tool/binary and output hashes; not a complete archived dependency closure',
 'verification':{'status':'not_run','scope':'21 specific polynomial samples; no general theorem claim'}}
for path in ['examples/notes/experiment.w','experiments/wasm/kernels.w','core/notes.w','core/numeric/mat3.w',
             'core/io/interop.w','runtime/science_interop.py','scripts/wasm.py','scripts/run-notes-demo.py']:
 manifest['source_files'][path]=sha(ROOT/path)
status=0
try:
    env=dict(os.environ);env.pop('TUNGSTEN_SCIENCE_PYTHON',None)
    if args.science_python:
        env['TUNGSTEN_SCIENCE_PYTHON']=str(args.science_python.absolute())
        manifest['optional_python']=str(args.science_python.absolute())
        manifest['optional_versions']=json.loads(command([args.science_python,'-c',
          'import json,numpy,h5py,pyarrow;print(json.dumps({"numpy":numpy.__version__,"h5py":h5py.__version__,"pyarrow":pyarrow.__version__}))'],'versions'))
    command([ROOT/'bin/tungsten-compiler','compile',ROOT/'examples/notes/experiment.w','--out',OUT/'experiment','--release','--no-lto'],'compile')
    command([OUT/'experiment',OUT],'native',env)
    command([ROOT/'bin/tungsten','wasm',ROOT/'experiments/wasm/kernels.w','--export','polynomial','--out',OUT/'polynomial.wasm'],'wasm-build')
    js=OUT/'wasm-check.js'
    js.write_text('''const fs=require('fs');const m=new WebAssembly.Module(fs.readFileSync(process.argv[2]));
if(WebAssembly.Module.imports(m).length)throw Error('unexpected imports');
const e=new WebAssembly.Instance(m).exports;const rows=[];
for(let x=-10n;x<=10n;x++)rows.push([x.toString(),e.polynomial(x).toString()]);
console.log(JSON.stringify(rows));
''')
    wasm=json.loads(command(['node',js,OUT/'polynomial.wasm'],'wasm-run'))
    document=json.loads((OUT/'producer.tnotes').read_text())
    native=document['blocks'][1]['rows']
    expected=[[str(x),str((x+1)**2)] for x in range(-10,11)]
    if native!=expected or wasm!=expected:raise RuntimeError('native/WASM/reference sample mismatch')
    if args.science_python:
        checker=OUT/'check-formats.py'
        checker.write_text('''import sys,h5py,numpy as np,pyarrow.parquet as pq,pyarrow.ipc as ipc
from pathlib import Path
p=Path(sys.argv[1]); xs=list(range(-10,11));ys=[(x+1)**2 for x in xs]
with h5py.File(p/'samples.h5','r') as f: np.testing.assert_array_equal(f['samples'][:],np.array(list(zip(xs,ys))))
assert pq.read_table(p/'samples.parquet').to_pydict()=={'x':xs,'y':ys}
with ipc.open_file(p/'samples.arrow') as f: assert f.read_all().to_pydict()=={'x':xs,'y':ys}
print('Independent HDF5/Parquet/Arrow checks passed')
''')
        command([args.science_python,checker,OUT],'format-check')
    evidence={'schema_version':1,'verifier':'notes-sample-v1','verifier_sha256':sha(__file__),
              'scope':'21 explicit integer samples x=-10..10', 'status':'passed','rows':expected,
              'native_binary_sha256':sha(OUT/'experiment'),'wasm_sha256':sha(OUT/'polynomial.wasm'),
              'producer_document_sha256':sha(OUT/'producer.tnotes')}
    (OUT/'verification.json').write_text(json.dumps(evidence,indent=2)+'\n')
    document['blocks'].append({'kind':'certificate','claim':'All 21 sampled outputs agree with the integer reference and WebAssembly.',
      'scope':'x = -10 through 10; evidence SHA-256 '+sha(OUT/'verification.json'),'level':'finite_checked',
      'verification':{'status':'passed','verifier':'notes-sample-v1'},'assumptions':[]})
    document['blocks'].append({'kind':'text','text':'Run '+run_id+'\nProvenance and replay evidence are in the adjacent manifest.json and verification.json.'})
    (OUT/'experiment.tnotes').write_text(json.dumps(document,ensure_ascii=False,indent=2)+'\n')
    command([ROOT/'bin/tungsten','notes','--validate',OUT/'experiment.tnotes'],'notes-validate')
    manifest['verification']={'status':'passed','level':'finite_checked','scope':evidence['scope'],'evidence_sha256':sha(OUT/'verification.json')}
    manifest['status']='succeeded'
except Exception as error:
    status=1;manifest['status']='failed';manifest['error']=str(error)
finally:
    manifest['ended_at']=datetime.now(timezone.utc).isoformat()
    manifest['artifacts']=[{'path':p.name,'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(OUT.iterdir()) if p.is_file() and p.name!='manifest.json']
    temporary=OUT/'manifest.json.tmp';temporary.write_text(json.dumps(manifest,indent=2)+'\n');temporary.replace(OUT/'manifest.json')
print(str(OUT/'manifest.json'))
if status:
    print(manifest['error'],file=sys.stderr)
else:
    print(str(OUT/'experiment.tnotes'))
    if not args.no_open:
        subprocess.run([str(ROOT/'bin/tungsten'),'notes',str(OUT/'experiment.tnotes')],cwd=ROOT,check=True)
raise SystemExit(status)
