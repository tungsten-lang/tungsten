"""Public comparator tables for the whole shape grid, via the repo's scoreboard tool."""
from pathlib import Path
from types import SimpleNamespace
import sys

W = Path(__file__).resolve().parent
TOOLS = '/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools'
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
import gf2_record_board as grb  # noqa: E402


def tables():
    """(lille, any_ring, gf2_valid): {sorted shape tuple: best listed rank}."""
    args = SimpleNamespace(lille=str(W / 'upstream/fmm_digest/fmm_sota.json'),
                           matmulcatalog=str(W / 'mmc_catalog_0929.json'),
                           fmm_repo=str(W / 'upstream/fmm'), fmm_revision='HEAD',
                           extra_repo=[str(W / 'upstream/merlijn')])
    return grb.public_tables(args)
