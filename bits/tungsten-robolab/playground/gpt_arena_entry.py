"""Run the unmodified arena CLI, additionally preserving its per-seed rows.
Usage: gpt_arena_entry.py --artifact NAME.json eval TRIAL [arena arguments]
The existing evaluate, score_rollouts, compare, and promotion code remain the judge.
"""
import json,sys
from pathlib import Path
import arena
if __name__=='__main__':
    pos=sys.argv.index('--artifact')
    dest=Path(sys.argv[pos+1]);del sys.argv[pos:pos+2]
    evaluate=arena.evaluate
    def capture(trial,params,controller,task_name,workers):
        rows,scores=evaluate(trial,params,controller,task_name,workers)
        dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_text(json.dumps({'trial':trial,'params':params,'controller':controller,'task':task_name,'rows':rows,'scores':scores},indent=2)+'\n')
        return rows,scores
    arena.evaluate=capture
    arena.main()
