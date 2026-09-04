#!/usr/bin/env python3
import json
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/reports/wasm';OUT.mkdir(parents=True,exist_ok=True)

def run(args,success=True):
 p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,timeout=90)
 assert (p.returncode==0)==success,p.stdout+p.stderr
 return p.stdout
run([ROOT/'bin/tungsten','wasm',ROOT/'experiments/wasm/kernels.w','--out',OUT/'kernels.wasm'])
cases=[('polynomial',n) for n in (-2**63,-100,-1,0,1,37,2**40,2**63-1)]
cases += [('sum_to',n) for n in (-1,0,1,2,100,10000)]
source=OUT/'native-check.w'
source.write_text((ROOT/'experiments/wasm/kernels.w').read_text()+'\n'+'\n'.join(f'<< {name}({n})' for name,n in cases)+'\n')
run([ROOT/'bin/tungsten-compiler','compile',source,'--out',OUT/'native-check','--no-lto'])
native=run([OUT/'native-check']).splitlines()
js=OUT/'check.js'
js.write_text('''const fs=require('fs');
const module_ = new WebAssembly.Module(fs.readFileSync(process.argv[2]));
if (WebAssembly.Module.imports(module_).length) throw Error('unexpected runtime imports');
const exports_ = new WebAssembly.Instance(module_).exports;
const cases = '''+json.dumps([[name,str(n)] for name,n in cases])+''';
for (const [name, text] of cases) {
 const n=BigInt(text), got=exports_[name](n);
 const expected=name==='polynomial'?BigInt.asIntN(64,n*n+2n*n+1n):(n<=0n?0n:n*(n-1n)/2n);
 if(got!==expected) throw Error('oracle mismatch: '+name+' '+n);
 console.log(got.toString());
}
''')
wasm=run(['node',js,OUT/'kernels.wasm']).splitlines()
assert native==wasm,(native,wasm)
for name,text in {
 'dynamic':'-> dynamic(x)\n  x.size()\n',
 'effect':'-> effect(x) (i64) i64\n  << x\n  x\n',
 'float':'-> floating(x) (f64) f64\n  x * x\n',
 'top_level':'write_file("/tmp/wasm-must-not-execute", "bad")\n'
}.items():
 fixture=OUT/(name+'.w');fixture.write_text(text)
 target=OUT/(name+'.wasm');target.unlink(missing_ok=True)
 run([ROOT/'bin/tungsten','wasm',fixture,'--out',target],False)
 assert not target.exists()
print('PASS: 14 native/WASM/BigInt-oracle cases including signed overflow; zero imports; dynamic/effect/f64/top-level rejection')
