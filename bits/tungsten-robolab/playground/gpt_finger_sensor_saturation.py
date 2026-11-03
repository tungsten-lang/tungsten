"""Estimate feature clipping from already-consumed fingered-body traces."""
import hashlib, json
from pathlib import Path

import mujoco
import numpy as np
from tasks.dribble_v3 import TASK

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'out/competitor_dribble_fingers_prototype'
OUTPUT = SOURCE / 'feature_saturation_controlled_window.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def describe(values, threshold):
    values = np.asarray(values)
    return {
        'samples': int(values.size),
        'p95_absolute': float(np.quantile(np.abs(values), .95)),
        'maximum_absolute': float(np.max(np.abs(values))),
        'fraction_clipped': float(np.mean(np.abs(values) > threshold)),
    }


def main():
    task = TASK()
    xml = task.xml(task.builder())
    model = mujoco.MjModel.from_xml_string(xml)
    ball_qadr = int(model.joint('ball').qposadr[0])
    metrics_by_key = {
        (row['label'], int(row['seed'])): row['metrics']
        for row in json.loads((SOURCE / 'rollouts.json').read_text())
    }
    paths = sorted(SOURCE.glob('*_28910[12].npz'))
    rows = []
    for path in paths:
        if path.name.startswith(('zero_pure', 'zero_tcn')):
            continue
        data = np.load(path)
        qtimes, q = data['t'], data['q']
        c = data['measured']
        ctimes = np.linspace(qtimes[0], qtimes[-1], len(c))
        sample_times = np.arange(qtimes[0], qtimes[-1] + 1e-9, .02)
        labels = data['labels']
        releases = np.flatnonzero(np.char.find(labels.astype(str), 'right:let_go') >= 0)
        if not len(releases):
            raise ValueError(f'No initial right-hand release label in {path.name}')
        release_time = float(ctimes[int(releases[0])])
        row_label = path.stem.rsplit('_', 1)[0]
        seed = int(path.stem[-6:])
        controlled_end = release_time + float(metrics_by_key[(row_label, seed)]['controlled_s'])
        in_control = (sample_times >= release_time) & (sample_times <= controlled_end)

        position = q[:, ball_qadr:ball_qadr + 3]
        velocity_est = np.gradient(position, qtimes, axis=0)
        pos50 = np.column_stack([np.interp(sample_times, qtimes, position[:, j]) for j in range(3)])
        vel50 = np.column_stack([np.interp(sample_times, qtimes, velocity_est[:, j]) for j in range(3)])
        sensors = np.column_stack([
            pos50[:, 0] - task.home[0], pos50[:, 1], pos50[:, 2],
            vel50[:, 0] / 4., vel50[:, 1] / 4., vel50[:, 2] / 5.,
        ])
        sensor_names = ['ball_x_relative', 'ball_y', 'ball_z', 'ball_vx_scaled', 'ball_vy_scaled', 'ball_vz_scaled']
        sensor_limits = [1., 1., 1., 1., 1., 1.]
        sensor_report = {name: describe(sensors[:, i], sensor_limits[i]) for i, name in enumerate(sensor_names)}

        rate = np.gradient(c, ctimes, axis=0)
        rate50 = np.column_stack([np.interp(sample_times, ctimes, rate[:, j]) for j in range(c.shape[1])])
        acc50 = np.gradient(rate50, sample_times, axis=0)
        jerk50 = np.gradient(acc50, sample_times, axis=0)
        raw_channels = [2. * np.column_stack([np.interp(sample_times, ctimes, c[:, j]) for j in range(c.shape[1])]) - 1.,
                        rate50 / 5., acc50 / 100., jerk50 / 2000.]
        derivative_names = ['contraction_centered', 'velocity_scaled', 'acceleration_scaled', 'jerk_scaled']
        derivative_limits = [1., 1., 1., 1.]
        muscle_report = {
            name: describe(channel, derivative_limits[i])
            for i, (name, channel) in enumerate(zip(derivative_names, raw_channels))
        }
        groups = np.stack([
            [np.mean(np.clip(channel[:, np.arange(channel.shape[1]) % 4 == group], -1., 1.), axis=1)
             for group in range(4)]
            for channel in raw_channels
        ], axis=2)
        grouped_report = {
            name: describe(groups[i], 1.)
            for i, name in enumerate(derivative_names)
        }
        rows.append({
            'trace': path.name,
            'label': row_label,
            'seed': seed,
            'source_sha256': sha(path),
            'feature_samples': len(sample_times),
            'measured_control_window': {'release_time_s': release_time, 'end_time_s': controlled_end, 'samples': int(in_control.sum())},
            'sensor_inputs_before_clip': {name: describe(sensors[in_control, i], 1.) for i, name in enumerate(sensor_names)},
            'muscle_values_before_individual_clip': {name: describe(channel[in_control], 1.) for name, channel in zip(derivative_names, raw_channels)},
            'group_means_after_individual_clip': {name: describe(groups[:, in_control, i], 1.) for i, name in enumerate(derivative_names)},
            'full_motion_context': {'fraction_sensor_clip': {k: v['fraction_clipped'] for k, v in sensor_report.items()}, 'fraction_muscle_clip': {k: v['fraction_clipped'] for k, v in muscle_report.items()}},
        })

    result = {
        'scope': 'Offline estimate from already-consumed traces only. No new rollout or controller run. Metrics are restricted to the task-reported interval from initial right-hand ball release through control loss, excluding unrelated post-loss wandering. Ball velocity is reconstructed by finite differences from saved 100 Hz q; contractions are differentiated from saved 200 Hz measured values and resampled to the declared 50 Hz feature cadence. Active-side mirroring does not change absolute clip rates. These estimates identify possible information loss; they do not establish a performance cause or justify changing the frozen Round11 inputs.',
        'analysis_script_sha256': sha(__file__),
        'rollout_metrics_sha256': sha(SOURCE / 'rollouts.json'),
        'feature_source_sha256': sha(ROOT / 'lib/robolab/skills/gpt_temporal.w'),
        'sensor_source_sha256': sha(ROOT / 'lib/robolab/skills/gpt_finger_dribble.w'),
        'model_xml_sha256': hashlib.sha256(xml.encode()).hexdigest(),
        'traces': rows,
    }
    with OUTPUT.open('x') as handle:
        json.dump(result, handle, indent=2)
        handle.write('\n')
    print(json.dumps({'output': str(OUTPUT), 'traces': len(rows), 'labels': sorted({r['label'] for r in rows})}, indent=2))


if __name__ == '__main__':
    main()
