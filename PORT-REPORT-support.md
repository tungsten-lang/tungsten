# PORT-REPORT-support: support libraries for the Tungsten port of the GF(2) toolchain

Branch `port/support` (worktree `/Users/erik/tungsten-mf-port-support`). Everything is under `bits/tungsten-metaflip/`:
seven library modules in `lib/metaflip/gf2/`, one test program with its case files and Python/Ruby-made goldens, and
`PORT-BLOCKERS.md` at the worktree root. `core/`, `compiler/`, `runtime/` and the shared checkout were not touched.
Nothing outside the listed paths changed (`git status` clean after the commit).

Provenance: I wrote `floatx.w`, `jsonx.w` and the harness; three helper agents built `fsx.w` + `gitx.w` + `procx.w`, `cli.w`, and
`textx.w` from my design; I reviewed them, wired the float parts into `textx.w`, and re-ran every headline check myself.

The requirements come from a survey of 32 originals (12 tools, 13 campaign drivers, 7 paper scripts; 5,423 lines of Python)
that use, in total: 105 `json` calls, 93 `argparse` calls, 23 `subprocess` calls, 97 `sorted`/`sort`, 39
`Counter`/`defaultdict`/`setdefault`, 11 `csv` calls, 23 `glob`/`rglob`, 22 `mkdir`/`makedirs`, 10 `tempfile`, plus
f-string/`%` formats, `zlib.crc32`, `statistics.median`, and Ruby's `JSON.pretty_generate` (`verify_tensor.rb`).
Each module's header says which originals need which function; nothing speculative was added except where the brief names
it (`zero_pad`, `pad_right`, `max_by`, flagged in `textx.w`). Beyond the brief's file list: `floatx.w` (jsonx and textx need
exact float digits), `procx.w` (gitx needs status/stderr capture) and `Procx.run_all` (five surveyed tools run subprocesses
from a `ThreadPoolExecutor`).

## Files

| file | lines | what |
|---|---|---|
| `lib/metaflip/gf2/floatx.w` | 416 | exact IEEE-754 double <-> decimal: Python `repr`, `%.Nf`, `%g`, `%`-percent, `round`, `float()`, `int / int` |
| `lib/metaflip/gf2/jsonx.w` | 584 | `json.loads` (strict, Python's error messages), `json.dumps` (indent, sort_keys, separators, ensure_ascii), Ruby `JSON.pretty_generate`, JSON Lines, `release` |
| `lib/metaflip/gf2/textx.w` | 842 | `f"{x:>10}"`, `:,`, `:+d`, `%x`, `int(s, 16)`, `repr(str)`, `splitlines`, `split()`, stable `sorted(key=, reverse=)`, `min/max(key=)`, `median`, `Counter`, `defaultdict`, `crc32`, `csv` with tab (reader, DictReader, writer) |
| `lib/metaflip/gf2/fsx.w` | 488 | pathlib/`os.path` arithmetic, `glob`/`rglob`/`walk` in `sorted(Path)` order, `mkdir`, atomic write, append, `resolve`, temp dirs |
| `lib/metaflip/gf2/gitx.w` | 171 | `git -C repo` `ls-tree`, `show`, `rev-parse`, `cat-file`, `log -1`; `GIT_NO_LAZY_FETCH=1` unless asked otherwise |
| `lib/metaflip/gf2/procx.w` | 221 | `subprocess.run/check_output` (status, stdout, stderr, cwd, env), shell-safe quoting, bounded-parallel `run_all` |
| `lib/metaflip/gf2/cli.w` | 889 | argparse: options, flags, append, `nargs`, choices, exclusive groups, subcommands, usage/help text, exit 2 |
| `spec/gf2_support_test.w` | 38 | the test program (runs the six case files) |
| `spec/gf2_support/{check,floatx_cases,json_cases,textx_cases,fsx_cases,gitx_cases,cli_cases}.w` | 1,967 | test harness and cases |
| `spec/gf2_support/json_bulk.{w,py}`, `json_bench.{w,py}` | 137 | bulk parity and timing programs (Tungsten and Python sides) |
| `spec/fixtures/gf2_support/**` | 52 files, 1.53 MB (largest file 121 KB) | goldens made by Python 3.14 / Ruby 4.0 and the scripts that regenerate them (`gen_*_goldens.py`, `classify_release_json.py`, `clone_fingerprint.py`) |
| `PORT-BLOCKERS.md` | | 15 sections with verified minimal repros |

The libraries are about 3,600 lines, the tests and generators about 3,700 lines.

## Porting cheat sheet

| Python / Ruby idiom in the originals | Tungsten |
|---|---|
| `json.loads(p.read_text())`, `json.loads(line)` | `Jsonx.load(path)`, `Jsonx.loads(text)`, `Jsonx.loads_lines(text)` |
| `json.dumps(x, indent=1) + "\n"`, `json.dumps(row)` | `Jsonx.dumps(x, indent: 1) + "\n"`, `Jsonx.dumps(row)`; also `sort_keys:`, `separators: [a, b]`, `ensure_ascii:` |
| `open(log, "a").write(...)` | `Fsx.append(path, text)` |
| `JSON.pretty_generate(x)` (verify_tensor.rb) | `Jsonx.pretty_generate(x)` (floats refused) |
| `repr(x)`, `f"{x:.2f}"`, `f"{x:g}"`, `f"{x:.1%}"`, `round(x, 2)`, `float(s)`, `a / b` on ints | `Floatx.repr/fixed/general/percent/round/parse/ratio` (also `Textx.fixed/general/percent/round/parse_float`) |
| `f"{v:>10}"`, `f"{n:,}"`, `f"{n:+d}"`, `"%x" % n`, `int(s, 16)`, `f"{s!r}"` | `Textx.pad_left/thousands/signed/hex/parse_hex/repr_str` |
| `s.split()`, `s.splitlines()` | `Textx.words`, `Textx.splitlines` |
| `sorted(xs, key=..., reverse=...)`, `min(xs, key=)`, `Counter`, `.most_common()`, `defaultdict(list)`, `statistics.median`, `zlib.crc32` | `Textx.sort_by/sorted/min_by`, `tally`, `most_common`, `group_by/push_to/add_to`, `median`, `crc32` |
| `csv.reader / DictReader / writer(delimiter="\t")` | `Textx.tsv_rows / tsv_records / tsv_text` |
| `Path.glob/rglob`, `glob.glob`, `sorted(Path...)` | `Fsx.glob/rglob/walk/sort_paths` (pathlib order) |
| `mkdir(parents=True, exist_ok=False)`, `os.makedirs`, `os.replace`, tmp+rename | `Fsx.mkdir(path, parents: true)`, `mkdir_p`, `replace`, `atomic_write` |
| `Path.stem/suffix/parent/parts/relative_to/resolve`, `os.path.join/basename` | `Fsx.stem/suffix/parent/parts/relative_to/resolve/join/basename` |
| `tempfile.TemporaryDirectory()` | `Fsx.with_tempdir -> (dir)` |
| `subprocess.run(argv, capture_output=True, text=True)` | `Procx.run(argv, cwd:, env:)` -> `status`, `out`, `err`; `Procx.check_output` |
| `ThreadPoolExecutor` over subprocesses | `Procx.run_all(jobs, limit: n)` |
| `git -C c ls-tree -r --name-only R path`, `show R:p`, `rev-parse`, `log -1 --format=` | `Gitx.new(c).ls_tree(R, path)`, `.show(R, p)` (nil when the blob is not local), `.rev_parse(R)`, `.log1(R, fmt)` |
| `argparse.ArgumentParser` | `Cli.new(prog, description:)`, `.add("--x", type: :int, default: 3)`, `.exclusive`, `.subcommands`, `.parse(argv())` -> Hash |

Two rules for tool authors. Arithmetic that must reproduce a Python float has to run on Floats (`~0.1`, `Floatx.of(x)`),
not on Decimals: `0.1 + 0.2` is exactly 0.3 in Tungsten. And a tool that takes `--flags` must be started as
`bin/tungsten run tool.w -- --flags` (the launcher swallows `-h`, `--help`, `-v` and unknown flags placed after the `.w`
file) or built with `-o`.

## Parity evidence

Oracles: Python 3.14.7, Ruby 4.0.6. "n of n" means n agree of n compared. Reproduce with
`export BIT_HOME=$PWD/bits GIT_NO_LAZY_FETCH=1; bin/tungsten bits/tungsten-metaflip/spec/gf2_support_test.w`
(`GF2_VERBOSE=1` prints every check label and the seconds per section).

**jsonx / floatx** (larger runs: `python3 spec/fixtures/gf2_support/json/gen_json_goldens.py DIR 20000 4242`, then
`GF2_JSON_GOLDENS=DIR GF2_VERBOSE=1 bin/tungsten spec/gf2_support_test.w`)

| check | result |
|---|---|
| every JSON/JSONL file of `work/release-0929/` re-dumped with the settings Python's own file needs | 73 of 73 files (47 JSON, 26 JSONL); 7,720 of 7,816 JSONL lines round-trip, exactly the lines that round-trip in Python |
| the four bundle manifests (`dumps(indent: 1) + "\n"`) and `comparators.json` (`dumps(indent: 1)`) are byte-identical to the files on disk | 5 of 5 |
| 6 option sets (default; `indent 1`; `indent 2 + sort_keys`; compact separators + `ensure_ascii false`; `indent 4 + utf8 + sort_keys`; tab indent) on random nested structures (ints to 2^200 and the 2^47/2^63/2^64 edges, random-bit-pattern floats, NaN/inf, quotes, controls, DEL, Latin-1, CJK, astral, lone surrogates, NUL, empty containers, depth 9) | 2,000 of 2,000 per set; 20,000 of 20,000 per set in a second run; 3,000 of 3,000 in a third |
| Ruby `JSON.pretty_generate` on the same structures | 13,399 of 13,399 comparable structures of 20,000 (3,813 hold floats and are refused) |
| parser differential: randomly spelled documents (odd whitespace, `\u` escapes of letters, exponent spellings) and the same with one character deleted/inserted/replaced; value or exact error message and position | 150,000 of 150,000 (49,104 malformed) (`gen_json_goldens.py DIR 3000 99 150000`); 20,000 of 20,000 in the other run; 87 hand-written cases (all of Python's error texts) |
| FMM scheme tree `work/upstream-latest/fmm-tree-ac13ca8855` (2,681 files, 1.81 GB): sha256 of `dumps(loads(file))` | 2,681 of 2,681 |
| the remaining JSON on the machine (`work/*.json`, extracted 10 MB catalogs, `mmc-cache`, `release-0929`): same digest | 422 of 422 |
| `verify_tensor.rb` output for a real 12x16x27 tensor read back and re-generated | byte-identical |
| floats: `repr`, `%.Nf` (5 precisions), `%g` (4), `.N%` (2), `round(x, 2)` | 32,859 doubles (random bit patterns, powers of two and their neighbours, powers of ten, subnormals, edge values) plus 4,000 over the full exponent range: 0 differences |
| decimal text -> double (halfway cases, subnormals, 400-digit inputs, underscores, whitespace, `inf`, `nan`, refusals) | 124,601 of 124,601 |
| Ruby `Float#to_s` (implemented once, dropped when `pretty_generate` had to refuse floats) | 38,350 of 38,350 |

What was wrong with core's `JSON.parse` (details and repros in `PORT-BLOCKERS.md` section 8): on 87 documents with known
Python results it agrees on 63. It does not decode `\uXXXX`, `\b` or `\f`, accepts invalid escapes, raw control characters,
leading zeros and trailing garbage, rejects `NaN`/`Infinity`, and reports no positions. Integers of any size, key order,
duplicate keys and the double of every float (122,740 decimals) were right and are kept.

**textx** (committed cases 1,431 formats, 2,545 `repr_str`, 478 split, 75 crc32, 484 sorts, 322 counting, 847 csv)

* the same generators at 15x and 25x scale (seeds 7, 424242): 10,758 / 17,437 format cases, 4,387 / 5,717 `repr_str`,
  6,638 / 11,038 split, 915 / 1,515 crc32, 1,815 / 3,025 sorts, 3,949 / 6,549 tsv reads, 4,200 / 7,000 tsv writes, all agree
  (`TEXTX_GOLDEN_SCALE=15 TEXTX_GOLDEN_SEED=7 python3 gen_textx_goldens.py DIR`);
* real data: 75 of 75 TSV files (`records.tsv`, the 16 `paper-data/*.tsv`, the benchmark TSVs; 2,641,547 bytes, 29,330 rows)
  read identically to Python's `csv`; all 75 re-emit byte-for-byte (`records.tsv` with its CRLF); 3,768 of 3,768 seed shape
  strings give Python's `zlib.crc32` and `% 1000003`; 200 of 200 random byte strings (NUL included, 3.2 MB) and 50 MB agree.

**cli** (`gen_cli_goldens.py`: 13 parser shapes, nine copied from the originals; real argparse is the oracle for the
Namespace, or the exact usage + error text, or the help text)

* 202 of 202 committed argument vectors; scratch runs (seeds 3, 7, 11, 21, 22): 47,214 of 47,214 more vectors,
  2,305 of 2,305 textwrap cases, 956 usage/help renderings at widths 14-200;
* end to end: a compiled program declaring `gf2_record_board.py`'s whole option set prints the same Namespace as Python for
  `--lille L --witness a --witness b --jobs 3 -v`; exit status, stdout and stderr agree on 8 argument vectors.

**fsx** 2,162 of 2,162 pure-path checks (parts, name, parent, stem, suffix, joins, `relative_to`, `parents[n]`, `abspath`,
fnmatch) agree with pathlib/`os.path`; 58 of 58 glob goldens (dotfiles, spaces, unicode, symlink to a directory, dangling
link, link loops); 31 of 31 `resolve()` goldens; 13 of 13 real-tree globs (7,240 `*_mfw/*.mfw`, 2,681 `**/*.json`).

**gitx** on the pinned clones under `work/upstream/` (blob-less partial clones):

* `ls_tree('613599b6c35159b2dcc6749574152eee89518998', 'schemes')` on `upstream/fmm`: 6,410 names, identical in order and
  count to Python's `subprocess.check_output([... 'ls-tree', '-r', '--name-only', rev, 'schemes']).split()` (sha256 of the
  joined list `6ad5e58b...` on both sides; I re-ran this myself after the fork's run);
* 8 of 8 `ls_tree` listings (fmm whole tree 6,440, `schemes/known` 1,718, mmc 11,125 and 11,920, merlijn 32 and 25,
  fmm_digest 3) and 36 of 36 `rev_parse` / `log1` (`%H`, `%h %ci`, `%aI`, `%s`) / `show` comparisons identical, including a
  byte-exact 10,675,245-byte `docs/catalog.json`; a blob that is not local gives `nil` (Python: rc 128) without fetching;
* no fetch, no new object (see the incident below for the one exception): `clone_fingerprint.py` (sha256 over path, size,
  mtime of every file under `.git`) equals its pre-session value for all four clones today: fmm `4c1496e6...` (60 object
  files, 15 packs, 1,555 in-pack, newest object 2026-09-29 09:55:03), mmc 126 / 31 / 3,661, merlijn 14 / 1 / 35,
  fmm_digest 3 / 1 / 5; `git count-objects -v` equals the pre-session output; promisor settings untouched.

**Incident.** While mutation-testing the git cases, the helper agent that built gitx ran the real-clone cases against
`upstream/fmm` with lazy fetch forced on. That downloaded 2 blobs from the network (8 files: 2 packs with
`.pack .idx .rev .promisor`). It deleted exactly those 8 files and its fingerprint matched the baseline again; I re-checked
all four clones afterwards (numbers above). The committed cases now
refuse any `Gitx` that could fetch when they touch a real clone, export `GIT_NO_LAZY_FETCH=1` around the block and assert that
no pack file appeared; the only committed use of `lazy_fetch: true` is against a throwaway clone created inside the test.

## Timings

Compiled `--release` against Python 3.14, same inputs, medians (the machine was shared: load average 17-27).

| task | Python | Tungsten | |
|---|---|---|---|
| `loads` mmc_catalog_0929.json (10.7 MB, 9,556 schemes), median of 3 x median of 5 | 44.8 ms | 25.4 ms (core `JSON.parse`: 127.4 ms) | 1.8x faster than Python, 5.0x than core |
| 67 FMM scheme files (41.6 MB) | 0.353 s | 0.116 s (core: 1.554 s) | 3.0x, 13.4x |
| 2,681 FMM scheme files (1.81 GB), parse only: best of runs (quiet machine) / median of 4 Python and 6 Tungsten runs (load 17-27) | 14.7 s / 21.5 s | 5.1 s / 5.7 s | 2.9x / 3.8x faster |
| same files, `dumps` (default separators): best / median | 7.4 s / 10.9 s | 11.2 s / 12.1 s | 1.5x / 1.1x slower |
| `dumps(indent=1)` of the catalog (10.4 MB) | 27.7 ms | 38.7 ms | 1.4x slower |
| `dumps` of the catalog (default separators) | 26.2 ms | 34.6 ms | 1.3x slower |
| 200k random floats: `loads` / `dumps` | 0.031 s / 0.060 s | 0.267 s / 1.471 s | 9x / 25x slower |
| `Floatx.repr`, 350 doubles | 0.2 ms | 2.3 ms | 12x slower (about 6 us per double) |
| `tsv_rows` x100 on `records.tsv` (167 KB) / `tsv_records` / `tsv_text` | 0.100 / 0.145 / 0.150 s | 0.041 / 0.072 / 0.159 s | 2.4x / 2.0x faster / 1.06x slower |
| `splitlines` x100 / `words` x100 | 8.8 / 18.7 ms | 12.1 / 40.5 ms | 1.4x / 2.2x slower |
| `crc32` of 50 MB | 1.22 ms | 4.77 ms | both hardware CRC |
| `sort_by` 100k rows, tuple keys / reverse int key | 0.061 / 0.011 s | 0.102 / 0.035 s | 1.7x / 3.2x slower |
| `tally` of 1M strings | 0.030 s | 0.055 s | 1.8x slower |
| `git rev-parse` x400 / `ls-tree schemes` x40 (6,410 names) / `show README.md` (112 KB) x150 | 22.3 / 27.1 / 46.2 ms per call | 27.7 / 30.6 / 39.2 ms | 1.24x / 1.13x slower / 0.85x |
| glob 2,681 files (`**/*.json`) / 7,240 (`*_mfw/*.mfw`) | 0.020 / 0.037 s | 0.076-0.106 / 0.11 s | 4-5x / 3x slower |

The git calls pay for the extra `/bin/sh` that `capture` starts (5-7 ms). Floats are the slow spot: `Floatx` is exact BigInt
arithmetic, and no surveyed original moves more than a few thousand floats. The JSON reader is typed (`u8[]` view, `## i64`
cursor, no per-value allocation); the rest is library code without special tuning.

## Tests

| test | engine | runtime | suggested shard |
|---|---|---|---|
| `spec/gf2_support_test.w` (3,156 checks) | compiled only: list it in `native_tests.txt` with reason `native` | warm 15-19 s (floatx 0.01, jsonx 0.1-0.2, textx 0.01, fsx 2.7-3.6, gitx 7-11, cli 1.5-1.7 s); cold with empty caches about 90 s (compile) | native |

It cannot run under `run --interpret`: it needs `wvalue_bits`, methods that yield, `Process.spawn`, and the interpreter cannot
box negative doubles (`PORT-BLOCKERS.md` section 12). I did not touch `interpreted_tests.txt` / `native_tests.txt`;
`spec/metaflip_test_manifest_spec.w` will list `spec/gf2_support_test.w` as unclassified (expected).
It passes from a clean `git archive` extraction of the commit with empty caches (3,156 of 3,156, with `TUNGSTEN` set as the
root gate does; the process cases fall back to `<repo>/bin/tungsten` like `metaflip_unit_harness.w`), and as a
`tungsten -o ... --release` binary (3,156 of 3,156, 23 s).

Environment (all optional): `GF2_JSON_GOLDENS=DIR` larger JSON goldens; `GF2_RECORD_HUNT_WORK` (default
`~/.tungsten/metaflip/experiments/record-hunt-20260926/work`) enables the real-data cases (release tree, `records.tsv`, git
clones, real globs), which skip when the directory is absent; `GF2_RELEASE_DIR`; `GF2_CLI_GOLDEN=DIR`; `GF2_SUPPORT_FIXTURES`;
`GF2_VERBOSE=1`. Mutation checks done by the helper agents: a plain string sort in `sort_paths` (13 failures), a wrong stem
rule (79), the no-fetch variable dropped from a clone copy, a corrupted argparse golden: the cases failed each time.

## Deviations from the originals (and why)

* `Jsonx.pretty_generate` refuses floats: the json gem prints them with its own shortest-digit printer, which differs from
  `Float#to_s` in the last digit for 0.6% of floats (1,130 of 189,499 plain-notation floats checked against Ruby); the verifier prints none.
* `Jsonx.loads` raises `JsonError` (message and position as Python's `JSONDecodeError`), does not validate UTF-8 (Python did
  when reading the file), stops at nesting depth 1000 like Python's recursion limit. `dumps` refuses invalid UTF-8 only when
  `ensure_ascii` has to decode it. A lone `\ud800` round-trips as its three-byte form.
* `Gitx#ls_tree` returns exact names (git's C-quoting undone) where Python's `.split()` cuts at spaces; `show` answers `nil`
  where Python raises (`show!` raises); `rev_parse` uses `--verify`. The pinned clones have no such names.
* `Procx`: text only (a NUL in stdout is reported through `truncated?`, `stdout_to:` is the escape), stdin is `/dev/null`, a
  killed child reports 128 + signal (Python: -signal).
* `Fsx` follows pathlib 3.14 rules (`**` as the last component matches files, character sets refused); `write` returns bytes.
* `Cli`: no prefix abbreviations of long options (`allow_abbrev=False`), no `set_defaults(func=)` (dispatch on
  `args["command"]`), help strings used verbatim, help width `$COLUMNS` else 80, exit status 2 for `optparse` usage errors
  (Ruby's exited 1). `try_parse` returns `[args, error_text, help_text]`.
* `Textx`: `splitlines` uses Python's full separator set; `tsv_records` skips blank lines before the header and refuses a row
  longer than the header (DictReader files the extras under `None`); `sort_by` and `sorted` refuse Decimal keys, and the
  counting helpers refuse Array keys, rather than miscount silently (PORT-BLOCKERS 1 and 13).
* Output that Python does with C speed is slower here for floats, `words`, sorts with tuple keys and `tally` (table above).

## Blockers and workarounds

Nothing is blocked. `PORT-BLOCKERS.md` holds 15 sections, each with a repro that was run: Decimal ordering (sort/min/max),
`*rest` with keyword arguments, an optional parameter before `&` on instance methods, typed instance-method self-calls,
`String#to_i(16)` saturating at 2^63, method names `string`/`int`/`bool`/`integer` hijacked, NUL handling (`chr(0)`,
`<=>`), core `JSON.parse` defects, a parenthesised ternary before `+`/`-` (silently drops `- 2`), bare `return if`, nine or
more parameters, interpreter differences, closure parameter corruption in `if/else`, a segfault on an unbound bracket in a
string, missing call-site splat, and unwired `File.basename/dirname/extname/realpath/readlink/symlink/file?/open`. Each is
avoided by API design or carries a `# TODO(port)` marker (`fsx.w`, `procx.w`). No language or stdlib bug was patched.

## Things the integrator must do or know

* `spec/runtime_manifests_test.w` now fails with 14 problems (7 new `.w` files missing from `lib/metaflip/SHA256SUMS` and
  `manifests/runtime-sources.tsv`). I deliberately did not run `tools/regen_manifests.w`: every porter branch would edit the same
  two generated files. Run it once after the merges.
* `use` paths from a tool: `use ../lib/metaflip/gf2/jsonx` (the libraries `use` their siblings; diamonds are fine).
* There is no garbage collector: a parse result is never freed. A tool that walks many big files calls
  `Jsonx.release(tree)` and frees its own input and output strings (peak RSS over the 1.8 GB tree: 6.4 GB with no frees,
  433 MB with them).
* Regex is not covered by any support library and the compiled engine's regex is thin: `\d` and `\w` never match, `(?:...)`
  is rejected, `String#match` is undefined; `[0-9]` classes, capturing groups, alternation and optional groups work
  (`PORT-BLOCKERS.md` section 13). The originals' name patterns (`RING`, `SCHEME`, `FNAME`, lineage references) must be
  rewritten with `[0-9]` and capturing groups.
* `raise "text"` raises a bare String without `.message`; the libraries raise `JsonError`, `FloatxError`, `TextxError`,
  `FsError`, `GitError`, `ProcError`, `CliError` (all `Error` subclasses).
