"""MJCF generator for the robolab muscle humanoid.

A 1.75 m, ~68 kg humanoid (segment lengths and masses after Winter's
anthropometric tables) whose every degree of freedom is driven by an
antagonist pair of MuJoCo `<muscle>` actuators with joint transmission.
For each joint `j` with positive direction named by the joint (hip flexion,
knee flexion, ankle plantarflexion, ...) there are two muscles:

  `<j>_pos`  pulls q toward +  (gear -1, so it shortens as q grows)
  `<j>_neg`  pulls q toward -  (gear +1)

Muscle contraction is reported as a fraction of the muscle's length range,
c = (Lmax - L) / (Lmax - Lmin): 0 fully lengthened, 1 fully contracted.
For a pos/neg pair, c_pos + c_neg = 1 kinematically, so a pair of commanded
contractions that sums above 1 is co-contraction (joint stiffness).

Root modes:
  planar  slide x, slide z, hinge pitch. The whole body stays in the
          sagittal plane (running, jumping, hurdling), like the 2D model of
          the NeurIPS 2017 Learning-to-Run challenge.
  free    6-DOF free joint (full 3D balance).
  pivot   pelvis held at standing height on a vertical yaw hinge that is
          itself muscle driven (pelvis rotation for batting); the legs stand
          on the floor. Used for stationary upper-body skills.

Every builder models an average adult. `profile=` (or ROBOLAB_PROFILE) opts
into a population-percentile body (body_profile.py, profiles/*.json: strength,
muscle speed, tendon stiffness, activation, and, only when asked, the
skeleton's anthropometry); unset, every builder emits exactly its old XML.
"""

from dataclasses import dataclass, field

from body_profile import resolve as resolve_profile, scale_body_xml

# name: (axis for left side, axis for right side, range, peak torque pos, peak torque neg)
# Axes are in the segment's rest frame: x forward, y left, z up.
LEG_JOINTS = {
    "hip_flex": ((0, -1, 0), (0, -1, 0), (-0.6, 2.2), 180, 280),
    "hip_abd": ((1, 0, 0), (-1, 0, 0), (-0.4, 0.8), 150, 150),
    "hip_rot": ((0, 0, -1), (0, 0, 1), (-0.6, 0.6), 80, 80),
    "knee": ((0, 1, 0), (0, 1, 0), (-0.02, 2.5), 150, 350),
    "ankle": ((0, 1, 0), (0, 1, 0), (-0.6, 0.9), 300, 80),
}
SPINE_JOINTS = {
    "spine_flex": ((0, 1, 0), None, (-0.5, 1.2), 200, 250),
    "spine_lat": ((1, 0, 0), None, (-0.5, 0.5), 150, 150),
    "spine_rot": ((0, 0, 1), None, (-0.8, 0.8), 100, 100),
}
SHOULDER_JOINTS = {
    "shoulder_flex": ((0, -1, 0), (0, -1, 0), (-1.0, 3.1), 100, 100),
    "shoulder_abd": ((1, 0, 0), (-1, 0, 0), (-0.3, 3.0), 100, 80),
    "shoulder_rot": ((0, 0, -1), (0, 0, 1), (-1.4, 1.4), 60, 60),
}
ELBOW_JOINTS = {
    "elbow": ((0, -1, 0), (0, -1, 0), (0.0, 2.6), 80, 70),
}
WRIST_JOINTS = {
    "wrist_flex": ((0, 1, 0), (0, 1, 0), (-1.2, 1.2), 25, 25),
    "wrist_dev": ((1, 0, 0), (-1, 0, 0), (-0.5, 0.5), 20, 20),
}

PLANAR_DOFS = {"hip_flex", "knee", "ankle", "spine_flex", "shoulder_flex", "elbow"}


@dataclass
class Muscle:
    name: str
    joint: str
    sign: int  # +1 pulls q positive, -1 pulls q negative
    peak: float
    qmin: float
    qmax: float
    group: str


@dataclass
class BodySpec:
    mode: str = "planar"  # planar | free | pivot
    strength: float = 1.0
    wrists: bool = False
    muscles: list = field(default_factory=list)
    joints: list = field(default_factory=list)


def _f(v):
    return " ".join(f"{x:g}" for x in v)


class HumanoidBuilder:
    def __init__(self, mode="planar", strength=1.0, wrists=None, color=(0.85, 0.87, 0.9, 1),
                 profile=None, profile_parts=None):
        assert mode in ("planar", "free", "pivot")
        self.spec = BodySpec(mode=mode, strength=strength,
                             wrists=(mode != "planar") if wrists is None else wrists)
        self.color = color
        # population-percentile profile (body_profile.py); None = the average body
        self.profile = resolve_profile(profile, profile_parts)

    def _peak_scale(self, group, muscle=None):
        """Peak-force factor of a muscle group: `strength`, times the profile's
        (per muscle `<dof>_<pos|neg>` when the profile names one)."""
        s = self.spec.strength
        return s if self.profile is None else s * self.profile.strength(group, muscle)

    def _timeconst(self):
        if self.profile is None:
            return "0.01 0.04"
        ka, kd = self.profile.timeconst()
        return f"{0.01 * ka:g} {0.04 * kd:g}"

    def _dof_enabled(self, dof):
        if self.spec.mode == "planar":
            return dof in PLANAR_DOFS
        if dof.startswith("wrist"):
            return self.spec.wrists
        return True

    def _joint(self, side, dof, table, out, group):
        axis_l, axis_r, rng, peak_pos, peak_neg = table[dof]
        axis = axis_l if side in ("l", "") else axis_r
        name = f"{side}_{dof}" if side else dof
        out.append(f'<joint name="{name}" type="hinge" axis="{_f(axis)}" range="{rng[0]} {rng[1]}" '
                   f'damping="1.5" armature="0.02" limited="true"/>')
        s = self._peak_scale(group)
        self.spec.joints.append((name, rng))
        self.spec.muscles.append(Muscle(f"{name}_pos", name, +1, peak_pos * s, rng[0], rng[1], group))
        self.spec.muscles.append(Muscle(f"{name}_neg", name, -1, peak_neg * s, rng[0], rng[1], group))

    def _joints(self, side, table, group):
        out = []
        for dof in table:
            if self._dof_enabled(dof):
                self._joint(side, dof, table, out, group)
        return "\n".join(out)

    def _leg(self, side):
        y = 0.09 if side == "l" else -0.09
        c = 'contype="2" conaffinity="1"'
        return f"""
      <body name="{side}_thigh" pos="0 {y} 0">
        {self._joints(side, {k: LEG_JOINTS[k] for k in ("hip_flex", "hip_abd", "hip_rot")}, "hip")}
        <geom name="{side}_thigh" type="capsule" fromto="0 0 0 0 0 -0.41" size="0.06" mass="7.0" {c} rgba="{_f(self.color)}"/>
        <body name="{side}_shin" pos="0 0 -0.43">
          {self._joints(side, {"knee": LEG_JOINTS["knee"]}, "knee")}
          <geom name="{side}_shin" type="capsule" fromto="0 0 0 0 0 -0.40" size="0.045" mass="3.25" {c} rgba="{_f(self.color)}"/>
          <body name="{side}_foot" pos="0 0 -0.43">
            {self._joints(side, {"ankle": LEG_JOINTS["ankle"]}, "ankle")}
            <geom name="{side}_foot" type="box" pos="0.06 0 -0.055" size="0.13 0.045 0.025" mass="1.0" friction="1.2 0.02 0.002" {c} rgba="0.25 0.27 0.32 1"/>
            <site name="{side}_heel" pos="-0.06 0 -0.08" size="0.02"/>
            <site name="{side}_toe" pos="0.18 0 -0.08" size="0.02"/>
          </body>
        </body>
      </body>"""

    def _arm(self, side):
        y = 0.19 if side == "l" else -0.19
        c = 'contype="2" conaffinity="1"'
        wrist = ""
        if self.spec.wrists:
            wrist = self._joints(side, WRIST_JOINTS, "wrist")
        return f"""
        <body name="{side}_upper_arm" pos="0 {y} 0.42">
          {self._joints(side, SHOULDER_JOINTS, "shoulder")}
          <geom name="{side}_upper_arm" type="capsule" fromto="0 0 0 0 0 -0.28" size="0.04" mass="2.0" {c} rgba="{_f(self.color)}"/>
          <body name="{side}_forearm" pos="0 0 -0.30">
            {self._joints(side, ELBOW_JOINTS, "elbow")}
            <geom name="{side}_forearm" type="capsule" fromto="0 0 0 0 0 -0.24" size="0.035" mass="1.1" {c} rgba="{_f(self.color)}"/>
            <body name="{side}_hand" pos="0 0 -0.26">
              {wrist}
              <geom name="{side}_hand" type="box" pos="0 0 -0.05" size="0.018 0.045 0.055" mass="0.4" {c} rgba="0.25 0.27 0.32 1"/>
              <site name="{side}_palm" pos="-0.02 0 -0.05" size="0.015"/>
              <site name="{side}_grip" pos="0 0 -0.06" size="0.01"/>
            </body>
          </body>
        </body>"""

    def _root(self):
        m = self.spec.mode
        if m == "planar":
            return ('<joint name="root_x" type="slide" axis="1 0 0" damping="0" armature="0"/>\n'
                    '<joint name="root_z" type="slide" axis="0 0 1" damping="0" armature="0"/>\n'
                    '<joint name="root_pitch" type="hinge" axis="0 1 0" damping="0" armature="0"/>')
        if m == "free":
            return '<freejoint name="root"/>'
        out = []
        self._joint("", "pelvis_yaw", {"pelvis_yaw": ((0, 0, 1), None, (-1.2, 1.2), 250, 250)}, out, "pelvis")
        return "\n".join(out)

    def body_xml(self, height=0.955):
        xml = self._body_xml(height)
        if self.profile is not None and (self.profile.length(), self.profile.mass()) != (1.0, 1.0):
            xml = scale_body_xml(xml, self.profile.length(), self.profile.mass())
        return xml

    def _body_xml(self, height):
        c = 'contype="2" conaffinity="1"'
        return f"""
    <body name="pelvis" pos="0 0 {height}">
      {self._root()}
      <site name="root" pos="0 0 0" size="0.01"/>
      <geom name="pelvis" type="capsule" fromto="0 -0.07 0.05 0 0.07 0.05" size="0.1" mass="10" {c} rgba="{_f(self.color)}"/>
      <body name="torso" pos="0 0 0.10">
        {self._joints("", SPINE_JOINTS, "spine")}
        <geom name="abdomen" type="capsule" fromto="0 -0.07 0.08 0 0.07 0.08" size="0.09" mass="8" {c} rgba="{_f(self.color)}"/>
        <geom name="chest" type="capsule" fromto="0 -0.09 0.30 0 0.09 0.30" size="0.11" mass="15" {c} rgba="{_f(self.color)}"/>
        <geom name="head" type="sphere" pos="0 0 0.58" size="0.1" mass="5" {c} rgba="{_f(self.color)}"/>
        <site name="chest" pos="0 0 0.30" size="0.01"/>
        <camera name="eyes" pos="0.1 0 0.6" xyaxes="0 -1 0 0 0 1"/>
        {self._arm("l")}
        {self._arm("r")}
      </body>
      {self._leg("l")}
      {self._leg("r")}
    </body>"""

    def actuators_xml(self):
        out = []
        for mu in self.spec.muscles:
            gear = -1 if mu.sign > 0 else 1
            out.append(f'<muscle name="{mu.name}" joint="{mu.joint}" gear="{gear}" force="{mu.peak:g}" '
                       f'range="0.75 1.05" lmin="0.5" lmax="1.6" vmax="1.5" fpmax="1.3" fvmax="1.2" '
                       f'timeconst="{self._timeconst()}"/>')
        return "\n    ".join(out)


def scene_xml(builder, extra_world="", extra_assets="", extra_equality="", extra_actuators="",
              timestep=0.002, floor_size=60, sky=(0.62, 0.75, 0.9), pelvis_height=0.955):
    body = builder.body_xml(pelvis_height)
    acts = builder.actuators_xml()
    return f"""<mujoco model="robolab">
  <compiler angle="radian" autolimits="true"/>
  <option timestep="{timestep}" integrator="implicitfast" iterations="50" solver="Newton"/>
  <size memory="64M"/>
  <visual>
    <global offwidth="1280" offheight="720"/>
    <quality shadowsize="4096"/>
    <headlight ambient="0.35 0.35 0.35" diffuse="0.5 0.5 0.5"/>
  </visual>
  <asset>
    <texture name="sky" type="skybox" builtin="gradient" rgb1="{_f(sky)}" rgb2="0.95 0.96 0.98" width="512" height="512"/>
    <texture name="grid" type="2d" builtin="checker" rgb1="0.78 0.8 0.82" rgb2="0.7 0.72 0.75" width="512" height="512" mark="edge" markrgb="0.6 0.62 0.65"/>
    <material name="grid" texture="grid" texrepeat="{floor_size} {floor_size}" reflectance="0.05"/>
    {extra_assets}
  </asset>
  <worldbody>
    <light name="sun" directional="true" pos="0 0 10" dir="-0.3 0.4 -1" diffuse="0.7 0.7 0.7" castshadow="true"/>
    <geom name="floor" type="plane" size="{floor_size} {floor_size} 0.1" material="grid" contype="1" conaffinity="31" friction="1.0 0.02 0.002"/>
    {body}
    {extra_world}
  </worldbody>
  <tendon>
    {builder.tendons_xml() if hasattr(builder, "tendons_xml") else ""}
  </tendon>
  <equality>
    {extra_equality}
  </equality>
  <actuator>
    {acts}
    {extra_actuators}
  </actuator>
</mujoco>"""


# ---- v2 anatomy: biarticular muscles and toes ---------------------------------
#
# HumanoidV2Builder keeps every joint of the base body and adds what the
# locomotion literature (Geyer & Herr 2010, OpenSim gait models) treats as
# essential for running and jumping:
#
#   toe (MTP) joints: the foot splits at the ball; push-off rolls over the toes
#   rectus femoris (rf):   hip flexion + knee extension
#   hamstrings (ham):      hip extension + knee flexion
#   gastrocnemius (gas):   knee flexion + ankle plantarflexion
#
# The biarticulars are MuJoCo muscles on fixed tendons (length = sum of
# coef * joint angle); monoarticular peaks are reduced so each joint's total
# peak torque stays at human scale. Geometry (JOINT/MLEN/MRANGE) is sent to the
# controller for this body so Pose maps postures onto every muscle.

V2_MONO_PEAKS = {"hip_flex": (100, 120), "knee": (40, 230), "ankle": (150, 80)}
V2_TOE = ((0, 1, 0), (0, 1, 0), (-0.8, 0.4), 40, 20)
# name: ({joint suffix: coef}, peak force); tension F gives torque -coef * F
V2_BIARTICULAR = {
    "rf": ({"hip_flex": -1.0, "knee": 0.8}, 150),
    "ham": ({"hip_flex": 1.0, "knee": -0.6}, 200),
    "gas": ({"knee": -0.3, "ankle": -1.0}, 180),
}


# Human calibration for v2 (approximate, from the biomechanics literature;
# figures are typical peak values, not individual measurements):
#
#   V2_OMEGA   unloaded peak joint angular velocity (rad/s): sprint hip swing
#              ~15, kicking knee ~25, plantarflexion ~20, trunk rotation in
#              batting/golf ~15, throwing elbow extension ~35-40, wrist ~30.
#              A MuJoCo muscle's vmax is in optimal lengths (L0 = length range
#              / 0.3) per second, so vmax = omega * 0.3 / range. The base
#              body's uniform vmax 1.5 gives distal joints 2-3x less speed
#              than a human (elbow ~13 rad/s).
#   V2_DAMPING passive joint damping (N m s/rad): large joints ~0.5-1, elbow
#              ~0.2, wrist ~0.05; the base body's 1.5 everywhere is 3-20x too
#              high distally.
#   V2_ARMATURE rotor-style inertia added for numerical stability, kept small
#              distally so it does not swamp a 0.4 kg hand.
# Opt-in articulated hand (HumanoidV2Builder(fingers=True)): a palm plus the
# four fingers as one two-segment plate, flexed at the knuckles (MCP) and the
# middle joints (PIP) by antagonist pairs (peak torques roughly those of the
# summed finger flexors / extensors); no thumb.
FINGER_JOINTS = {
    "finger_mcp": ((0, 1, 0), (0, 1, 0), (-0.4, 1.4), 12, 6),
    "finger_pip": ((0, 1, 0), (0, 1, 0), (0.0, 1.6), 8, 4),
}
V2_OMEGA = {"hip_flex": 15, "hip_abd": 10, "hip_rot": 10, "knee": 25, "ankle": 20, "toe": 15,
            "spine_flex": 10, "spine_lat": 10, "spine_rot": 15, "shoulder_flex": 20, "shoulder_abd": 20,
            "shoulder_rot": 40, "elbow": 35, "wrist_flex": 30, "wrist_dev": 20, "pelvis_yaw": 12,
            "finger_mcp": 20, "finger_pip": 20}
V2_DAMPING = {"hip": 1.0, "knee": 0.5, "ankle": 0.5, "toe": 0.1, "spine": 1.0, "shoulder": 0.3,
              "elbow": 0.2, "wrist": 0.05, "pelvis": 1.0, "finger": 0.01}
V2_ARMATURE = {"wrist": 0.002, "elbow": 0.005, "shoulder": 0.01, "finger": 0.0005}


def _v2_lookup(table, dof, default):
    if dof in table:
        return table[dof]
    return table.get(dof.split("_")[0], default)


class HumanoidV2Builder(HumanoidBuilder):
    send_geometry = True

    def __init__(self, mode="planar", strength=1.0, wrists=None, color=(0.85, 0.87, 0.9, 1), fingers=False,
                 profile=None, profile_parts=None):
        super().__init__(mode, strength, wrists, color, profile, profile_parts)
        self.biarticular = []  # (name, {joint: coef}, peak, lo, hi)
        self.vmax = {}  # muscle name -> vmax (optimal lengths per second)
        self.fingers = fingers

    def _arm(self, side):
        if not self.fingers:
            return super()._arm(side)
        y = 0.19 if side == "l" else -0.19
        c = 'contype="2" conaffinity="1"'
        wrist = self._joints(side, WRIST_JOINTS, "wrist") if self.spec.wrists else ""
        dark = "0.25 0.27 0.32 1"
        return f"""
        <body name="{side}_upper_arm" pos="0 {y} 0.42">
          {self._joints(side, SHOULDER_JOINTS, "shoulder")}
          <geom name="{side}_upper_arm" type="capsule" fromto="0 0 0 0 0 -0.28" size="0.04" mass="2.0" {c} rgba="{_f(self.color)}"/>
          <body name="{side}_forearm" pos="0 0 -0.30">
            {self._joints(side, ELBOW_JOINTS, "elbow")}
            <geom name="{side}_forearm" type="capsule" fromto="0 0 0 0 0 -0.24" size="0.035" mass="1.1" {c} rgba="{_f(self.color)}"/>
            <body name="{side}_hand" pos="0 0 -0.26">
              {wrist}
              <geom name="{side}_hand" type="box" pos="0 0 -0.035" size="0.018 0.045 0.035" mass="0.29" {c} rgba="{dark}"/>
              <site name="{side}_palm" pos="-0.02 0 -0.05" size="0.015"/>
              <site name="{side}_grip" pos="0 0 -0.06" size="0.01"/>
              <body name="{side}_fingers1" pos="0 0 -0.07">
                {self._joints(side, {"finger_mcp": FINGER_JOINTS["finger_mcp"]}, "finger")}
                <geom name="{side}_fingers1" type="box" pos="0 0 -0.022" size="0.011 0.043 0.022" mass="0.07" {c} rgba="{dark}"/>
                <body name="{side}_fingers2" pos="0 0 -0.044">
                  {self._joints(side, {"finger_pip": FINGER_JOINTS["finger_pip"]}, "finger")}
                  <geom name="{side}_fingers2" type="box" pos="0 0 -0.018" size="0.009 0.041 0.018" mass="0.04" {c} rgba="{dark}"/>
                  <site name="{side}_fingertip" pos="-0.01 0 -0.034" size="0.01"/>
                </body>
              </body>
            </body>
          </body>
        </body>"""

    def _dof_enabled(self, dof):
        if dof.startswith("finger"):
            return self.fingers
        if dof == "toe":
            return True
        return super()._dof_enabled(dof)

    def _joint(self, side, dof, table, out, group):
        axis_l, axis_r, rng, peak_pos, peak_neg = table[dof]
        if side in ("l", "r") and dof in V2_MONO_PEAKS:
            peak_pos, peak_neg = V2_MONO_PEAKS[dof]
        axis = axis_l if side in ("l", "") else axis_r
        name = f"{side}_{dof}" if side else dof
        damping = _v2_lookup(V2_DAMPING, dof, 1.0)
        armature = _v2_lookup(V2_ARMATURE, dof, 0.02)
        out.append(f'<joint name="{name}" type="hinge" axis="{_f(axis)}" range="{rng[0]} {rng[1]}" '
                   f'damping="{damping:g}" armature="{armature:g}" limited="true"/>')
        self.spec.joints.append((name, rng))
        vmax = _v2_lookup(V2_OMEGA, dof, 15) * 0.3 / (rng[1] - rng[0])
        if self.profile is not None:
            vmax *= self.profile.speed(dof)
        for suffix, sign, peak in (("pos", +1, peak_pos), ("neg", -1, peak_neg)):
            s = self._peak_scale(group, f"{dof}_{suffix}")
            self.spec.muscles.append(Muscle(f"{name}_{suffix}", name, sign, peak * s, rng[0], rng[1], group))
            self.vmax[f"{name}_{suffix}"] = vmax

    def _leg(self, side):
        y = 0.09 if side == "l" else -0.09
        c = 'contype="2" conaffinity="1"'
        xml = f"""
      <body name="{side}_thigh" pos="0 {y} 0">
        {self._joints(side, {k: LEG_JOINTS[k] for k in ("hip_flex", "hip_abd", "hip_rot")}, "hip")}
        <geom name="{side}_thigh" type="capsule" fromto="0 0 0 0 0 -0.41" size="0.06" mass="7.0" {c} rgba="{_f(self.color)}"/>
        <body name="{side}_shin" pos="0 0 -0.43">
          {self._joints(side, {"knee": LEG_JOINTS["knee"]}, "knee")}
          <geom name="{side}_shin" type="capsule" fromto="0 0 0 0 0 -0.40" size="0.045" mass="3.25" {c} rgba="{_f(self.color)}"/>
          <body name="{side}_foot" pos="0 0 -0.43">
            {self._joints(side, {"ankle": LEG_JOINTS["ankle"]}, "ankle")}
            <geom name="{side}_foot" type="box" pos="0.035 0 -0.055" size="0.105 0.045 0.025" mass="0.8" friction="1.2 0.02 0.002" {c} rgba="0.25 0.27 0.32 1"/>
            <site name="{side}_heel" pos="-0.06 0 -0.08" size="0.02"/>
            <body name="{side}_toes" pos="0.14 0 -0.068">
              {self._joints(side, {"toe": V2_TOE}, "toe")}
              <geom name="{side}_toes" type="box" pos="0.035 0 0" size="0.035 0.045 0.012" mass="0.2" friction="1.2 0.02 0.002" {c} rgba="0.25 0.27 0.32 1"/>
              <site name="{side}_toe" pos="0.05 0 -0.012" size="0.02"/>
            </body>
          </body>
        </body>
      </body>"""
        ranges = {name: rng for name, rng in self.spec.joints}
        for short, (coefs, peak) in V2_BIARTICULAR.items():
            joints = {f"{side}_{j}": k for j, k in coefs.items() if f"{side}_{j}" in ranges}
            if len(joints) < 2:
                continue
            s = self._peak_scale(short)
            lo = sum(min(k * ranges[j][0], k * ranges[j][1]) for j, k in joints.items())
            hi = sum(max(k * ranges[j][0], k * ranges[j][1]) for j, k in joints.items())
            name = f"{side}_{short}"
            self.biarticular.append((name, joints, peak * s, lo, hi))
            speed = sum(abs(k) * V2_OMEGA[j.split("_", 1)[1]] for j, k in joints.items())
            if self.profile is not None:
                speed = sum(abs(k) * V2_OMEGA[j.split("_", 1)[1]] * self.profile.speed(j.split("_", 1)[1])
                            for j, k in joints.items())
            self.vmax[name] = speed * 0.3 / (hi - lo)
            primary, coef = max(joints.items(), key=lambda kv: abs(kv[1]))
            sign = 1 if coef < 0 else -1
            self.spec.muscles.append(Muscle(name, primary, sign, peak * s, ranges[primary][0], ranges[primary][1], short))
        return xml

    def tendons_xml(self):
        out = []
        for name, joints, _, _, _ in self.biarticular:
            js = "".join(f'<joint joint="{j}" coef="{k:g}"/>' for j, k in joints.items())
            out.append(f'<fixed name="{name}">{js}</fixed>')
        return "\n    ".join(out)

    def actuators_xml(self):
        bi = {b[0]: b for b in self.biarticular}
        out = []
        for mu in self.spec.muscles:
            if mu.name in bi:
                _, _, peak, lo, hi = bi[mu.name]
                out.append(f'<muscle name="{mu.name}" tendon="{mu.name}" force="{peak:g}" lengthrange="{lo:g} {hi:g}" '
                           f'range="0.75 1.05" lmin="0.5" lmax="1.6" vmax="{self.vmax[mu.name]:.4g}" fpmax="1.3" fvmax="1.2" '
                           f'timeconst="{self._timeconst()}"/>')
            else:
                gear = -1 if mu.sign > 0 else 1
                out.append(f'<muscle name="{mu.name}" joint="{mu.joint}" gear="{gear}" force="{mu.peak:g}" '
                           f'range="0.75 1.05" lmin="0.5" lmax="1.6" vmax="{self.vmax.get(mu.name, 1.5):.4g}" fpmax="1.3" fvmax="1.2" '
                           f'timeconst="{self._timeconst()}"/>')
        return "\n    ".join(out)


# ---- v3 anatomy: series-elastic tendons (opt-in) --------------------------------
#
# HumanoidV3Builder is the v2 anatomy (same joints, muscles, muscle order,
# peaks, speeds and damping) with a compliant tendon in series with the fibres
# of the ankle plantarflexors (soleus = <side>_ankle_pos and gastrocnemius =
# <side>_gas: the Achilles tendon) and the knee extensors (vasti =
# <side>_knee_neg and rectus femoris = <side>_rf: the quadriceps and patellar
# tendons). v1 and v2 are untouched. MuJoCo muscles have rigid tendons, so
# each elastic muscle-tendon unit (MTU) is split into two elements in series:
#
#   fibre   the MuJoCo <muscle> (v2's force-length-velocity curves, peak force,
#           vmax, activation dynamics and length range) acts on its own slide
#           DOF `<muscle>_fiber`: the fibre length x, in the MTU's length units.
#           The DOF sits on a weightless body on the world, so it couples to the
#           skeleton only through the tendon.
#   tendon  a fixed tendon `<muscle>_see` of length L_T = L_MTU(q) - x, where
#           L_MTU(q) = sum_j coef_j q_j is the v2 muscle's path length: a linear,
#           tension-only spring F_T = K max(0, L_T) (MuJoCo tendon stiffness with
#           the dead band [-1000, 0], so a slack tendon pushes nothing).
#
# The slack length is set so that an unloaded tendon leaves the fibre exactly
# as long as the v2 muscle would be (x = L_MTU(q)): a posture maps to the same
# contraction as on v2, and under a load F the fibre is F / K shorter than the
# posture implies (the tendon took the difference). In equilibrium F_T equals
# the fibre force and the skeleton receives torque coef_j F_T, as on v2; in
# motion the fibre can stay near-isometric while the tendon stretches and
# recoils (the stretch-shortening "catapult" of running and jumping).
#
# Units: an MTU length is in its v2 muscle's units (radians of its joint at
# coef 1) and a force is a torque at coef 1 (N m), so energies come out in J.
# A linear tendon of stiffness k (N/m) at moment arm r (m) about joint J is a
# rotational stiffness K_J = k r^2 (N m/rad). A tendon group's K_J is shared
# among its muscles in proportion to their peak torques about J (muscle i:
# K_i = share_i K_J / coef_iJ^2), so at peak force every member stretches the
# same joint-equivalent amount, as a shared tendon would.
#
# Parameters (V3_TENDONS; approximate literature values, not individual
# measurements):
#   achilles     k = 200 N/mm at r = 5.0 cm about the ankle (in vivo Achilles
#                tendon stiffness is ~150-250 N/mm at running loads, e.g.
#                Lichtwark & Wilson 2005 in hopping, Magnusson et al. 2003;
#                plantarflexor moment arm ~5 cm, Maganaris et al. 1998):
#                K_ankle = 500 N m/rad, i.e. 0.66 rad of ankle-equivalent
#                stretch at the v2 plantarflexors' summed peak (150 + 180 N m).
#   quadriceps   k = 250 N/mm at r = 4.5 cm about the knee: the knee
#                extensors' whole series-elastic element (quadriceps tendon,
#                patella and patellar tendon, aponeurosis). The free patellar
#                tendon alone is much stiffer (~2-4 kN/mm, Hansen et al. 2006);
#                in vivo tendon-aponeurosis measurements (Kubo et al., vastus
#                lateralis ~50-100 N/mm scaled to the whole quadriceps) put the
#                whole element in the same order as the Achilles:
#                K_knee = 506 N m/rad, 0.69 rad at the summed peak (230 + 0.8 x 150).
#   fibre mass   m_f = 1.0 kg per group at r (the effective moving mass of the
#                muscle bellies, rounded up so the fibre-tendon mode, ~450-500
#                rad/s, is resolved at a 1 ms timestep), shared like K.
#   fibre damping  beta = 0.1 of F0 / (vmax L0) (Millard et al. 2013's damped
#                fibre), a passive viscosity in parallel with the fibre that damps
#                the fibre-tendon mode while the muscle is silent.
#   The tendon itself is lossless (real tendons return ~90-95 % of the energy
#   stored; this model returns all of it).
#
# Numerics: use a 1 ms timestep (the v3 tasks do; control stays at 4 ms).
#
# Contraction and geometry: the bridge reports each muscle's contraction from
# its actuator length, which for an elastic muscle is the fibre length x, so c
# and cdot are fibre (spindle) signals and the reflexes act on them. The
# posture geometry sent to the controller (JOINT / MLEN / MRANGE) is the MTU
# path length L_MTU(q) (actuator length + tendon length) over the v2 length
# range: Pose maps a posture to the fibre contraction that holds it with a
# slack tendon; under load the fibre sits shorter by F / K and the reflexes
# see that error. The fibre DOFs are internal and never appear as joints.

V3_TENDONS = {
    # group: (joint, muscle suffixes, stiffness N/mm, moment arm m, fibre mass kg)
    "achilles": ("ankle", ("ankle_pos", "gas"), 200.0, 0.050, 1.0),
    "quadriceps": ("knee", ("knee_neg", "rf"), 250.0, 0.045, 1.0),
}
V3_FIBER_BETA = 0.1


def settle_fibers(m, d):
    """Set every series-elastic tendon (a `<name>_see` fixed tendon with its
    `<name>_fiber` DOF) to its slack length for the current posture: the fibre
    as long as the MTU path, unloaded, as a v2 muscle would be. No-op on
    bodies without fibres. Call after a task's reset has set the posture."""
    import mujoco
    mujoco.mj_forward(m, d)
    moved = False
    for t in range(m.ntendon):
        name = m.tendon(t).name
        if name.endswith("_see"):
            j = m.joint(name[:-4] + "_fiber")
            d.qpos[j.qposadr[0]] += d.ten_length[t]
            d.qvel[j.dofadr[0]] = 0.0
            moved = True
    if moved:
        mujoco.mj_forward(m, d)


class HumanoidV3Builder(HumanoidV2Builder):
    """v2 anatomy + series-elastic Achilles and quadriceps tendons (see above).

    `groups` picks the tendon groups (default both); `stiffness_scale`
    multiplies every tendon stiffness (for sensitivity checks)."""

    def __init__(self, mode="planar", strength=1.0, wrists=None, color=(0.85, 0.87, 0.9, 1),
                 groups=("achilles", "quadriceps"), stiffness_scale=1.0, profile=None, profile_parts=None):
        super().__init__(mode, strength, wrists, color, profile=profile, profile_parts=profile_parts)
        self.groups = tuple(groups)
        self.stiffness_scale = stiffness_scale
        self.elastic = {}  # muscle name -> dict(path, lo, hi, K, inertia, damping, group, joint, coef)

    def _v3_units(self):
        """Every elastic MTU's path, length range, stiffness, fibre inertia and damping."""
        ranges = {name: rng for name, rng in self.spec.joints}
        bi = {b[0]: b for b in self.biarticular}
        out = {}
        for side in ("l", "r"):
            for group in self.groups:
                joint, suffixes, k_mm, arm, mass = V3_TENDONS[group]
                jname = f"{side}_{joint}"
                if jname not in ranges:
                    continue
                units = []
                for suffix in suffixes:
                    name = f"{side}_{suffix}"
                    mu = next((u for u in self.spec.muscles if u.name == name), None)
                    if mu is None:
                        continue
                    if name in bi:
                        _, path, _, lo, hi = bi[name]
                        path = dict(path)
                    else:
                        gear = -1 if mu.sign > 0 else 1
                        path = {mu.joint: gear}
                        qlo, qhi = ranges[mu.joint]
                        lo, hi = min(gear * qlo, gear * qhi), max(gear * qlo, gear * qhi)
                    coef = abs(path.get(jname, 0.0))
                    if coef == 0.0:
                        continue
                    units.append((name, mu, path, lo, hi, coef, mu.peak * coef))
                total = sum(u[6] for u in units)
                KJ = k_mm * 1000.0 * arm * arm * self.stiffness_scale
                IJ = mass * arm * arm
                if self.profile is not None:
                    # the fibre mass (sized for the numerics) scales with the
                    # stiffness, so the fibre-tendon mode stays where v3 validated it
                    KJ *= self.profile.tendon(group)
                    IJ *= self.profile.tendon(group)
                for name, mu, path, lo, hi, coef, torque in units:
                    share = torque / total
                    L0 = (hi - lo) / 0.3
                    out[name] = {"group": group, "joint": jname, "coef": coef, "path": path, "lo": lo, "hi": hi,
                                 "K": share * KJ / coef ** 2, "inertia": share * IJ / coef ** 2,
                                 "damping": V3_FIBER_BETA * mu.peak / (self.vmax[name] * L0)}
        return out

    def body_xml(self, height=0.955):
        xml = super().body_xml(height)
        self.elastic = self._v3_units()
        # the fibres keep their v2 muscles' length ranges exactly (MuJoCo derives a
        # joint muscle's range at compile time, a hair beyond the joint limits)
        import mujoco
        twin = mujoco.MjModel.from_xml_string(scene_xml(HumanoidV2Builder(
            self.spec.mode, strength=self.spec.strength, wrists=self.spec.wrists, color=self.color,
            profile=self.profile or "none")))
        for name, e in self.elastic.items():
            e["lo"], e["hi"] = (float(v) for v in twin.actuator_lengthrange[twin.actuator(name).id])
        fibres = []
        for name, e in self.elastic.items():
            span = e["hi"] - e["lo"]
            fibres.append(f'<body name="{name}_fiber"><joint name="{name}_fiber" type="slide" axis="0 1 0" '
                          f'range="{e["lo"] - span:.6g} {e["hi"] + span:.6g}" limited="true" '
                          f'armature="{e["inertia"]:.6g}" damping="{e["damping"]:.6g}"/>'
                          f'<inertial pos="0 0 0" mass="1e-6" diaginertia="1e-9 1e-9 1e-9"/></body>')
        return xml + "\n    " + "\n    ".join(fibres)

    def tendons_xml(self):
        out = [super().tendons_xml()]
        for name, e in self.elastic.items():
            js = "".join(f'<joint joint="{j}" coef="{k:g}"/>' for j, k in e["path"].items())
            out.append(f'<fixed name="{name}_see" stiffness="{e["K"]:.6g}" springlength="-1000 0">'
                       f'{js}<joint joint="{name}_fiber" coef="-1"/></fixed>')
        return "\n    ".join(out)

    def actuators_xml(self):
        lines = super().actuators_xml().split("\n    ")
        for i, mu in enumerate(self.spec.muscles):
            e = self.elastic.get(mu.name)
            if e is not None:
                lines[i] = (f'<muscle name="{mu.name}" joint="{mu.name}_fiber" gear="1" force="{mu.peak:g}" '
                            f'lengthrange="{e["lo"]:.12g} {e["hi"]:.12g}" range="0.75 1.05" lmin="0.5" lmax="1.6" '
                            f'vmax="{self.vmax[mu.name]:.4g}" fpmax="1.3" fvmax="1.2" timeconst="{self._timeconst()}"/>')
        return "\n    ".join(lines)

    def muscle_geometry(self, m, muscle_ids, ref_qpos):
        """The bridge's JOINT / MLEN / MRANGE geometry (myo_bridge.muscle_geometry's
        sampling) over MTU path lengths: an elastic muscle's length is its fibre
        (actuator length) plus its tendon, so the fibre DOFs drop out and a
        posture's lengths are those of a slack tendon."""
        import math
        import mujoco
        import numpy as np
        from myo_bridge import SAMPLES
        see = np.array([mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_TENDON,
                                          f"{mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_ACTUATOR, a)}_see")
                        for a in muscle_ids])
        el = see >= 0

        def lengths(d):
            L = d.actuator_length[muscle_ids].copy()
            L[el] += d.ten_length[see[el]]
            return L

        ref_qpos = np.array(ref_qpos, dtype=float)
        d = mujoco.MjData(m)
        d.qpos[:] = ref_qpos
        mujoco.mj_forward(m, d)
        base = lengths(d)
        cand = []
        for j in range(m.njnt):
            if int(m.jnt_type[j]) not in (int(mujoco.mjtJoint.mjJNT_HINGE), int(mujoco.mjtJoint.mjJNT_SLIDE)):
                continue
            adr = m.jnt_qposadr[j]
            lo, hi = (m.jnt_range[j] if m.jnt_limited[j] else (-math.pi, math.pi))
            span = hi - lo
            d.qpos[:] = ref_qpos
            d.qpos[adr] = min(hi, ref_qpos[adr] + 0.02 * span)
            mujoco.mj_forward(m, d)
            up = lengths(d)
            d.qpos[:] = ref_qpos
            d.qpos[adr] = max(lo, ref_qpos[adr] - 0.02 * span)
            mujoco.mj_forward(m, d)
            dn = lengths(d)
            if np.max(np.abs(up - dn)) > 1e-7:
                cand.append((j, m.joint(j).name, float(lo), float(hi), float(ref_qpos[adr]), adr))
        table = [dict() for _ in muscle_ids]
        for k, (j, name, lo, hi, qref, adr) in enumerate(cand):
            rows = []
            for q in np.linspace(lo, hi, SAMPLES):
                d.qpos[:] = ref_qpos
                d.qpos[adr] = q
                mujoco.mj_forward(m, d)
                rows.append(lengths(d))
            rows = np.array(rows)
            for i in range(len(muscle_ids)):
                if np.max(rows[:, i]) - np.min(rows[:, i]) > 1e-6:
                    table[i][k] = rows[:, i].tolist()
        return cand, table, base


# ---- v4 anatomy: a calibrated body (opt-in) --------------------------------------
#
# HumanoidV4Builder is the v3 body (series-elastic Achilles and quadriceps) with
# its muscle, segment and contact parameters taken from a CALIBRATION file,
# playground/calibrations/<name>.json: every value with the literature it
# stands for (see that file). v1-v3 are untouched; a calibration that sets
# nothing builds exactly the v3 XML. Keys (all optional; the v3 value in
# brackets):
#
#   omega         {dof: rad/s} unloaded joint angular velocity [V2_OMEGA]
#   omega_scale   {dof or "all": x} multiplies it
#   omega_muscle  {muscle suffix: rad/s} one direction of a joint alone (e.g.
#                 hip_flex_neg = the hip extensors); a biarticular muscle takes
#                 the value of the direction it acts in at each joint
#   fl_range      [lo, hi] each muscle's normalised fibre length over its joint
#                 range [0.75, 1.05]; vmax is kept consistent (omega unchanged)
#   lmin, lmax, fpmax, fvmax   MuJoCo muscle curve parameters [0.5, 1.6, 1.3, 1.2]
#   timeconst     [activation, deactivation] s [0.01, 0.04]
#   peaks         {muscle suffix: N m} (hip_flex_pos, hip_flex_neg, knee_pos,
#                 knee_neg, ankle_pos, ankle_neg, toe_pos, toe_neg, rf, ham, gas)
#   tendon_scale  {achilles | quadriceps: x} stiffness multipliers
#   mass          {segment geom: kg} (thigh, shin, foot, toes, pelvis, abdomen,
#                 chest, head, upper_arm, forearm, hand); inertia follows mass
#   foot_friction [1.2], foot_solref [timeconst, dampratio] (MuJoCo default
#                 0.02 1) on the feet's geoms
#
# Selection: HumanoidV4Builder(..., calib=<name | path | dict>), or for any
# task / tool ROBOLAB_BODY=v4 with ROBOLAB_CALIB=<name> and, for one-off
# probes, ROBOLAB_CALIB_SET="key=value;key=value" (JSON values).

import os  # noqa: E402

CALIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "calibrations")


def load_calibration(calib=None):
    """The calibration's parameter values as a flat dict (file values, then
    ROBOLAB_CALIB_SET overrides)."""
    import json
    if calib is None:
        calib = os.environ.get("ROBOLAB_CALIB", "")
    vals = {}
    if isinstance(calib, dict):
        vals = dict(calib)
    elif calib:
        path = calib if calib.endswith(".json") else os.path.join(CALIB_DIR, f"{calib}.json")
        with open(path) as f:
            data = json.load(f)
        for k, v in data.get("params", {}).items():
            vals[k] = v["value"] if isinstance(v, dict) and "value" in v else v
    extra = os.environ.get("ROBOLAB_CALIB_SET", "")
    for kv in extra.split(";"):
        if kv.strip():
            k, v = kv.split("=", 1)
            vals[k.strip()] = json.loads(v)
    return vals


class HumanoidV4Builder(HumanoidV3Builder):
    """v3 body with calibrated parameters (see above)."""

    def __init__(self, mode="planar", strength=1.0, wrists=None, color=(0.85, 0.87, 0.9, 1),
                 groups=("achilles", "quadriceps"), stiffness_scale=1.0, profile=None, profile_parts=None, calib=None):
        super().__init__(mode, strength, wrists, color, groups, stiffness_scale, profile=profile, profile_parts=profile_parts)
        self.calib = load_calibration(calib)
        self._v4_done = False

    def _c(self, key, default):
        return self.calib.get(key, default)

    def _omega_factor(self, dof):
        f = 1.0
        om = self.calib.get("omega", {})
        if dof in om:
            f *= float(om[dof]) / _v2_lookup(V2_OMEGA, dof, 15)
        sc = self.calib.get("omega_scale", {})
        if isinstance(sc, (int, float)):
            f *= float(sc)
        else:
            f *= float(sc.get(dof, sc.get("all", 1.0)))
        return f

    # the direction a biarticular muscle acts in at each of its joints
    BI_DIRECTION = {"ham": {"hip_flex": "hip_flex_neg", "knee": "knee_pos"},
                    "rf": {"hip_flex": "hip_flex_pos", "knee": "knee_neg"},
                    "gas": {"knee": "knee_pos", "ankle": "ankle_pos"}}

    def _muscle_factor(self, suffix, dof):
        """omega factor of one muscle direction (omega_muscle), else the dof's."""
        om = self.calib.get("omega_muscle", {})
        if suffix in om:
            return float(om[suffix]) / _v2_lookup(V2_OMEGA, dof, 15)
        return self._omega_factor(dof)

    def _fl(self):
        lo, hi = self._c("fl_range", [0.75, 1.05])
        return float(lo), float(hi)

    def _apply_calibration(self):
        """Peaks and speeds, once the v2 body has collected its muscles."""
        if self._v4_done:
            return
        self._v4_done = True
        peaks = self.calib.get("peaks", {})
        lo, hi = self._fl()
        wscale = (hi - lo) / 0.3
        bi = {b[0]: i for i, b in enumerate(self.biarticular)}
        for mu in self.spec.muscles:
            suffix = mu.name[2:] if mu.name[:2] in ("l_", "r_") else mu.name
            if suffix in peaks:
                scale = self._peak_scale(mu.group if suffix not in ("rf", "ham", "gas") else suffix,
                                         suffix if suffix not in ("rf", "ham", "gas") else None)
                mu.peak = float(peaks[suffix]) * scale
                if mu.name in bi:
                    b = self.biarticular[bi[mu.name]]
                    self.biarticular[bi[mu.name]] = (b[0], b[1], mu.peak, b[3], b[4])
            if mu.name in self.vmax:
                if mu.name in bi:
                    joints = self.biarticular[bi[mu.name]][1]
                    dirs = self.BI_DIRECTION.get(suffix, {})
                    num = sum(abs(k) * _v2_lookup(V2_OMEGA, j.split("_", 1)[1], 15)
                              * self._muscle_factor(dirs.get(j.split("_", 1)[1], ""), j.split("_", 1)[1])
                              for j, k in joints.items())
                    den = sum(abs(k) * _v2_lookup(V2_OMEGA, j.split("_", 1)[1], 15) for j, k in joints.items())
                    f = num / den
                else:
                    f = self._muscle_factor(suffix, mu.joint.split("_", 1)[1] if mu.joint[:2] in ("l_", "r_") else mu.joint)
                self.vmax[mu.name] *= f * wscale

    def _v3_units(self):
        self._apply_calibration()
        out = super()._v3_units()
        lo, hi = self._fl()
        ts = self.calib.get("tendon_scale", {})
        for name, e in out.items():
            s = float(ts.get(e["group"], 1.0))
            e["K"] *= s
            e["inertia"] *= s
            mu = next(u for u in self.spec.muscles if u.name == name)
            L0 = (e["hi"] - e["lo"]) / (hi - lo)
            e["damping"] = V3_FIBER_BETA * mu.peak / (self.vmax[name] * L0)
        return out

    def body_xml(self, height=0.955):
        import re
        xml = super().body_xml(height)
        mass = self.calib.get("mass", {})
        for seg, kg in mass.items():
            for side in ("l_", "r_", ""):
                pat = re.compile(r'(<geom name="%s" [^>]*?mass=")([0-9.eE+-]+)(")' % re.escape(side + seg))
                xml = pat.sub(lambda m_: m_.group(1) + f"{float(kg):g}" + m_.group(3), xml)
        fr = self.calib.get("foot_friction")
        sr = self.calib.get("foot_solref")
        for g in ("foot", "toes"):
            for side in ("l_", "r_"):
                pat = re.compile(r'(<geom name="%s" [^>]*?)( ?/>)' % re.escape(side + g))
                if fr is not None:
                    xml = re.sub(r'(<geom name="%s" [^>]*?friction=")([0-9.]+)' % re.escape(side + g),
                                 lambda m_: m_.group(1) + f"{float(fr):g}", xml)
                if sr is not None:
                    xml = pat.sub(lambda m_: m_.group(1) + f' solref="{float(sr[0]):g} {float(sr[1]):g}"' + m_.group(2), xml)
        return xml

    def actuators_xml(self):
        self._apply_calibration()
        out = super().actuators_xml()
        lo, hi = self._fl()
        subs = [('range="0.75 1.05"', f'range="{lo:g} {hi:g}"'), ('lmin="0.5"', f'lmin="{float(self._c("lmin", 0.5)):g}"'),
                ('lmax="1.6"', f'lmax="{float(self._c("lmax", 1.6)):g}"'), ('fpmax="1.3"', f'fpmax="{float(self._c("fpmax", 1.3)):g}"'),
                ('fvmax="1.2"', f'fvmax="{float(self._c("fvmax", 1.2)):g}"')]
        for a, b in subs:
            if a != b:
                out = out.replace(a, b)
        if "timeconst" in self.calib:
            ta, td = (float(x) for x in self.calib["timeconst"])
            if self.profile is not None:
                ka, kd = self.profile.timeconst()
                ta, td = ta * ka, td * kd
            out = out.replace(f'timeconst="{self._timeconst()}"', f'timeconst="{ta:g} {td:g}"')
        return out
