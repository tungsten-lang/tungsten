# robolab controller for the basketball dribble skill, v3 (arms-only, elbow-driven, V crossovers, fingered hands).

use robolab/easing
use robolab/body
use robolab/contraction
use robolab/sensors
use robolab/latch
use robolab/chunk
use robolab/reflex
use robolab/controller
use robolab/link
use robolab/skill
use robolab/skills/dribble_v3

use robolab/skills/gpt_temporal
use robolab/skills/gpt_finger_dribble

Robolab.serve(->(body, params) GptFingerDribbleSkill.new(body, params))
