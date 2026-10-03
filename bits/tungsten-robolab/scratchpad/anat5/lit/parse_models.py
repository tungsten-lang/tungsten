import sys, re
import xml.etree.ElementTree as ET
def muscles(fn):
    root = ET.parse(fn).getroot()
    out = {}
    for el in root.iter():
        if el.tag in ("Thelen2003Muscle", "Millard2012EquilibriumMuscle", "Millard2012AccelerationMuscle", "Schutte1993Muscle_Deprecated", "Millard2012EquilibriumMuscle_Deprecated"):
            g = lambda t: (el.find(t).text.strip() if el.find(t) is not None and el.find(t).text else None)
            out[el.get("name")] = dict(F=float(g("max_isometric_force")), lopt=float(g("optimal_fiber_length")), lts=float(g("tendon_slack_length")),
                                       pen=float(g("pennation_angle_at_optimal")), vmax=g("max_contraction_velocity"), typ=el.tag)
    return out
if __name__ == "__main__":
    for fn in sys.argv[1:]:
        m = muscles(fn)
        print(fn, len(m))
        for k, v in m.items():
            print(f"  {k:14s} F={v['F']:8.1f} lopt={v['lopt']*100:5.1f}cm lts={v['lts']*100:5.1f}cm pen={v['pen']*57.2958:4.1f}deg {v['typ']}")
