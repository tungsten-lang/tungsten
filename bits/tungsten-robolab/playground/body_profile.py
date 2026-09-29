"""Population-percentile body profiles (opt-in).

The robolab bodies (body.py) model an AVERAGE adult: strength 1.0, the v2
human-calibrated joint speeds (V2_OMEGA), v3's mean tendon stiffnesses, and a
1.75 m / 67.5 kg skeleton after Winter's tables. A profile rescales them to a
population percentile. Profiles are data, `playground/profiles/<name>.json`:
every multiplier with the statistic it stands for and its sources.

A profile has five independent PARTS, each switchable on its own:

  strength    peak isometric force of every muscle (per group, else the
              profile's default multiplier): the percentile of body-mass-
              normalised joint torque, so it means the same on any skeleton
  speed       maximum shortening velocity (MuJoCo vmax) of the human-
              calibrated v2/v3 muscles, per joint: fibre-type mix and
              fascicle length. v1's placeholder vmax 1.5 is not scaled.
  tendon      the v3 series-elastic tendons' stiffness, per group (the fibre
              mass is scaled with it, so the fibre-tendon mode, and with it
              the numerics, stay as v3 validated them)
  activation  MuJoCo muscle activation / deactivation time constants
  anthro      the skeleton: every length (segment, geom, site, the starting
              pelvis height) x `length`, every mass x `mass`, capsule radii so
              that density is unchanged. Joint-level torques and tendon
              stiffnesses then scale with body mass (moments scale with m^1
              under geometric similarity, Jaric 2002), so strength per kg is
              the strength part's alone. Joint angles, ranges and muscle
              geometry (JOINT / MLEN / MRANGE) do not change, but practised
              distances (COM-foot leads, clearances, pelvis-height refs) do.

`anthro` is never on by default: it changes the geometry that practised
keyframes and distances were tuned on, so it is asked for by name.

Selection (explicit builder arguments win over the environment):

  HumanoidV3Builder(..., profile="p95")                  strength, speed, tendon, activation
  HumanoidV3Builder(..., profile="p95", profile_parts="strength,anthro")
  ROBOLAB_PROFILE=p95                                    same, for every task's builder
  ROBOLAB_PROFILE_PARTS=speed | strength,anthro | all    which parts apply (default: the four muscle parts)

Unset (or "none"), nothing changes: the builders take exactly their old code
paths, and `p50` (every multiplier 1.0) builds byte-identical XML.
"""

import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILE_DIR = os.path.join(HERE, "profiles")
MUSCLE_PARTS = ("strength", "speed", "tendon", "activation")
ALL_PARTS = MUSCLE_PARTS + ("anthro",)


class Profile:
    def __init__(self, name, data, parts):
        self.name = name
        self.data = data
        self.parts = tuple(p for p in ALL_PARTS if p in parts)
        unknown = set(parts) - set(ALL_PARTS)
        if unknown:
            raise ValueError(f"unknown profile parts {sorted(unknown)}; parts are {', '.join(ALL_PARTS)}")

    def __repr__(self):
        return f"Profile({self.name!r}, parts={','.join(self.parts)})"

    def _part(self, part):
        return self.data.get("parts", {}).get(part, {}) if part in self.parts else {}

    def _mult(self, part, key=None):
        p = self._part(part)
        if key is not None and key in p.get("groups", {}):
            return float(p["groups"][key])
        return float(p.get("multiplier", 1.0))

    @property
    def anthro(self):
        return "anthro" in self.parts

    def length(self):
        return float(self._part("anthro").get("length", 1.0))

    def mass(self):
        return float(self._part("anthro").get("mass", 1.0))

    def strength(self, group, muscle=None):
        """Peak-force multiplier for a muscle group (hip, knee, ankle, toe,
        spine, shoulder, elbow, wrist, pelvis, finger, rf, ham, gas). A v2/v3
        monoarticular muscle also passes its own key `<dof>_<pos|neg>` (e.g.
        hip_flex_neg: the hip extensors, knee_neg: the vasti), which a
        profile's `groups` may name to scale one direction of a joint alone
        (opt-in: without such a key the group's value applies, as before)."""
        p = self._part("strength")
        if muscle is not None and muscle in p.get("groups", {}):
            return float(p["groups"][muscle]) * self.mass()
        return self._mult("strength", group) * self.mass()

    def speed(self, dof):
        """vmax multiplier for a joint dof (hip_flex, knee, ankle, ...)."""
        p = self._part("speed")
        groups = p.get("groups", {})
        if dof in groups:
            return float(groups[dof])
        return float(groups.get(dof.split("_")[0], p.get("multiplier", 1.0)))

    def tendon(self, group):
        """Joint-level stiffness multiplier of a v3 tendon group (achilles, quadriceps)."""
        return self._mult("tendon", group) * self.mass()

    def timeconst(self):
        p = self._part("activation")
        return float(p.get("act", 1.0)), float(p.get("deact", 1.0))


def load(name, parts=None):
    path = name if name.endswith(".json") else os.path.join(PROFILE_DIR, f"{name}.json")
    with open(path) as f:
        data = json.load(f)
    if parts is None:
        parts = MUSCLE_PARTS
    elif isinstance(parts, str):
        parts = ALL_PARTS if parts.strip() == "all" else tuple(p.strip() for p in parts.split(",") if p.strip())
    return Profile(data.get("name", os.path.basename(path)[:-5]), data, parts)


def resolve(profile=None, parts=None):
    """The builder's profile: an explicit Profile or name, else ROBOLAB_PROFILE
    (with ROBOLAB_PROFILE_PARTS); None when neither is set or either says
    "none" (the builders then run exactly their default code)."""
    if isinstance(profile, Profile):
        return profile
    if profile is None:
        profile = os.environ.get("ROBOLAB_PROFILE", "")
        if parts is None:
            parts = os.environ.get("ROBOLAB_PROFILE_PARTS") or None
    if not profile or profile == "none":
        return None
    return load(profile, parts)


def scale_body_xml(xml, length, mass):
    """Scale a body-tree XML fragment (body.py's `body_xml`): positions and
    lengths x length, masses x mass, capsule / cylinder radii x sqrt(mass /
    length) so every segment keeps its density. Joint axes and ranges, site
    sizes and colours are untouched. Anything attached inside the tree (a
    held bat) is scaled with it."""
    import xml.etree.ElementTree as ET
    radius = math.sqrt(mass / length)
    root = ET.fromstring(f"<wrap>{xml}</wrap>")

    def mul(el, attr, k):
        v = el.get(attr)
        if v is not None:
            el.set(attr, " ".join(f"{float(x) * k:.9g}" for x in v.split()))

    for el in root.iter():
        tag = el.tag
        if tag in ("body", "site", "camera", "geom", "inertial"):
            mul(el, "pos", length)
        if tag == "geom":
            mul(el, "fromto", length)
            mul(el, "mass", mass)
            kind = el.get("type", "sphere")
            size = el.get("size")
            if size is not None:
                vals = [float(x) for x in size.split()]
                if kind in ("capsule", "cylinder"):
                    vals[0] *= radius
                    if len(vals) > 1 and el.get("fromto") is None:
                        vals[1] *= length
                else:
                    vals = [x * length for x in vals]
                el.set("size", " ".join(f"{x:.9g}" for x in vals))
        if tag == "inertial":
            mul(el, "mass", mass)
            mul(el, "diaginertia", mass * length * length)
    return "\n".join(ET.tostring(child, encoding="unicode") for child in root)
