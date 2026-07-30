# Plotting

| Layer | Path | Role |
|-------|------|------|
| **PlotExt** | `core/plot.w` | sparklines, ASCII heatmap, coarse line |
| **drawille** | `bits/tungsten-drawille` | braille canvas, polynomial `Plot` |

```
use core/plot
<< PlotExt.sparkline([~1.0, ~2.0, ~3.0, ~2.0, ~1.0])  # .+#+.
```

Class stays `PlotExt` so it doesn’t collide with drawille’s `Plot`.

This is not yet a scene-graph or mathematical-animation toolkit. The planned
2D/3D, timeline, formula-morphing, interactive-documentation, and deterministic
rendering layers are mapped in [../mathematics.md](../mathematics.md).
