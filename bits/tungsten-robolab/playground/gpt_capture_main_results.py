"""Preserve read-only main-arena cross-evaluations, separate from our campaign."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent;MAIN=Path('/Users/erik/tungsten/bits/tungsten-robolab');OUT=ROOT/'out/competitor_jump_round4'
def main():
    p=MAIN/'playground/arena/history.jsonl';raw=p.read_bytes();hist=[json.loads(l) for l in raw.decode().splitlines() if l.strip()]
    rows=[r for r in hist if 'Codex' in r.get('note','') and r.get('result')!='seeded']
    chains=[]
    for row in rows:
        assert 'vs_champion' in row
        name=row['trial'];prior=[r for r in hist[:hist.index(row)] if r['trial']==name and r.get('result') in ['promoted','seeded']]
        champion=prior[-1] if prior else None
        chains.append({'entry':row,'previous_champion':champion})
    evidence={'source':str(p),'sha256_at_capture':hashlib.sha256(raw).hexdigest(),'entries':chains,'provenance_correction':'The Codex batter was trained on four continuous randomized pitches, not on the 18-pitch arena grid. Incorrect later main-arena attribution is preserved as source evidence and has been reported to the other agent.','scope':'Historical cross-evaluations by the main agent. They do not update this worktree board or claim to be the current main board.'}
    (OUT/'main_cross_evaluations.json').write_text(json.dumps(evidence,indent=2)+'\n')
    lines=['# Main-arena cross-evaluation of the independent challengers','', 'These are the main agent’s recorded arena decisions, separately from this worktree’s original campaign. The main board has continued to change after these entries.','', '| Trial | Challenger result | Paired difference in arena orientation | p | Decision |','|---|---:|---:|---:|---|']
    for e in chains:
        r=e['entry'];v=r['vs_champion'];lines.append(f"| {r['trial']} | {r['summary']['mean']:.8g} | {v['mean_diff']:+.8g} | {v['p']:.5f} | {r['result']} |")
    lines+=['','Guard failures score -1e9; guard-scored differences are not physical distances or speeds. For lower-is-better trials, the paired comparison reverses the raw metric direction. A sampled p of zero means 0/4,000 sampled sign flips, not an exact zero.','', 'Training-provenance correction: the independent pure batter used four fixed continuous randomized training pitches and 24 different validation pitches. It did not train on the arena’s 18-pitch grid. Main’s later note is inaccurate on that point; the saved source retains it for audit.','', 'The main-arena technique checks confirm the limitations: bat flow 7.3251 loses to 2.0475, and dribble trunk share 0.7345 loses to 0.1823. The bat-power controller subsequently wins the main fresh-pitch power trial at 14.78875 m/s, but fails its clean-motion variant.','']
    (OUT/'MAIN_CROSS_EVALUATION.md').write_text('\n'.join(lines));print('Captured',len(chains),'cross-evaluations with incumbent history')
if __name__=='__main__':main()
