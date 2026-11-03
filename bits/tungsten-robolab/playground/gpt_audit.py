"""Final provenance and matched-budget audit; no simulator or source mutation."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'out/competitor_20260927'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    baseline=json.loads((OUT/'baseline_files.json').read_text())
    allowed={'playground/arena/trials.json','playground/arena/champions.json','playground/arena/history.jsonl'}
    changed=[p for p,h in baseline.items() if (not (ROOT/p).is_file() or digest(ROOT/p)!=h) and p not in allowed]
    frozen=json.loads((OUT/'frozen_manifest.json').read_text())
    frozen_drift=[p for p,h in frozen.items() if digest(ROOT/p)!=h]
    trials=json.loads((ROOT/'playground/arena/trials.json').read_text());trials.pop('gpt_jump_stable6')
    # The inherited document used this exact json.dump format.
    trial_hash=hashlib.sha256(json.dumps(trials,indent=1).encode()).hexdigest()
    unchanged_trials=trial_hash==baseline['playground/arena/trials.json']
    parity={p.stem:all(json.loads(p.read_text())['parity'].values()) for p in sorted(OUT.glob('*_parity.json'))}
    protocol=json.loads((OUT/'protocol.json').read_text())
    seed_sets=[set(protocol[k]) for k in ['training_seeds','validation_seeds','arena_new_seeds']]
    disjoint=all(not a&b for i,a in enumerate(seed_sets) for b in seed_sets[i+1:])
    budgets={problem:{variant:json.loads((OUT/f'{problem}_{variant}.json').read_text())['used'] for variant in ['pure','tcn']} for problem in ['jump','bat','dribble']}
    budget_ok=all(r['pure']==r['tcn']==protocol['budgets'][p] for p,r in budgets.items())
    failures=[]
    for path in [*OUT.glob('*_validate.json'),*OUT.glob('*_zero_head.json')]:
        failures.extend({'file':path.name,'seed':r['seed'],'error':r['metrics']['error']} for r in json.loads(path.read_text()) if 'error' in r['metrics'])
    report={'inherited_file_count':len(baseline),'unexpected_inherited_file_changes':changed,'frozen_source_or_binary_drift':frozen_drift,'existing_trials_byte_identical_after_removing_addition':unchanged_trials,'zero_head_exact_parity':parity,'disjoint_private_seed_sets':disjoint,'budgets':budgets,'matched_budget_check':budget_ok,'validation_or_ablation_errors':failures}
    integration=json.loads((OUT/'integration.json').read_text())
    report['nonzero_residual_reaches_measured_motion']=len(integration)==6 and all(not r['errors'] and all(v>1e-8 for v in r['max_absolute_difference'].values()) for r in integration)
    report['passed']=report['nonzero_residual_reaches_measured_motion'] and not changed and not frozen_drift and unchanged_trials and len(parity)==6 and all(parity.values()) and disjoint and budget_ok and not failures
    (OUT/'audit.json').write_text(json.dumps(report,indent=2)+'\n')
    paths=[*ROOT.glob('lib/entry/gpt_*.w'),*ROOT.glob('lib/robolab/skills/gpt_*.w'),*ROOT.glob('playground/gpt_*.py'),*ROOT.glob('params/competitor_20260927/*.txt'),*ROOT.glob('bin/challengers/gpt-*'),ROOT/'spec/gpt_residual_spec.w']
    (OUT/'final_manifest.json').write_text(json.dumps({str(p.relative_to(ROOT)):digest(p) for p in sorted(paths)},indent=2)+'\n')
    print(json.dumps(report,indent=2))
    if not report['passed']:raise SystemExit(1)
if __name__=='__main__':main()
