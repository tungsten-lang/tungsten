import cProfile, pstats, os, sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
p = read_params("params/myo_soccer_single_leg_310_lift.txt")
sim = MyoSim(MyoSoccerTask(), params=p, controller="bin/challengers/soccer6-g", seed=90000)
pr = cProfile.Profile()
pr.enable()
sim.run(4.0)
pr.disable()
st = pstats.Stats(pr)
st.sort_stats("cumulative").print_stats(28)
