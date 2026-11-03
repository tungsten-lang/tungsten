"""Append whole-motion observations, limitations and verified champion media."""
import json,statistics
from collections import Counter
from pathlib import Path
from gpt_summarize import ROOT,OUT

def avg(rows,key):return statistics.mean(r[key] for r in rows)
def data(problem,variant,kind):
    return [r['metrics'] for r in json.loads((OUT/f'{problem}_{variant}_validate.json').read_text()) if r['kind']==kind]
def main():
    motion=json.loads((OUT/'bat_measured_motion.json').read_text())
    lines=['## Failure modes and whole-motion inspection','', '**Jump.** The temporal candidate loses both existing jump-distance trials. The new six-second trial records partial recovery, with only 9/32 legal starts. Fresh success is 5/24 for both temporal and bias-only residuals, but just one successful seed overlaps: temporal feedback changes which starts recover without demonstrating a higher recovery rate. Twelve-second diagnostics cover eight fresh starts, so they establish finite examples rather than robust sustained balance. The temporal candidate also increases mean peak landing force and loading rate despite the training penalty.','', '**Bat.** The arena improvement is in contact speed. The original whole-sequence `hitch_full` metric is computed from commanded contractions; it is not a measured-joint smoothness certificate. Fresh means are:', '', '| Controller | Command-based hitch_full (lower better) |','|---|---:|']
    for variant,kind in [('pure','baseline'),('pure','candidate'),('tcn','candidate'),('tcn','bias_only')]:
        lines.append(f'| {variant}_{kind} | {avg(data("bat",variant,kind),"hitch_full"):.4f} |')
    lines += ['', 'Measured joint traces cover the full 0–7.799 s rollout on fresh seed 271001. During the explicitly marked leg-lift-to-finish interval, the longest quiet spans (RMS angular speed below 0.1 rad/s, approximately 10 ms sampling) are:', '', '| Controller | Arms quiet ms | Trunk quiet ms | Front hip quiet ms during lift | Front knee quiet ms during lift | Plant-to-swing ms |','|---|---:|---:|---:|---:|---:|']
    for r in motion:
        q=[r['groups'][k]['quiet_ms_measured'] for k in ['arms','trunk','front_hip','front_knee']]
        lines.append(f"| {r['controller']} | {' | '.join(f'{v:.1f}' for v in q)} | {r['plant_to_swing_ms']:.1f} |")
    lines += ['', 'The diagnostic JSON also records the longest quiet intervals, total joint travel and peak measured speed across the entire visible rollout, including the initial setup and final reset. These threshold measurements are descriptive and do not establish perceptual smoothness. The unchanged quiet spans and full video prevent a claim that either batter challenger fixed the hitch.', '', '**Crossover.** All full 15-second rollouts are retained, including motion after loss of control. Fresh-seed failure observations:', '', '| Controller | Mean controlled seconds | Mean successful crossovers | Mean ball/body contacts | Runs with recorded ball loss | Mean trunk share of upper-body activation |','|---|---:|---:|---:|---:|---:|']
    failures={}
    for variant,kind in [('pure','baseline'),('pure','candidate'),('tcn','candidate'),('tcn','bias_only')]:
        rows=data('dribble',variant,kind);loss=Counter(str(r.get('lost')) for r in rows);failures[variant+'_'+kind]=dict(loss)
        lost=sum(bool(r.get('lost')) for r in rows)
        lines.append(f'| {variant}_{kind} | {avg(rows,"controlled_s"):.2f} | {avg(rows,"x_ok"):.3f} | {avg(rows,"body_hits"):.3f} | {lost}/{len(rows)} | {100*avg(rows,"trunk_share_upper"):.1f}% |')
    (OUT/'dribble_failure_modes.json').write_text(json.dumps(failures,indent=2)+'\n')
    lines += ['', 'The correction itself uses only arm joints, but the backbone retains its trunk pump. The body retains paddle hands; this campaign does not provide articulated-finger technique or an arms-only solution. A higher crossover count must not be read as continuous control for the entire 15 seconds.', '', '## Promoted champions and videos','', 'Promotions below were made only by `arena.py eval --promote` in this isolated worktree. Their frozen binary and parameter files are checked byte-for-byte against the selected challengers. The original checkout\'s board is unchanged. Videos use declared arena seeds and show the full trial; the jump is extended to twelve seconds.','']
    for r in json.loads((OUT/'promotions.json').read_text()):
        lines.append(f"- **{r['trial']} — {r['variant']}**, seed {r['seed']}: [video]({r['video']}); [contact sheet]({r['sheet']}); [frozen parameters]({ROOT/r['champion']['frozen_params']}).")
        if r.get('failure_video'):lines.append(f"  Failure example, seed {r['failure_seed']}: [full video]({r['failure_video']}).")
    lines += ['', '## Conclusion','', 'The temporal residual is most convincing for crossovers: it beats pure search by 2.84 completed crossovers in the arena, and its fresh-seed score falls from 7.708 to 5.042 when temporal features are removed and to 3.792 when the entire readout is removed. Pure search is better for batting by 0.80 m/s in the arena; the temporal batter performs almost identically with bias only. Jump residuals enable some six-second recovery, but constant offsets match their fresh success count, and neither challenger beats the existing distance trials. These results support bounded temporal feedback for the crossover task and retain explicit keyframes as the effective backbone. They do not establish a general advantage for learned residuals.', '', 'The comparison covers one optimizer seed per challenger and these task/seed distributions. Only the zero-initialized readout is trained over fixed convolution filters; this is not an end-to-end TCN training study. All arena verdicts, including losses, are above. No shared SDK changes or commits were made.','']
    p=ROOT/'GPT_CHALLENGERS_20260927.md';s=p.read_text();marker='## Failure modes and whole-motion inspection';a=s.find(marker)
    if a>=0:s=s[:a]
    p.write_text(s.rstrip()+'\n\n'+'\n'.join(lines))
if __name__=='__main__':main()
