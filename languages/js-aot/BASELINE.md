# JS-AOT baseline (milestone 0)

The engine being replaced, measured before any JS-AOT code ran: Blade's closure interpreter
(`tier0/`, copied from Blade 99b7307 plus the aot body-scope fix), through `tools/jsrun.w` with
`BLADE_JS_AOT=0`, and Blade itself for the pages. Apple M5, other work running. Each number was
taken twice; the pairs agree within 5% unless noted.

## T1 — tests/regress (47 files)

46 pass, 1 fails (`sem_ev.js`: direct eval's `function g(){}` is not hoisted into the caller;
Blade's own build fails it too).

## T3 — bench/ (tier 0, `tools/memstat.sh`)

| Benchmark | CPU (run 1 / run 2) | Peak RSS |
|---|---|---|
| closure | 1.04 / 1.01 s | 482 MB |
| property | 1.43 / 1.43 s | 314 MB |
| arith | 1.65 / 1.67 s | 7 MB |
| generator | 0.13 / 0.13 s | 77 MB |
| async | 0.17 / 0.17 s | 323 MB |
| manygen | 0.14 / 0.14 s | 43 MB |
| strbuild | killed at the 4.5 GB cap after 0.47 s (5.8–6.0 GB) | — |
| arraymethods | 2.14 / 2.11 s | 38 MB |
| forof | 2.48 / 2.46 s | 12 MB |
| classes | 0.77 / 0.80 s | 151 MB |

Script time only (`JSRUN_TIME=1`, used for the speed ratios): closure 992 ms, property
1,452 ms, arith 1,621 ms.

## T2 — test262

`tools/test262.py build/test262 ~/src/test262 build/t262_m0.txt language built-ins annexB`;
per-directory pass rates are in `build/t262_m0.summary` (filled in when the run completes).

## YouTube (Blade 99b7307 + this agent's fixes: script-mode output, the AOT body scope, fresh
## layouts for geometry reads, incremental stylesheet reloads)

- Home page (`--script`: goto, wait 15): renders the video grid (31–34 items) and the Shorts
  shelf; before the fixes it stayed on grey skeletons (ReferenceError in kevlar_base from the
  AOT tier), and with the AOT tier off it showed the chips but an empty grid (clientWidth 0).
  Peak RSS 10.3–11.2 GB; ~16 s of CPU.
- Watch page `watch?v=aqz-KE-bpKQ` (wait 14 after load): video plays (currentTime 10–12.5 s at the
  14-second mark, not paused); the metadata under the player is still skeleton at that point.
  Recording: `scratchpad/jsaot/yt/watch.bladerr` (replay diverges after a rebuild: the recording
  pins the Blade build).
- Watch page, 30 s after launch (about 14 s after load), process stopped for `heap`:

| Measure | Value |
|---|---|
| RSS | 7.3 GB (peak over the run 6.5–9.8 GB) |
| Live malloc blocks | 50.5 M (7.0 GB) |
| 16-byte blocks | 20.8 M |
| Main thread, 5 s sample at that point | 91.5% idle, 7.0% JS, 0.1% AOT cache |

- During the load (home page, 10 s sample from second 9): JS execution dominates the main
  thread, and the AOT cache's dylib copy (`cp`/`rm` per unit through `system`) took 20% of it.
- Relaying out on every geometry read when the DOM is dirty (190 layouts instead of 46 on the
  watch page) does not change its peak RSS (6.59 vs 6.60 GB).
