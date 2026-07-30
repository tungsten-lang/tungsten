# Wassat vs. Green LymphoSAT specialists, 2026-07-29

This is a narrow same-host comparison of the two structured SAT families used
to evaluate Wassat's Hantzsche--Wendt and knight-tour recognizers. It is not a
whole-corpus SAT Competition result.

## Method

- Host: Apple M5 Max (arm64), 128 GiB, macOS 26.6 (25G72).
- Background load: two unrelated CaDiCaL processes each occupied one core
  throughout. Results are therefore suitable for this interleaved comparison,
  not as unloaded absolute timings.
- Timing: one unreported warm-up, then eleven samples per solver and formula.
  Solver order alternated on every repetition. Wall time includes DIMACS
  parsing and SAT-model formatting; stdout was redirected to `/dev/null`.
- Wassat: release/LTO/fast binary, SHA-256
  `a77bca7aeec6010f3900e7e7e7fc6c9e0ec88dff51b76711e1f8a7a727b1e1ca`.
- Green source archive: SHA-256
  `7bc2ad3278197261cee221fd8c2dd583069821213f31d63e6873495000713c70`.
  The relevant direct specialist sources were compiled with Apple clang 21 as
  C++20 using `-O3 -mcpu=native -DNDEBUG -pthread`. This excludes Green's
  matcher-process overhead and is deliberately favorable to Green.
- Green algebra specialist: SHA-256
  `ed16b817d8a8e1f0e188edbdbfec46a6ca86af720f8f024c95c3c7ea644ab898`.
- Green knight specialist: SHA-256
  `d100218ce68c789262f104f46edd052414e4ea69ca651c14fe537d5b283dc1a9`.

## Results

| Formula | Wassat median | Green median | Wassat speedup | Wassat max RSS | Green max RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `hantzsche_wendt_unit_93.cnf` | 15.606 ms | 33.015 ms | 2.116x | 45,121,536 B | 34,963,456 B |
| `knight_18.cnf` | 214.019 ms | 644.042 ms | 3.009x | 457,785,344 B | 106,446,848 B |

The Hantzsche--Wendt CNF has SHA-256
`e3bd4301dbdc0441dd1eb14fd3caba3da69f6d0c756d3f57fc36454ad030c360`;
the knight-tour CNF has SHA-256
`0178c7cef0b660c4abf8272dce88305bd4bc75878906442f21b25b908225198d`.

Wassat's outputs passed the strict competition-output checker and satisfied
every original clause. Green's direct specialists returned complete models
(12,168 and 126,152 literals respectively), and those models independently
satisfied every original clause. Their direct `v` lines are longer than the
4096-character competition limit; the top-level Green wrapper was intentionally
not included in this specialist-only timing.

## Raw timing samples (milliseconds)

- Hantzsche--Wendt Wassat: 14.613, 16.358, 14.804, 15.759, 15.869,
  16.000, 15.374, 15.606, 15.535, 16.026, 15.423.
- Hantzsche--Wendt Green: 32.222, 34.839, 33.702, 33.802, 32.422,
  34.056, 31.883, 33.804, 33.006, 33.015, 32.997.
- Knight-tour Wassat: 214.831, 206.811, 215.606, 214.019, 221.274,
  194.775, 181.766, 197.611, 220.572, 214.056, 198.648.
- Knight-tour Green: 644.760, 652.281, 712.848, 700.400, 642.629,
  629.587, 610.651, 599.008, 644.042, 648.639, 614.301.

The maintained pre-commit gate passed against the measured Wassat binary:
all library specifications, the same seeded 200-case differential corpus in
default and raw-zero modes, and the `php87` UNSAT proof checked by a freshly
built WRAT.
