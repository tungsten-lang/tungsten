# Animation — deterministic timelines over declarative Plot scenes.
#
# Animation produces time-indexed scene updates and camera state as portable
# data. It deliberately owns no video encoder, GUI, GPU renderer, or TeX
# engine; backends consume the stable timeline/frame descriptions.

use core/plot
use core/animation/interpolation
use core/animation/camera
use core/animation/keyframe
use core/animation/track
use core/animation/frame
use core/animation/timeline
use core/animation/model_check
use core/animation/verification
use core/animation/facade
