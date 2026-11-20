"""Assemble the complementary start-time cases for job 8 and run the official CakePB CNF checker."""
import argparse,hashlib,os,subprocess,tempfile
from pathlib import Path
ap=argparse.ArgumentParser()
ap.add_argument('--cake',type=Path,required=True)
ap.add_argument('--directory',type=Path,default=Path('.'))
ap.add_argument('--translator',type=Path)
ap.add_argument('--scope',choices=('original','branch','both'),default='both')
a=ap.parse_args();directory=a.directory.resolve();original=directory/'input.cnf'
if not original.exists():original=directory.parent/'main-proof/input.cnf'
raw=original.read_bytes();lines=raw.splitlines()
assert hashlib.sha256(raw).hexdigest()=='6d6a406144bf3d3e20efa43e79395612596ac413efba1fac5b59f190c43cff79'
root=[4167,4171,4175,4199,2,29,58,4184,4187]
cases=[('third7-third8-late',-185),('third7-third8-early-resume',185)]
def clean(units):
 return f'p cnf 18420 {83276+len(units)}\n'.encode()+raw.split(b'\n',1)[1].rstrip()+b'\n'+b''.join(f'{v} 0\n'.encode() for v in units)
def proof(scope,tmp,trans):
 extra=root if scope=='branch' else []
 cnf=original if not extra else tmp/'first7.cnf'
 if extra:cnf.write_bytes(clean(extra))
 last=83276+len(extra);ends=[]
 with subprocess.Popen([a.cake.resolve(),cnf,'/dev/stdin'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,env=os.environ|{'CML_HEAP_SIZE':'1500','CML_STACK_SIZE':'128'}) as cake:
  f=cake.stdin;f.write(f'pseudo-Boolean proof version 3.0\nf {last};\n'.encode())
  for name,literal in cases:
   child=(directory/(name+'.cnf')).read_bytes()
   u=[int(row.split()[0]) for row in child.splitlines()[83277:]]
   assert set(u)==set(root+[literal]) and child==clean(u)
   refs=tmp/'refs';refs.write_text(' '.join(str(83277+extra.index(z)) if z in extra else '0' for z in u))
   f.flush()
   with subprocess.Popen(['zstd','-qdc',directory/(name+'.lpr.zst')],stdout=subprocess.PIPE) as zin:
    k=subprocess.run([trans,refs,str(last),*[str(v) for v in u if v not in extra]],stdin=zin.stdout,stdout=f,stderr=subprocess.PIPE)
    zin.stdout.close()
    if k.returncode or zin.wait():raise RuntimeError((name,k.stderr))
    last=int(k.stderr);ends.append(last)
  terms=' '.join('1 ~x'+str(z) for z in root) if not extra else ''
  refs=' '.join(map(str,ends))
  hint='~ ' if not extra else ''
  f.write(f'rup {terms} >= 1 : {hint}{refs};\noutput NONE;\n'.encode())
  f.write((f'conclusion UNSAT : {last+1};\n' if extra else 'conclusion NONE;\n').encode())
  f.write(b'end pseudo-Boolean proof;\n');f.close()
  result=cake.stdout.read().decode().strip()
  expected='s VERIFIED UNSAT' if extra else 's VERIFIED NO CONCLUSION'
  if cake.wait() or result!=expected:raise RuntimeError((scope,result))
  print(scope,result,flush=True)
with tempfile.TemporaryDirectory() as td:
 tmp=Path(td);trans=a.translator.resolve() if a.translator else tmp/'lift'
 if not a.translator:subprocess.run([os.environ.get('CXX','c++'),'-std=c++17','-O2',directory/'stapleguard.cpp','-o',trans],check=True)
 for scope in (('original','branch') if a.scope=='both' else [a.scope]):proof(scope,tmp,trans)
