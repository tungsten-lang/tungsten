"""Assemble the final report without rewriting any historical round."""
import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text())
def pvalue(p):return '0 / 4,000 sampled flips' if p==0 else f'{p:g}'
def main():
    out=ROOT/'out/competitor_jump_round7';final=ROOT/'out/gpt_campaign_final'
    s=read(out/'summary.json');audit=read(final/'requirements_audit.json');assert audit['passed'] and s['audit_passed']
    robust=next(e for e in s['arena']['entries'] if e['trial']=='search_jump_robust_legal' and e['variant']=='tcn');front=robust['main_frontier']
    report=ROOT/'GPT_CHALLENGERS_20260927.md';text=report.read_text()
    phrase='wins the pinned P6 comparison' if front['wins'] else 'does not decisively beat the pinned P6 incumbent'
    diff_unit='guard-scored points' if abs(front['mean_diff'])>1e6 else 'm'
    promotions=', '.join(p['trial']+' ('+p['variant']+')' for p in s['promotions']) or 'none'
    current=f'''## Latest verified status (through round 7)

All seven rounds are complete: **20 selected challengers, 52 arena entries, three motor-control problems**. The campaign produced **{audit['details']['promotion_events']} local promotion events**, with videos preserved for each. The original standing-jump distance, standing-jump robustness, bat-power, and crossover trials were won against their recorded incumbents; later main-arena comparisons remain separate.

Round 7 promotions: **{promotions}**. Its temporal controller passes **{robust['passes']}/{robust['n']}** robustness starts at **{robust['mean_valid']:.8f} m** and {phrase}: paired difference **{front['mean_diff']:+.8f} {diff_unit}**, **p = {pvalue(front['p'])}**. A higher mean without the arena's required significance is not a win.

On round 7's untouched starts, pure is legal at eight seconds on **{s['validation']['pure']['legal_final']}/64**, temporal on **{s['validation']['tcn']['legal_final']}/64**. Their twenty-second checks pass **{s['endurance20']['pure']['legal_final']}/8** and **{s['endurance20']['tcn']['legal_final']}/8**. All failed starts and later mark changes remain in the report. Historical tables retain their original decisions and are not a live main-arena leaderboard.

'''
    text=re.sub(r'## Latest verified status \(through round 6\).*?(?=## Protocol)',lambda _:current,text,flags=re.S)
    assert 'is running; it has no fresh-validation' not in text
    assert '\n## Round 7:' not in text,'Round seven appendix already attached; inspect before rerunning'
    text+='\n\n'+(out/'REPORT.md').read_text()
    text+='\nThe new robustness champion remains a tradeoff: its distance-only entry is 1.349 m versus the earlier 1.363 m champion, and its six-second entry falls to 26/32 versus the retained 31/32 recovery champion. On the same fresh starts, refinement raises temporal mean three-second distance from 1.309375 to 1.334140625 m while reducing eight-second legality from 60/64 to 57/64. Pure reaches 64/64 but with shorter marks. Temporal keeps the measured mark on all 57 surviving starts; pure retreats 1.54 cm on average, at most 8 cm. The representative champion video (seed 3024, 1.341 m) visibly settles into a balanced crouch and stays there through twenty seconds.\n'
    text+=f'''

## Completed campaign: evidence and interpretation

The work used the requested isolated worktree, left inherited SDK and simulation files unchanged, preserved existing trials, and created no commits. One search ran at a time with at most three rollout workers. All initial problems include both the explicit phase-based baseline and the bounded, zero-initialized temporal-convolution residual. Only the twenty-weight neural readout was learned; the convolution filters remained fixed. Follow-up rounds explicitly disclose when those learned weights were frozen.

The separate final audit passes **{len(audit['checks'])} checks**: [requirement audit]({final/'requirements_audit.json'}) and [all 52 arena decisions]({final/'arena_ledger.json'}). It recomputes every recorded verdict, checks all twenty frozen selections, confirms validation preceded each arena entry, verifies shared-file and trial integrity, and fully decodes all {audit['details']['promotion_events']} promoted-champion videos. Previous round audits and unsuccessful candidates are retained.

**Learned residual versus pure search.** Temporal feedback has its clearest benefit in crossovers: 7.52 versus 4.68 on the same 25 arena starts, paired +2.84, with no favorable null sample among 4,000 sign flips. Fresh bias-only and zero-head ablations lose much of that gain. Pure search wins the batting comparison: 14.72056 versus 13.92056 m/s, while the learned time dependence adds little beyond a constant offset. The measured hitch remains. For jumping, temporal wins the original distance trial at 1.363 m and contributes to longer recovery, but explicit landing logic is essential and the strongest later robustness comparisons must be read individually. Round 7 {phrase}. These results do not establish general neural superiority, sustained ball control, arms-only finger technique, or universal landing stability.

Arena decisions use the project's unadjusted exploratory rule, and multiple follow-ups reused its held-out starts. Fresh validation supports the reported finite behavior; it does not turn a borderline arena gain into a confirmed frontier improvement. P6 has a different training history and was never part of the matched-compute family comparison.
'''
    report.write_text(text)
    (out/'PROGRESS.md').write_text('COMPLETE. Training, fresh validation, arena entry, frozen artifacts, full-motion metrics, and round audit finished. Final campaign audit is in ../gpt_campaign_final/requirements_audit.json. Results are integrated into the main report.\n')
    print(json.dumps({'report':str(report),'arena_entries':52,'selected_challengers':20,'checks':len(audit['checks']),'promotions':audit['details']['promotion_events']}))
if __name__=='__main__':main()
