# Python simulation environments (on-demand)

The recorded arena numbers were produced with these top-level simulator packages (originally recorded on 29 Sep 2026).
MuJoCo differs between the two simulators on purpose: MyoSuite 2.12.2 requires `numpy<2` and `mujoco==3.6.0`.

No frozen `requirements/*.txt` lockfiles are committed in-tree so transitive third-party Python packages are resolved fresh on demand in local virtual environments.

| environment | top-level packages | used for |
| --- | --- | --- |
| `.venv` | `mujoco==3.14.0`, `numpy>=2.0` | every robolab body: running, jumping, batting, dribbling, hurdles |
| `.venv-myo` | `myosuite==2.12.2`, `mujoco==3.6.0`, `numpy==1.26.4` | the MyoChallenge tasks: table tennis, soccer, chase tag, relocate, baoding, die, bimanual |
| `.venv-pose` | `mediapipe`, `jax`, `matplotlib`, `opencv-python` | the Bolt keyframe extraction (`playground/refs/bolt/keyframes.py`) and a few plots; not needed for the arena |

```sh
cd bits/tungsten-robolab
uv venv --python 3.12 .venv      && uv pip install --python .venv/bin/python      "mujoco==3.14.0" "numpy>=2.0"
uv venv --python 3.12 .venv-myo  && uv pip install --python .venv-myo/bin/python  "myosuite==2.12.2" "mujoco==3.6.0" "numpy==1.26.4"
uv venv --python 3.12 .venv-pose && uv pip install --python .venv-pose/bin/python mediapipe jax matplotlib opencv-python   # optional
```
