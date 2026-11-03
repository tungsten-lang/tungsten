"""Render a frozen challenger on an exact arena seed; preserve full horizon."""
import argparse,json,os
from pathlib import Path
import arena
from search import jsonable

def main():
    ap=argparse.ArgumentParser();ap.add_argument('trial');ap.add_argument('--controller',required=True);ap.add_argument('--params',required=True);ap.add_argument('--seed',type=int,required=True);ap.add_argument('--out',required=True);ap.add_argument('--seconds',type=float)
    a=ap.parse_args();trial=json.loads(Path(arena.TRIALS).read_text())[a.trial]
    for key,value in trial.get('env',{}).items():os.environ[key]=str(value)
    import importlib
    from bridge import Sim
    from render import Recorder
    task=importlib.import_module('tasks.'+trial['task']).TASK();task.seed=a.seed
    sim=Sim(task,params=arena.read_params(a.params),controller=os.path.abspath(a.controller))
    rec=Recorder(sim,width=800,height=448,fps=30)
    metrics=sim.run(a.seconds or trial.get('seconds'),recorder=rec)
    dest=Path(a.out);dest.parent.mkdir(parents=True,exist_ok=True)
    rec.write_mp4(str(dest)+'.mp4');rec.write_sheet(str(dest)+'_sheet.png',count=16,cols=4,scale=.5)
    Path(str(dest)+'.json').write_text(json.dumps(jsonable({'seed':a.seed,'trial':a.trial,'controller':a.controller,'params':a.params,'metrics':metrics}),indent=2)+'\n')
    rec.renderer.close()
if __name__=='__main__':main()
