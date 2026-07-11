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
