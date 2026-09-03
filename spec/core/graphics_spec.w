# Graphics — windowed Metal rendering facade (core/graphics.w).
#
# METAL LANE. The `gfx_*` functions are thin ccalls into runtime/graphics.m and
# every one of them needs a live NSWindow, so this spec covers the CPU-testable
# half: the hardware keyCode constants and the Camera basis/orientation maths.
# Nothing here opens a window or touches the GPU.
#
# Run:
#   bin/tungsten run --interpret spec/core/graphics_spec.w
#   bin/tungsten -o /tmp/graphics_spec spec/core/graphics_spec.w && /tmp/graphics_spec

use core/graphics

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

-> near(a, b)
  d = a - b
  if d < ~0.0
    d = ~0.0 - d
  return d < ~1.0e-12

-> vec3(x, y, z)
  Vec3<f64>.new([x, y, z] ## f64[3])

# ---- hardware keyCode constants (ANSI layout positions) ----
check("KEY_A", KEY_A == 0)
check("KEY_S", KEY_S == 1)
check("KEY_D", KEY_D == 2)
check("KEY_W", KEY_W == 13)
check("KEY_Q", KEY_Q == 12)
check("KEY_E", KEY_E == 14)
check("KEY_SPACE", KEY_SPACE == 49)
check("KEY_ESC", KEY_ESC == 53)
check("KEY_LEFT", KEY_LEFT == 123)
check("KEY_RIGHT", KEY_RIGHT == 124)
check("KEY_DOWN", KEY_DOWN == 125)
check("KEY_UP", KEY_UP == 126)
check("KEY_SHIFT", KEY_SHIFT == 56)
check("WASD are four distinct codes",
      KEY_W != KEY_A && KEY_A != KEY_S && KEY_S != KEY_D && KEY_W != KEY_D)

# ---- Camera construction ----
origin = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0)
check("constructs", type(origin) == "Camera")
check("position is a Vec3", type(origin.pos).include?("Vec3"))
check("yaw accessor", origin.yaw == ~0.0)
check("pitch accessor", origin.pitch == ~0.0)

# ---- basis vectors: yaw 0 / pitch 0 looks down -Z ----
f = origin.forward
check("forward x at rest", near(f.x, ~0.0))
check("forward y at rest", near(f.y, ~0.0))
check("forward z at rest is -1", near(f.z, ~-1.0))
r = origin.right
check("right x at rest is 1", near(r.x, ~1.0))
check("right y is always 0", r.y == ~0.0)
check("right z at rest", near(r.z, ~0.0))
u = origin.up
check("up x at rest", near(u.x, ~0.0))
check("up y at rest is 1", near(u.y, ~1.0))
check("up z at rest", near(u.z, ~0.0))

# A quarter turn of yaw swings forward onto +X and right onto +Z.
quarter = ~1.5707963267948966
turned = Camera.new(vec3(~0.0, ~0.0, ~0.0), quarter, ~0.0)
check("yawed forward is +X", near(turned.forward.x, ~1.0))
check("yawed forward loses -Z", near(turned.forward.z, ~0.0))
check("yawed right is +Z", near(turned.right.z, ~1.0))
check("yawed right loses +X", near(turned.right.x, ~0.0))

# Pitching up tilts forward toward +Y and leaves right horizontal.
pitched = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, quarter)
check("pitched forward is +Y", near(pitched.forward.y, ~1.0))
check("right is independent of pitch", near(pitched.right.x, ~1.0))

# The basis stays unit-length and orthogonal at an arbitrary attitude.
tilted = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.7, ~0.3)
tf = tilted.forward
tr = tilted.right
tu = tilted.up
check("forward is unit length", near(tf.x * tf.x + tf.y * tf.y + tf.z * tf.z, ~1.0))
check("right is unit length", near(tr.x * tr.x + tr.y * tr.y + tr.z * tr.z, ~1.0))
check("up is unit length", near(tu.x * tu.x + tu.y * tu.y + tu.z * tu.z, ~1.0))
check("forward is perpendicular to right", near(tf.x * tr.x + tf.y * tr.y + tf.z * tr.z, ~0.0))
check("up is perpendicular to forward", near(tu.x * tf.x + tu.y * tf.y + tu.z * tf.z, ~0.0))

# ---- orientation: a unit quaternion, identity at rest ----
q = origin.orientation
check("orientation is a Quaternion", type(q).include?("Quaternion"))
check("orientation is normalized", near(q.norm, ~1.0))
check("orientation at rest is the identity rotation", near(q.real, ~1.0))
check("orientation stays normalized when tilted", near(tilted.orientation.norm, ~1.0))

# ---- look: accumulates yaw, clamps pitch to +/- 1.48 rad ----
c = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0)
c.look(~0.5, ~0.25)
check("look accumulates yaw", near(c.yaw, ~0.5))
check("look accumulates pitch", near(c.pitch, ~0.25))
c.look(~0.5, ~0.0)
check("look keeps accumulating yaw", near(c.yaw, ~1.0))
up_clamped = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0)
up_clamped.look(~0.0, ~9.0)
check("pitch clamps looking up", up_clamped.pitch == ~1.48)
down_clamped = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0)
down_clamped.look(~0.0, ~-9.0)
check("pitch clamps looking down", down_clamped.pitch == ~-1.48)
check("yaw is not clamped", near(Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0).yaw, ~0.0))

# ---- move: f along forward, s along right, u along world +Y ----
m = Camera.new(vec3(~1.0, ~2.0, ~3.0), ~0.0, ~0.0)
m.move(~1.0, ~0.0, ~0.0)
check("moving forward walks -Z", near(m.pos.z, ~2.0))
check("moving forward leaves x", near(m.pos.x, ~1.0))
s = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0)
s.move(~0.0, ~2.0, ~0.0)
check("strafing right walks +X", near(s.pos.x, ~2.0))
w = Camera.new(vec3(~0.0, ~0.0, ~0.0), ~0.0, ~0.0)
w.move(~0.0, ~0.0, ~5.0)
check("the up component is world-relative", near(w.pos.y, ~5.0))
check("a zero move is a no-op",
      near(Camera.new(vec3(~4.0, ~5.0, ~6.0), ~1.0, ~0.2).pos.x, ~4.0))

<< "ALL PASS graphics_spec ([passed.load()] checks)"
