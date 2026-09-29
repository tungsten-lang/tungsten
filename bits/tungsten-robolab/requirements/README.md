# Pinned Python environments

The recorded arena numbers were produced with these versions (frozen on 29 Sep 2026 with `uv pip freeze`).
MuJoCo differs between the two simulators on purpose: MyoSuite 2.12.2 needs numpy below 2 and MuJoCo 3.6.

| file | environment | used for |
| --- | --- | --- |
| `venv.txt` | `.venv` (MuJoCo 3.14.0, numpy 2.5.3) | every robolab body: running, jumping, batting, dribbling, hurdles |
| `venv-myo.txt` | `.venv-myo` (MyoSuite 2.12.2, MuJoCo 3.6.0, numpy 1.26.4) | the MyoChallenge tasks: table tennis, soccer, chase tag, relocate, baoding, die, bimanual |
| `venv-pose.txt` | `.venv-pose` (MediaPipe, JAX, matplotlib, OpenCV) | the Bolt keyframe extraction (`playground/refs/bolt/keyframes.py`) and a few plots; not needed for the arena |

```sh
cd bits/tungsten-robolab
uv venv --python 3.12 .venv      && uv pip install --python .venv/bin/python      -r requirements/venv.txt
uv venv --python 3.12 .venv-myo  && uv pip install --python .venv-myo/bin/python  -r requirements/venv-myo.txt
uv venv --python 3.12 .venv-pose && uv pip install --python .venv-pose/bin/python -r requirements/venv-pose.txt   # optional
```
