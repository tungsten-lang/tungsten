# Exact GF(2) 20×21×23 projection/walk descendants

The checked-in 20×21×23/r5463 tensor seeded a one-round automatic
projection/basis/walk loop with two 50M-move walk slots. Its distinct
19×21×23/r5347 and 20×20×23/r5211 projections received both slots and
reached r5316 and r5146. A third exact projection reached
20×21×22/r5345. `python3 verify.py` reconstructs all projected seeds and
independently checks each tensor in Python and Ruby. The walk metadata is
provenance, not a replay of every stochastic move.

These are GF(2) tensor-rank upper bounds, not optimality or confirmed global
world-record claims. Only exact tensor witnesses are retained here;
the pinned 2..32 GF(2) composition calculation lowers exactly these three
shape prices (5540→5316, 5261→5146, 5347→5345), by 341 summed rank units.
It produces no additional larger-shape price improvement from this generation.
