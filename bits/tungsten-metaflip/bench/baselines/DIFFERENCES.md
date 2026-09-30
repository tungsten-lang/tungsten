# The programs compared: problem statement, moves, counting, restarts, randomness

Catalogue of what each program does, read from its source at the pinned commit (`PINS.md`). Citations are
`file:line`; a path is relative to the program's tree: `km2022` = `flips/code/`, `km2024` = `flips/updated_code/`,
`tfg` = `ternary_flip_graph/`, `metaflip` = `bits/tungsten-metaflip/` (the directed walker as the campaign ran it,
`lib/metaflip/wide/{scheme,directed}.w`, `tools/wide_rect_walk.w`, `papers/methods/sections/walker.tex`).
All four search the flip graph of matrix-multiplication schemes over GF(2) by random walk. The tables list the differences
that bear on a comparison; the last section states which conditions the harness equalises.

## 1. Problem statement

| | metaflip | km2022 | km2024 | tfg (`--ring Z2`) |
| --- | --- | --- | --- | --- |
| tensor | `sum a[i][k] b[k][j] c[i][j]` in `n x m x p`; `C` is `n x p` (`bench/README.md`) | `sum a[i][k] b[k][j] c[j][i]`, `C` transposed, `p x n` (`scheme.cpp:233-270`) | as km2022 (`mm.cpp:101-141`) | `U` `n1 x n2`, `V` `n2 x n3`, `W` `n3 x n1` (`binary_scheme.hpp:116-146`, `:1217-1232`) |
| coefficients | GF(2) | GF(2): factors are 64-bit masks combined by XOR (`scheme.hpp:65`, `scheme.cpp:147-154`) | as km2022 (`tensor.hpp:31`) | `Z2`: bit masks in `uint16_t` ... `uint256_t` by size (`binary_scheme.hpp:21-24`, `flip_graph.cpp:120-139`); the default ring is `ZT` |
| start | seed scheme in MFW1, required; header shape must match; `n, m, p >= 2` (`wide_rect_walk.w:22-39`) | `.exp` file; the standard algorithm is `333-27-mod2.exp` for 3x3x3 (`main.cpp:48-57`) | `.exp` file (`main_mm.cpp:23-30`, `:48`) | naive scheme from `-n1 -n2 -n3`, or a file `-i` (`flip_graph.cpp:31-45`) |
| target rank | none; the walk runs a fixed number of proposals (the walker of metabench adds `--target`, `--trace`, `--cpu-budget` and leaves the walk unchanged) | none; ends at the first failed path (`main.cpp:67-81`) | none; ends at the first failed path (`tensor.cpp:202-228`) | `--target-rank`, tested after each round of `--flip-iterations` iterations of every runner (`flip_graph.hpp:154`) |
| input check | seed passes the full tensor gate (`wide_rect_walk.w:37-39`) | `check()` of the input (`main.cpp:54-57`) | `iscorrect()`, optional argument (`main_mm.cpp:52-55`) | Brent-equation check unless `--no-verify` (`flip_graph.cpp:34`) |
| size limits | multiword limbs, factors up to 1024 bits (`packed.w:5-16`) | one-digit dimensions, factors in one `unsigned long long`, at most `n*m*p` terms (`main.cpp:29-40`, `scheme.cpp:27`) | as km2022 (`main_mm.cpp:24-26`, `mm.cpp:14`) | matrices up to 256 elements (`utils.cpp:151-157`, `flip_graph.cpp:120-139`) |

## 2. Moves

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| flip | two terms equal in position `s`: first `R := R1+R2`, second `L := L1+L2` (`directed.w:288-293`) | same, `rows[r1][c] ^= rows[r2][c]; rows[r2][b] ^= rows[r1][b]` (`scheme.cpp:147-154`) | same (`tensor.cpp:89-94`) | same (`binary_scheme.hpp:1026-1028`) |
| choice of the flip | uniform legal bucket, then a uniform member, then a uniform equal-factor partner; orientation by which term is first (`directed.w:256-274`) | uniform over the list of all flips, both orientations of every equal-factor pair, resampled while equal to the previous flip (`randompath.cpp:434-435`, `:454-457`) | uniform over all equal-factor pairs of the three positions, orientation by a coin (`tensor.cpp:230-253`) | uniform over all equal-factor pairs of the three positions; two independent coins swap the roles of the other two factors and of the two terms (`binary_scheme.hpp:285-324`) |
| guard against undoing | nonbacktracking: a proposal that restores the current or previous state fingerprint is undone unless it reaches a new best rank (`directed.w:103-110`, `:317-356`) | the flip just made is not repeated (`randompath.cpp:454-458`) | none | none |
| rank-raising move | split: one term, one factor, one bit; the factor becomes the unit vector in one copy and its complement in the other (`directed.w:207-247`) | none | one plus transition before the walk: split of a random pair of terms along a random position, one flip, `split_distance` (10) flips without reduction checks; repeated while it ends in a reduction (`tensor.cpp:255-285`, `:205-207`) | plus (three terms replace two) or split, each with probability 1/2 (`binary_scheme.hpp:359-368`, `:1057-1103`) |
| when it is used | every 2000 proposals, when no legal pair exists, after 256 consecutive rejections; only while rank < best + 8 and a slot is free (`directed.w:363-364`, `:208`) | never | once, at the start, and only if rank < `n*m*p` (`tensor.cpp:205-207`, `:256`) | after a period drawn uniformly from 5K..100K flips since the last rank drop or plus, only while rank < the runner's best + 4 and rank < `n*m*p`; also whenever no flip exists (`flip_graph.hpp:309`, `:315-318`, `:340-343`, `binary_scheme.hpp:361-362`) |

The periodic plus of tfg corresponds to Algorithm 3 of Arai et al. (a plus after `L = 5*10^3` iterations without a reduction); tfg draws the
period from 5K..100K and alternates plus and split. km2024 applies one plus at the start of a run of the program only.

## 3. What is counted

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| unit of work | proposal: one call of `ffwd_one`; it can find no legal bucket, be accepted, or be rejected and undone (`directed.w:249-356`) | step: one iteration of the loop of `randompath`; it examines every flip of the scheme for an immediate reduction and then performs exactly one flip (`randompath.cpp:38-477`) | step: one `randomflip` (`tensor.cpp:211-218`) | iteration: one `tryFlip`, replaced by an expand move when no flip exists (`flip_graph.hpp:311-318`) |
| accepted moves | `accepted` counts accepted proposals (`directed.w:345`); splits are not counted | every step | every step | `flipsCount` counts flips since the last rank drop or plus (`flip_graph.hpp:327-332`); plus and split moves are separate |
| path | none: one walk of `STEPS` proposals | at most `PATH` steps from the start scheme or from the last reduced scheme; the counter restarts after each reduction (`main.cpp:67-81`) | as km2022 (`tensor.cpp:209-227`) | none: rounds of `--flip-iterations` iterations per runner, with counters kept between rounds |
| rank change per move | a flip lowers the rank by 0 to 4 through cancellation (`walker.tex:18-20`) | by 1 at the end of a path | by 1 per detected reduction | by 0 to 2 per flip through the checks of section 4 |

## 4. Reductions

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| mechanism | none apart from cancellation of equal terms and dropping of terms with a zero factor inside a flip (`scheme.w:66-112`, `walker.tex:18-21`) | exact: a set of terms with one common factor and dependent other factors (Gaussian elimination on the equal-factor group, `scheme.cpp:156-208`, `:275-348`) | two terms with two equal factors merge (`tensor.cpp:45-70`) | two terms with two equal factors merge (`binary_scheme.hpp:1106-1131`); zero factors are removed (`:922-926`) |
| when | as a by-product of a flip | (a) at the start of every path (`randompath.cpp:33-35`); (b) at every step, for every candidate flip, whether the flip would make the scheme reducible; if so that flip is performed followed by the reduction (`randompath.cpp:38-432`) | inside each flip, for the terms that newly share the flipped factor with the changed term (`tensor.cpp:97-124`) | inside each flip, for the same terms (`binary_scheme.hpp:1039-1053`); a full scan with probability `--reduce-probability`, default 0 (`flip_graph.hpp:321`) |
| fingerprint / hash | 63-bit XOR fingerprints, heuristic (`directed.w:74-110`) | hash maps from factor to term (`randompath.cpp:24-30`) | vector of pairs per position, exact (`pairSet.cpp`) | vector of pairs per position, exact (`flip_set.cpp`) |

## 5. Restarts, limits and populations

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| restart | none in a walk (one walk per process) | with `tries = 1` the program continues from every reduced scheme and exits at the first path of `PATH` steps without reduction; with `tries = 0` it runs one path (`main.cpp:67-81`) | `restart = 1`: as km2022; `restart = 0`: stops at the first reduction (`tensor.cpp:209-227`) | rounds continue where they stopped; after a new global best each other runner adopts it with probability `--copy-best-probability` (0.5); after `--reset-iterations` (10B) iterations without a best a runner restarts from one of the last `--max-improvements` (10) improvements (`flip_graph.hpp:214-245`, `:345-353`) |
| path length / budget | `STEPS` proposals in total (campaign: 40M, 100M or 200M) | `PATH` steps per reduction (paper: 10^7 for single walks on 3x3x3; 10^6 in the pool method, Sect. 4-5) | as km2022 | none |
| slack above the best rank | +8 (split only) | none: the rank never rises | the start split adds one | +4 above the runner's best (`--plus-diff`) |
| population | one walker | one walker (the paper's pool method, Algorithm 2, is a driver around the program and is not in the repository) | one walker; the patch adds Algorithm 2 as an option (`KM_POOL`, off by default) | `--count` runners (default 128) advanced in rounds; with one thread they run one after the other |
| pool mode | none | none | none | `--use-pool` keeps a pool of schemes per rank (`flip_graph_pool.hpp`); not used here |

## 6. Randomness

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| generator | 63-bit linear congruential generator, top 31 bits, multiply-shift range reduction (`scheme.w:31-34`) | C library `rand()`, `srand(seed)` at the start of every path, remainder for the range (`randompath.cpp:23`, `:454`) | `std::mt19937` with `uniform_int_distribution` (`main_mm.cpp:61-67`, `tensor.cpp:203-204`, `:233`) | one `std::mt19937` per OpenMP thread, seeded through `seed_seq` from a master `mt19937(seed)`; remainder of the raw output for the flip index (`utils.cpp:161-172`, `flip_graph.hpp:85`, `binary_scheme.hpp:291`) |
| seed | the nonce, initial state of the generator (`wide_rect_walk.w:42`) | nanoseconds of `CLOCK_MONOTONIC` (`main.cpp:59-61`) | tenth argument, else `std::random_device` (`main_mm.cpp:61-67`) | `--seed`; 0 means the time (`flip_graph.cpp:72-73`) |
| reproducible | yes, a function of shape, seed bytes, proposals, nonce | only with the seed hook of the instrumentation patch | yes with the seed argument | yes with `--threads 1`: all runners draw from the generator of thread 0 |

## 7. Process structure and output

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| parallelism | one thread, no clocks or environment reads (`walker.tex:70-71`) | one thread | one thread | OpenMP over runners; run here with `OMP_NUM_THREADS=1 --threads 1` |
| ends | after `STEPS` proposals | at the first failed path | at the first failed path or when no flip exists | when the best rank is `<=` the target after a round, else never |
| writes | the best scheme by (rank, density), canonical MFW1, and one summary line with `moves`, `accepted`, `no_pair`, `escapes` (`wide_rect_walk.w:61-70`) | on exit, if at least one step was reduced: `j<hash>.exp` in the working directory, one log line in `j00.log`, and `name,rank` on stdout (`main.cpp:104-109`, `scheme.cpp:212-230`) | on exit, always: `k<hash>.exp`, `k00.log`, `name,rank` (`tensor.cpp:157-176`, `:195-200`) | a report table per round; every new best is validated and saved as `NxMxP_m<rank>_c<complexity>_iteration<k>_Z2.txt` (`flip_graph.hpp:214-245`, `:248-305`) |
| progress before the end | none | none | none | per round |

## 8. Measured cost per step

Instructions retired per step of one process on the M5 Max (`/usr/bin/time -l`), all four starting from the same rank-23 scheme of
3x3x3 (a hit of the pilot), clang 23.1.0 `-O3`:

| | metaflip | km2022 | km2024 | tfg |
| --- | --- | --- | --- | --- |
| step | proposal | step | step | flip |
| instructions per step | 2,460 (accepted 89%) | 6,850 | 750 | 754 |

A step is not the same amount of search in the four programs: one km2022 step scans the whole neighbourhood for a reduction,
one metaflip proposal chooses among legal buckets, and one km2024 or tfg step draws one pair (section 2).

## 9. What the adapters add

| | km2022 | km2024 | tfg |
| --- | --- | --- | --- |
| start | `start.mfw` converted to `.exp` | same | converted to the tool's text format, read with `-i` |
| stop at target | environment `KM_TARGET_RANK` (patch) | same | patch: the round ends at the target |
| CPU budget | `setitimer` in the program (patch) | same | same |
| restarts | a new process with the next seed when a walk fails: from the start scheme (default) or from the scheme the walk ended on | the same inside the process (`KM_LOOP`, patch) | none: the process runs until the target or the budget |
| counters | steps taken; trace at every new best rank | same | flips, iterations and plus/split moves over all runners |
| output | also writes the scheme when every reduction took zero steps (patch) | unchanged | unchanged |

## 10. Conditions held equal by the harness

* Same task, start scheme file, target rank and seed sequence for every algorithm; the start scheme is converted without loss and the third factor transposed exactly (`adapters/README.md`).
* One thread; the CPU seconds of the program (user + system) and its retired instructions are measured by the harness's meter
  (`mb_measure`), the same budget applies to every algorithm, and a hit counts only if the returned scheme passes the independent
  exactness verifier.
* The three baselines are compiled from the pinned commits with Homebrew clang 23.1.0, `-O3 -flto -mcpu=apple-m5` (`PINS.md`).

Not equalised: the move set and the proposal distribution (section 2), the reduction checks (4), rank slack and restarts (5), the
generator (6), and the cost of a step (8). The tfg population (`--count`) and the km2022/km2024 path length are parameters of the
programs that the sweeps vary.
