# robolab controller for MyoSuite geometry check.

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
use robolab/skills/geocheck

Robolab.serve(->(body, params) GeoCheckSkill.new(body, params))
