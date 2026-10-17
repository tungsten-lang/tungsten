# View3D and Scene3D (core/scene3d.w): camera geometry, projection, culling, depth order, shading, colours.
#
# Run:
#   bin/tungsten run --interpret spec/core/scene3d_spec.w
#   bin/tungsten -o /tmp/scene3d_spec spec/core/scene3d_spec.w && /tmp/scene3d_spec

use scene3d

-> s3_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

-> s3_near(a, b)
  (a - b).abs < ~0.000001

-> s3_near_pt(p, q)
  s3_near(p[0], q[0]) && s3_near(p[1], q[1])

# ---- the camera frame is orthonormal and right-handed, with forward = -eye ----
v = View3D.new(~0.7, ~0.4, ~0.0, ~1.0, ~0.0, ~0.0)
s3_check("eye is a unit vector", s3_near(View3D.dot(v.eye, v.eye), ~1.0))
s3_check("right and up are unit vectors", s3_near(View3D.dot(v.right, v.right), ~1.0) && s3_near(View3D.dot(v.up, v.up), ~1.0))
s3_check("right, up and eye are orthogonal",
         s3_near(View3D.dot(v.right, v.up), ~0.0) && s3_near(View3D.dot(v.right, v.eye), ~0.0) && s3_near(View3D.dot(v.up, v.eye), ~0.0))
c = View3D.cross(v.right, v.up)
s3_check("right × up = eye (right-handed, looking along -eye)", s3_near(c[0], v.eye[0]) && s3_near(c[1], v.eye[1]) && s3_near(c[2], v.eye[2]))
s3_check("world z projects upward for a level camera", View3D.dot(v.up, [~0.0, ~0.0, ~1.0]) > ~0.0)

# ---- an eye on the +x axis sees +y to the right and +z up ----
side = View3D.new(~0.0, ~0.0, ~0.0, ~100.0, ~500.0, ~400.0)
s3_check("+y appears to the right", s3_near_pt(side.project([~0.0, ~1.0, ~0.0]), [~600.0, ~400.0]))
s3_check("+z appears up (smaller screen y)", s3_near_pt(side.project([~0.0, ~0.0, ~1.0]), [~500.0, ~300.0]))
s3_check("depth grows toward the eye", side.depth([~2.0, ~0.0, ~0.0]) > side.depth([~-2.0, ~0.0, ~0.0]))
s3_check("roll turns the picture counter-clockwise",
         s3_near_pt(View3D.new(~0.0, ~0.0, ~1.5707963267948966, ~100.0, ~500.0, ~400.0).project([~0.0, ~1.0, ~0.0]), [~500.0, ~300.0]))

# ---- the isometric view: the body diagonal collapses to a point, the axes are 120° apart ----
iso = View3D.isometric(~1.0, ~0.0, ~0.0)
s3_check("the diagonal (1, 1, 1) projects to the centre", s3_near_pt(iso.project([~1.0, ~1.0, ~1.0]), [~0.0, ~0.0]))
ex = iso.project([~1.0, ~0.0, ~0.0])
ey = iso.project([~0.0, ~1.0, ~0.0])
ez = iso.project([~0.0, ~0.0, ~1.0])
s3_check("each axis projects to length √(2/3)", s3_near(ex[0] * ex[0] + ex[1] * ex[1], ~2.0 / ~3.0) &&
         s3_near(ey[0] * ey[0] + ey[1] * ey[1], ~2.0 / ~3.0) && s3_near(ez[0] * ez[0] + ez[1] * ez[1], ~2.0 / ~3.0))
s3_check("projected axes meet at 120°", s3_near(ex[0] * ey[0] + ex[1] * ey[1], ~-1.0 / ~3.0) &&
         s3_near(ey[0] * ez[0] + ey[1] * ez[1], ~-1.0 / ~3.0))
s3_check("isometric z is straight up", s3_near(ez[0], ~0.0) && ez[1] < ~0.0)
# rolled by 150°, x lies along screen +x and y at 120°: the Eisenstein lattice 1, ω
rolled = View3D.isometric(~1.0, ~0.0, ~0.0, ~2.6179938779914944)
px = rolled.project([~1.0, ~0.0, ~0.0])
py = rolled.project([~0.0, ~1.0, ~0.0])
s3_check("rolled isometric: x → (√(2/3), 0)", s3_near(px[1], ~0.0) && px[0] > ~0.0)
s3_check("rolled isometric: y → 120° (screen y down)", s3_near(py[0], ~-0.40824829046386296) && s3_near(py[1], ~-0.7071067811865476))

# ---- perspective magnifies what is near ----
per = View3D.new(~0.0, ~0.0, ~0.0, ~100.0, ~0.0, ~0.0, ~10.0)
s3_check("orthographic magnification is 1", s3_near(side.magnification([~3.0, ~0.0, ~0.0]), ~1.0))
s3_check("perspective magnification is larger nearer the eye",
         per.magnification([~2.0, ~0.0, ~0.0]) > ~1.0 && per.magnification([~-2.0, ~0.0, ~0.0]) < ~1.0)
s3_check("perspective at the target is unchanged", s3_near_pt(per.project([~0.0, ~1.0, ~0.0]), [~100.0, ~0.0]))

# ---- camera interpolation ----
a = View3D.new(~0.0, ~0.0, ~0.0, ~10.0, ~0.0, ~0.0)
b = View3D.new(~1.0, ~0.5, ~0.2, ~30.0, ~100.0, ~50.0)
m = View3D.between(a, b, ~0.5)
s3_check("between interpolates angles, scale and centre", s3_near(m.azimuth, ~0.5) && s3_near(m.elevation, ~0.25) &&
         s3_near(m.roll, ~0.1) && s3_near(m.scale, ~20.0) && s3_near(m.cx, ~50.0) && s3_near(m.cy, ~25.0))

# ---- normals, culling, drawing order ----
n = Scene3D.normal([[~0.0, ~0.0, ~0.0], [~1.0, ~0.0, ~0.0], [~1.0, ~1.0, ~0.0], [~0.0, ~1.0, ~0.0]])
s3_check("counter-clockwise in the xy-plane has normal +z", s3_near(n[0], ~0.0) && s3_near(n[1], ~0.0) && s3_near(n[2], ~1.0))
faces = Scene3D.box_faces([~0.0, ~0.0, ~0.0], [~2.0, ~1.0, ~3.0])
outward = true
dirs = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
k = 0
while k < 6
  nk = Scene3D.normal(faces[k])
  outward = false if !s3_near(nk[0], dirs[k][0] + ~0.0) || !s3_near(nk[1], dirs[k][1] + ~0.0) || !s3_near(nk[2], dirs[k][2] + ~0.0)
  k += 1
s3_check("box faces are wound outward in the order +x, -x, +y, -y, +z, -z", outward)
sc = Scene3D.new(iso)
sc.polygon([[~0.0, ~0.0, ~0.0], [~0.0, ~1.0, ~0.0], [~1.0, ~1.0, ~0.0], [~1.0, ~0.0, ~0.0]], {fill: "#ff0000", cull: true})
s3_check("a face turned away from the eye is culled", sc.count == 0)
sc.polygon([[~0.0, ~0.0, ~0.0], [~1.0, ~0.0, ~0.0], [~1.0, ~1.0, ~0.0], [~0.0, ~1.0, ~0.0]], {fill: "#ff0000", cull: true})
s3_check("a face toward the eye is kept", sc.count == 1)
sc2 = Scene3D.new(iso)
sc2.dot([~5.0, ~5.0, ~5.0], 3, {fill: "#00ff00"})
sc2.dot([~-5.0, ~-5.0, ~-5.0], 3, {fill: "#0000ff"})
sc2.dot([~0.0, ~0.0, ~0.0], 3, {fill: "#ffffff", layer: -1})
order = sc2.ordered
s3_check("lower layers first, then far before near", order[0][4][2][:fill] == "#ffffff" &&
         order[1][4][2][:fill] == "#0000ff" && order[2][4][2][:fill] == "#00ff00")
cube = Scene3D.new(iso)
cube.cube([0, 0, 0], ~1.0, {fill: "#4ea1ff"})
s3_check("an isometric cube shows exactly three faces", cube.ordered[0][4].size == 3)

# ---- colour arithmetic and shading ----
s3_check("mix endpoints", Scene3D.mix("#102030", "#f0e0d0", ~0.0) == "#102030" && Scene3D.mix("#102030", "#f0e0d0", ~1.0) == "#f0e0d0")
s3_check("mix midpoint", Scene3D.mix("#000000", "#ffffff", ~0.5) == "#808080")
s3_check("mix clamps", Scene3D.mix("#000000", "#ffffff", ~2.0) == "#ffffff")
lit = Scene3D.new(View3D.new(~0.0, ~1.2, ~0.0, ~1.0, ~0.0, ~0.0)).lighting([~0.0, ~0.0, ~1.0], ~0.4)
s3_check("a face toward the light is at full brightness", s3_near(lit.brightness([~0.0, ~0.0, ~1.0]), ~1.0))
s3_check("a face edge-on to the light keeps the ambient level", s3_near(lit.brightness([~1.0, ~0.0, ~0.0]), ~0.4))
s3_check("shading darkens toward black", lit.shaded("#ffffff", [~1.0, ~0.0, ~0.0], ~1.0) == "#666666")

# ---- rendering emits one element per visible face ----
svg = Svg.new(100, 100)
cube.render(svg)
s3_check("render writes the three polygons", svg.to_s.split("<polygon").size == 4)

<< "scene3d_spec: all checks passed"
