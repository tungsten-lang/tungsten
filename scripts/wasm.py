#!/usr/bin/env python3
"""Experimental raw-i64 leaf functions through existing Tungsten LLVM lowering."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from lib.tungsten_ast import read
ROOT=Path(__file__).resolve().parents[1]


def tool(env, names):
    requested=os.environ.get(env)
    if requested: return requested
    for name in names:
        found=shutil.which(name)
        if found:return found
        if Path(name).is_file():return name
    raise ValueError('missing tool; set '+env)


def run(args, env=None):
    p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,timeout=90,env=env)
    if p.returncode:raise ValueError(p.stdout+p.stderr)
    return p.stdout


def build(source, output, exports):
    compiler=ROOT/'bin/tungsten-compiler'
    ast=read(compiler,source)
    definitions=ast['expressions']
    if not definitions or any(n.get('node')!='method_def' or n.get('is_class_method') for n in definitions):
        raise ValueError('v1 source must contain only top-level function definitions')
    names={}
    for node in definitions:
        name=node['name']
        if not re.fullmatch('[a-z][a-z0-9_]*',name) or name in names:
            raise ValueError('v1 requires unique simple function names')
        if not node['params'] or any(p.get('default') is not None or any(p.get(k) for k in ('ivar_assign','keyword','block_param','splat')) for p in node['params']):
            raise ValueError('v1 requires one or more positional i64 parameters')
        names[name]=len(node['params'])
    if not exports:exports=list(names)
    if len(set(exports))!=len(exports) or any(n not in names for n in exports):
        raise ValueError('exports must name distinct source functions')
    clang=tool('TUNGSTEN_WASM_CLANG',['/opt/homebrew/opt/llvm/bin/clang','clang'])
    linker=tool('TUNGSTEN_WASM_LD',['wasm-ld','/opt/homebrew/opt/lld/bin/wasm-ld'])
    output=output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tungsten-wasm-') as temporary:
        work=Path(temporary)
        run([compiler,'compile',source,'--out',work/'native','--emit-ll','--release','--no-lto'],
            {**os.environ,'TUNGSTEN_LL_PATH':str(work/'native.ll')})
        llvm=(work/'native.ll').read_text();mapping=json.loads((work/'native.sidemap').read_text())
        implementations=[];wrappers=[];seen=set();signatures={}
        for name in exports:
            arity=names[name];expected='__w_'+name+'__'+'_'.join(['i64']*arity)
            symbols={row['symbol'] for row in mapping['hashes'].values() for origin in row['originals']
                     if origin['symbol']==expected and origin.get('class') is None}
            if len(symbols)!=1:raise ValueError(name+': requires an explicit all-i64 signature')
            symbol=symbols.pop()
            match=re.search(r'^define internal i64 @'+re.escape(symbol)+r'\(([^\n]*)\)(?: #[0-9]+)? \{\n(.*?)^}',llvm,re.M|re.S)
            if not match:raise ValueError(name+': unsupported LLVM ABI')
            params=match.group(1).split(', ')
            if len(params)!=arity or any(not re.fullmatch(r'i64 %[A-Za-z0-9_.]+',p) for p in params):
                raise ValueError(name+': only raw i64 arguments are supported')
            body=match.group(2)
            if '@' in body:raise ValueError(name+': runtime calls, globals and calls to other functions are outside v1')
            allowed={'alloca','load','store','add','sub','mul','icmp','select','br','ret','phi','and','or','xor','shl','lshr','ashr','zext','sext','trunc'}
            slots=set(re.findall(r'^\s*(%[\w.]+) = alloca i64, align 8$',body,re.M))
            for line in body.splitlines():
                line=line.strip()
                if not line or line.startswith(';') or line.endswith(':'):continue
                instruction=line.split(' = ',1)[-1].split()[0]
                if instruction not in allowed or re.search(r'\b(double|float|i128|asm|volatile|atomic)\b',line):
                    raise ValueError(name+': unsupported instruction '+line)
                if instruction in ('load','store'):
                    pointer=re.search(r'ptr (%[\w.]+)',line)
                    if not pointer or pointer.group(1) not in slots:raise ValueError(name+': only local scalar slots are supported')
                if instruction=='alloca' and not re.fullmatch(r'%[\w.]+ = alloca i64, align 8',line):
                    raise ValueError(name+': dynamic/non-scalar allocation is unsupported')
            if symbol not in seen:
                implementations.append('define internal i64 @'+symbol+'('+match.group(1)+') {\n'+body+'}\n');seen.add(symbol)
            parameters=', '.join('i64 %a'+str(i) for i in range(arity))
            wrappers.append(f'define i64 @{name}({parameters}) {{\n  %result = call i64 @{symbol}({parameters})\n  ret i64 %result\n}}\n')
            signatures[name]={'parameters':['i64']*arity,'result':'i64'}
        module='target triple = "wasm32-unknown-unknown"\n\n'+'\n'.join(implementations+wrappers)
        (work/'module.ll').write_text(module)
        run([clang,'--target=wasm32-unknown-unknown','-O0','-c',work/'module.ll','-o',work/'module.o'])
        run([linker,'--no-entry','--fatal-warnings','--stack-first','--initial-memory=131072','--max-memory=131072',
             *['--export='+name for name in exports],work/'module.o','-o',work/'module.wasm'])
        output.write_bytes((work/'module.wasm').read_bytes())
        output.with_suffix('.ll').write_text(module)
    report={'schema_version':1,'profile':'raw-i64-leaves-v1','source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'wasm_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
            'exports':signatures,'target':'wasm32-unknown-unknown','wasi':False,'runtime_imports':False,
            'clang':run([clang,'--version']).splitlines()[0],'linker':run([linker,'--version']).splitlines()[0]}
    output.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path);parser.add_argument('--out',required=True,type=Path)
    parser.add_argument('--export',dest='exports',action='append',default=[])
    args=parser.parse_args()
    try:
        build(args.source.resolve(),args.out,args.exports)
        print(str(args.out))
    except (OSError,ValueError,subprocess.TimeoutExpired) as error:
        parser.exit(1,'tungsten wasm: '+str(error)+'\n')
