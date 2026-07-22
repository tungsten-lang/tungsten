# Public, side-effect-free tungsten-metaflip library entry point.
#
# Importing the bit exposes scheme loading, exhaustive verification,
# rectangular support, composition, proof engines, and path policy.  The fleet
# executable is deliberately separate in bin/metaflip.w so `use metaflip`
# never starts a campaign as an import side effect.

use metaflip/scheme
use metaflip/verify
use metaflip/rect
use metaflip/compose
use metaflip/proof
use metaflip/paths
