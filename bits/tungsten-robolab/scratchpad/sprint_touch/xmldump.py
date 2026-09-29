import sys, os, hashlib
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "playground"))
from body import HumanoidV2Builder, HumanoidV3Builder
out = []
for cls in (HumanoidV2Builder, HumanoidV3Builder):
    for prof in (None, "p50", "p95"):
        for parts in (None, "all"):
            try:
                b = cls("planar", profile=prof, profile_parts=parts) if prof else cls("planar")
                x = b.body_xml() + b.tendons_xml() + b.actuators_xml() + repr([(m.name, m.peak) for m in b.spec.muscles]) + repr(sorted(b.vmax.items()))
            except Exception as e:
                x = "ERR " + repr(e)
            out.append(f"{cls.__name__} {prof} {parts} {hashlib.md5(str(x).encode()).hexdigest()}")
print("\n".join(out))
