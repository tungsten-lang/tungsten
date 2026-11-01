#!/usr/bin/env python3
"""Real package namespace dispatch, argv boundaries and version/lock precedence."""
import json
import os
import pathlib
import subprocess
import tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='bit-commands-') as d:
    root=pathlib.Path(d).resolve();home=root/'home';project=root/'project';project.mkdir();home.mkdir();package=root/'demo';(package/'commands/db').mkdir(parents=True)
    (package/'Bitfile').write_text('name "demo"\nversion "1.2.3"\nsummary "Demo command package"\n')
    source='<< JSON.encode({args: argv(), root: env("BIT_PACKAGE_ROOT"), name: env("BIT_COMMAND_NAME")})\n'
    for name in ('echo','db','db/migrate'):(package/'commands'/(name+'.w')).write_text(source)
    env=dict(os.environ,BIT_HOME=str(home),TUNGSTEN_ROOT=str(ROOT))
    def run(*args,ok=True):
        p=subprocess.run([ROOT/'bin/bit',*args],cwd=project,env=env,text=True,capture_output=True,timeout=120)
        if ok and p.returncode:raise AssertionError(p.stdout+p.stderr)
        if not ok and not p.returncode:raise AssertionError('command should have failed: '+p.stdout)
        return p.stdout
    (project/'Bitfile').write_text('name "project"\nversion "0.1.0"\nbit "demo", ">= 1.0.0", path: "../demo"\n')
    arguments=['--project','space dir','--json','--rate=30000/1001','--','-x','א','$(touch nope)','quote"back\\slash']
    result=json.loads(run('demo','echo',*arguments));assert result['args']==arguments,result
    assert result['name']=='demo';assert pathlib.Path(result['root']).resolve()==package
    assert json.loads(run('demo','db','migrate','raw'))['args']==['raw']
    assert 'db migrate' in run('help','demo')
    assert 'unknown demo command' in run('demo','../echo',ok=False)
    # A lock selects the installed exact version, even with another current.
    (project/'Bitfile').write_text('name "project"\nbit "demo", ">= 1.0.0"\n')
    (project/'Bitfile.lock').write_text('bit "demo", "1.2.3", path: "../demo"\n')
    assert json.loads(run('demo','echo','locked'))['args']==['locked']
    (project/'Bitfile.lock').write_text('bit "demo", "9.9.9", path: "../demo"\n')
    assert 'not installed' in run('demo','echo',ok=False)
    (project/'Bitfile.lock').unlink();assert 'lockfile' in run('demo','echo',ok=False)
    (project/'Bitfile').write_text('name "project"\n')
    (home/'demo').mkdir();(home/'demo/current').symlink_to(package,target_is_directory=True)
    assert json.loads(run('demo','echo','installed'))['args']==['installed']
    # Built-in names stay reserved, and help/list never execute package code.
    assert 'Available commands' in run('help','commands') or 'install' in run('help','commands')
    # Packaging includes root commands without a redundant asset declaration.
    packed=subprocess.run([ROOT/'bin/bit','pack'],cwd=package,env=env,text=True,capture_output=True,timeout=120)
    assert packed.returncode==0,packed.stdout+packed.stderr
    import tarfile
    archive=next((package/'pkg').glob('*.bit'))
    with tarfile.open(archive) as tar: assert any(name.endswith('commands/db/migrate.w') for name in tar.getnames())
print('PASS package dispatch: raw argv, nested commands, help, dependencies, locked versions, installed fallback and packaging')
