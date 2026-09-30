#!/usr/bin/env python3
"""Parity of the Tungsten tensor verifier with its Ruby and Python originals.

The three implementations under test, all reading the same certificate files:

  ruby     tools/verify_tensor.rb    dense-table gate, lenient certificate formats
  python   read_blob + exact         sparse gate, strict canonical MFW1
             (spec/wide_matrix_cleanup_parity_test.py, packed_composition_parity_test.py)
  tungsten tools/verify_tensor.w     default = the Ruby rules; --strict = the Python rules;
                                     --gate dense|sparse|both

Sub-commands:

  corpus   every tensor of a corpus directory (corpus.tsv + mfw/<sha256>.mfw): the Ruby record,
           the Python record and the Tungsten records (one --batch process per gate/mode) must be
           identical (exact, shape, rank, density, sha256; the path aside).
  mutate   a sample of the corpus is mutated several ways; Ruby, Python and Tungsten (default and
           --strict) must agree on accept/reject wherever the originals agree with each other, and
           the deliberate strictness differences of the originals must be reproduced (Tungsten
           default == Ruby, Tungsten --strict == Python) on every case.
  time     wall-clock and CPU time of the three implementations on the same files: whole corpus
           (Ruby and Python once, sequentially; Tungsten one --batch process, median of --runs) and
           per-invocation cost of single certificates (median of --runs).
  parse-fuzz  the strict MFW1 reader alone (spec/gf2_scheme_parse_parity.w) against read_blob on thousands of
           damaged canonical files: identical accept/reject, identical rank and digest on accepts, except for
           the documented deviations (negative numbers, non-positive dimensions, rows with other than three fields).
  fuzz     thousands of randomly damaged certificate texts (whitespace of every kind, NUL, tokens,
           lines, case, headers, formats): Tungsten's default mode must reproduce Ruby's exit status,
           records and failure messages byte for byte, and --strict must reproduce Python's verdict.

  verify_tensor_parity_test.py corpus --corpus DIR --binary verify_tensor [--out DIR] [--jobs 3]
  verify_tensor_parity_test.py mutate --corpus DIR --binary verify_tensor --samples 210 [--seed 1]
  verify_tensor_parity_test.py fuzz   --corpus DIR --binary verify_tensor --cases 4000 [--seed 1]
  verify_tensor_parity_test.py time   --corpus DIR --binary verify_tensor [--runs 3] [--skip-corpus]
  verify_tensor_parity_test.py parse-fuzz --corpus DIR --parse-binary gf2_scheme_parse_parity [--cases 20000]
"""
import argparse
import concurrent.futures as futures
import csv
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TOOLS = HERE.parent / 'tools'
sys.path[:0] = [str(HERE), str(ROOT / 'benchmarks/matmul/metaflip')]

RUBY = TOOLS / 'verify_tensor.rb'
FIELDS = ('exact', 'shape', 'rank', 'density', 'sha256')


def load_read_blob():
    from wide_matrix_cleanup_parity_test import blob, read_blob
    from packed_composition_parity_test import exact
    return blob, read_blob, exact


# ----------------------------------------------------------------------------- corpus

def entries(corpus):
    """(path, shape) per corpus row; the shape is the one in the file header."""
    rows = []
    with open(Path(corpus) / 'corpus.tsv') as handle:
        for row in csv.DictReader(handle, delimiter='\t'):
            path = Path(corpus) / 'mfw' / (row['sha256'] + '.mfw')
            with open(path, 'rb') as stream:
                header = stream.readline().split()
            rows.append((str(path), 'x'.join(part.decode() for part in header[1:4])))
    return rows


def python_verdict(path, expected_shape):
    """read_blob + exact, as the Python tooling combines them; None on rejection."""
    blob, read_blob, exact = load_read_blob()
    raw = Path(path).read_bytes()
    try:
        shape, terms = read_blob(raw)
        assert 'x'.join(map(str, shape)) == expected_shape
        exact(shape, terms)
    except Exception as error:  # every rejection is an assertion or a parse error
        return dict(ok=False, error=type(error).__name__)
    density = sum(u.bit_count() + v.bit_count() + w.bit_count() for u, v, w in terms)
    return dict(ok=True, exact=True, shape=expected_shape, rank=len(terms), density=density,
                sha256=hashlib.sha256(raw).hexdigest())


def python_job(job):
    path, shape = job
    started = time.perf_counter()
    result = python_verdict(path, shape)
    result['seconds'] = time.perf_counter() - started
    return path, result


def ruby_verdict(path, shape):
    started = time.perf_counter()
    run = subprocess.run(['ruby', str(RUBY), '--shape', shape, path], capture_output=True, text=True)
    seconds = time.perf_counter() - started
    if run.returncode != 0:
        return dict(ok=False, error=run.stderr.strip(), seconds=seconds)
    record = json.loads(run.stdout)[0]
    return dict(ok=True, seconds=seconds, **{k: record[k] for k in FIELDS})


def ruby_job(job):
    path, shape = job
    return path, ruby_verdict(path, shape)


def tungsten_batch(binary, rows, *options):
    """One process for the whole list: {path: record} and the wall-clock seconds."""
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as listing:
        for path, shape in rows:
            listing.write(f'{path}\t{shape}\n')
    started = time.perf_counter()
    run = subprocess.run([binary, *options, '--batch', listing.name], capture_output=True, text=True)
    seconds = time.perf_counter() - started
    os.unlink(listing.name)
    if run.returncode != 0:
        raise SystemExit(f'tungsten batch failed: {run.stderr.strip()}')
    return {r['path']: r for r in json.loads(run.stdout)}, seconds


def same(a, b):
    return a['ok'] and b['ok'] and all(a[k] == b[k] for k in FIELDS)


def corpus_command(args):
    rows = entries(args.corpus)
    out = Path(args.out) if args.out else None
    if out:
        out.mkdir(parents=True, exist_ok=True)
    print(f'{len(rows)} tensors in {args.corpus}')

    def cached(name, compute):
        if out and (out / name).exists():
            return json.loads((out / name).read_text())
        value = compute()
        if out:
            (out / name).write_text(json.dumps(value))
        return value

    def run_pool(function):
        with futures.ProcessPoolExecutor(max_workers=args.jobs) as pool:
            return dict(pool.map(function, rows, chunksize=4))

    python = cached('python.json', lambda: run_pool(python_job))
    ruby = cached('ruby.json', lambda: run_pool(ruby_job))
    tungsten = {}
    for name, options in (('default-both', ()), ('dense', ('--gate', 'dense')),
                          ('sparse', ('--gate', 'sparse')), ('strict', ('--strict',))):
        records, seconds = tungsten_batch(args.binary, rows, *options)
        tungsten[name] = {p: dict(ok=True, **records[os.path.abspath(p)]) for p, _ in rows}
        print(f'tungsten {name:13s} one process, {len(rows)} certificates: {seconds:7.2f} s')

    failures = 0
    for name, results in (('python', python), ('tungsten default/both', tungsten['default-both']),
                          ('tungsten --gate dense', tungsten['dense']),
                          ('tungsten --gate sparse', tungsten['sparse']),
                          ('tungsten --strict', tungsten['strict'])):
        agree = sum(same(ruby[p], results[p]) for p, _ in rows)
        failures += len(rows) - agree
        print(f'{name:24s} == ruby: {agree} of {len(rows)} identical records')
    exact_count = sum(1 for p, _ in rows if ruby[p]['ok'])
    print(f'ruby accepted {exact_count} of {len(rows)}')
    if failures:
        raise SystemExit('PARITY FAILURES')
    print('PASS corpus parity')


# ----------------------------------------------------------------------------- mutations

def popcount(x):
    return x.bit_count()


def flip_bit(rng, mask, width):
    """A different mask, still nonzero and below 2^width, one bit away."""
    while True:
        bit = rng.randrange(width)
        mutated = mask ^ (1 << bit)
        if mutated:
            return mutated


def transposed(mask, rows, cols):
    result = 0
    while mask:
        low = mask & -mask
        b = low.bit_length() - 1
        result |= 1 << ((b % cols) * rows + b // cols)
        mask ^= low
    return result


def semantic_mutants(rng, shape, terms):
    """Mutants no implementation may accept: the tensor or the header is wrong."""
    blob, _, exact = load_read_blob()
    n, m, p = shape
    out = {}
    for kind, axis, width in (('flip_u', 0, n * m), ('flip_v', 1, m * p), ('flip_w', 2, n * p)):
        mutated = list(terms)
        i = rng.randrange(len(terms))
        row = list(mutated[i])
        row[axis] = flip_bit(rng, row[axis], width)
        mutated[i] = tuple(row)
        out[kind] = blob(shape, mutated)
    mutated = list(terms)
    del mutated[rng.randrange(len(mutated))]
    out['drop_term'] = blob(shape, mutated)
    mutated = list(terms) + [terms[rng.randrange(len(terms))]]
    out['dup_term'] = blob(shape, mutated)
    if n != p:
        flipped = [(u, v, transposed(w, n, p)) for u, v, w in terms]
        try:
            exact(shape, flipped)
        except AssertionError:
            out['transposed_c'] = blob(shape, flipped)
    raw = blob(shape, terms)
    header, _, rest = raw.partition(b'\n')
    tag, *fields = header.split()
    out['rank_lie'] = b' '.join([tag, *fields[:3], str(len(terms) + 1).encode()]) + b'\n' + rest
    if n != m:
        out['shape_lie'] = b' '.join([tag, fields[1], fields[0], fields[2], fields[3]]) + b'\n' + rest
    zeroed = list(terms)
    i = rng.randrange(len(zeroed))
    zeroed[i] = (0, zeroed[i][1], zeroed[i][2])
    out['zero_factor'] = blob(shape, zeroed)
    wide = list(terms)
    i = rng.randrange(len(wide))
    wide[i] = (wide[i][0] | (1 << (n * m)), wide[i][1], wide[i][2])
    out['wide_factor'] = blob(shape, wide)
    return out


def format_mutants(rng, shape, terms):
    """Mutants of the TEXT of an exact scheme: (bytes, ruby_accepts, python_accepts)."""
    blob, _, _ = load_read_blob()
    raw = blob(shape, terms)
    lines = raw.split(b'\n')
    header, rows = lines[0], lines[1:-1]
    out = {}
    shuffled = list(rows)
    rng.shuffle(shuffled)
    if shuffled != rows:
        out['unsorted'] = (header + b'\n' + b'\n'.join(shuffled) + b'\n', True, False)
    out['crlf'] = (raw.replace(b'\n', b'\r\n'), True, False)
    out['blank_line'] = (header + b'\n\n' + b'\n'.join(rows) + b'\n', True, False)
    out['comment_line'] = (header + b'\n# a comment\n' + b'\n'.join(rows) + b'\n', True, False)
    out['trailing_space'] = (raw.replace(b'\n', b' \n', 1), True, False)
    out['no_final_newline'] = (raw[:-1], True, False)
    letters = [i for i, row in enumerate(rows) if any(c in row for c in b'abcdef')]
    if letters:
        i = rng.choice(letters)
        edited = list(rows)
        edited[i] = edited[i].upper()
        out['uppercase'] = (header + b'\n' + b'\n'.join(edited) + b'\n', False, False)
    edited = list(rows)
    i = rng.randrange(len(edited))
    edited[i] = b'0' + edited[i]
    out['leading_zero'] = (header + b'\n' + b'\n'.join(edited) + b'\n', True, False)
    extra = terms[rng.randrange(len(terms))]
    doubled = list(terms) + [extra, extra]
    out['cancelling_pair'] = (blob(shape, doubled), True, False)
    return out


def verdicts(binary, mutant_path, shape):
    ruby = ruby_verdict(str(mutant_path), shape)
    python = python_verdict(str(mutant_path), shape)
    lenient = subprocess.run([binary, '--shape', shape, str(mutant_path)], capture_output=True, text=True)
    strict = subprocess.run([binary, '--strict', '--shape', shape, str(mutant_path)], capture_output=True, text=True)
    return ruby['ok'], python['ok'], lenient.returncode == 0, strict.returncode == 0


def mutate_command(args):
    blob, read_blob, exact = load_read_blob()
    rows = entries(args.corpus)
    rng = random.Random(args.seed)
    small = [r for r in rows if int(Path(r[0]).stat().st_size) <= args.max_bytes]
    sample = rng.sample(small, min(args.samples, len(small)))
    print(f'{len(sample)} sampled tensors (of {len(rows)}; at most {args.max_bytes} bytes each)')
    work = Path(args.workdir) if args.workdir else Path(tempfile.mkdtemp(prefix='verify-tensor-mutants-'))
    work.mkdir(parents=True, exist_ok=True)
    jobs = []
    for path, shape in sample:
        raw = Path(path).read_bytes()
        parsed_shape, terms = read_blob(raw)
        dims = 'x'.join(map(str, parsed_shape))
        base = hashlib.sha256(raw).hexdigest()[:12]
        cases = {'original': (raw, True, True)}
        for kind, text in semantic_mutants(rng, parsed_shape, terms).items():
            cases[kind] = (text, False, False)
        for kind, (text, ruby_ok, python_ok) in format_mutants(rng, parsed_shape, terms).items():
            cases[kind] = (text, ruby_ok, python_ok)
        for kind, (text, ruby_ok, python_ok) in cases.items():
            target = work / f'{base}-{kind}' / dims / 'certificate.mfw'
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text)
            jobs.append((kind, target, dims, ruby_ok, python_ok))
    print(f'{len(jobs)} certificates written under {work}')

    def run(job):
        kind, target, dims, ruby_ok, python_ok = job
        return job, verdicts(args.binary, target, dims)

    tally = {}
    bad = []
    with futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for (kind, target, dims, ruby_ok, python_ok), got in pool.map(run, jobs):
            row = tally.setdefault(kind, dict(cases=0, ruby=0, python=0, lenient=0, strict=0, all_agree=0))
            r, p, lenient, strict = got
            row['cases'] += 1
            row['ruby'] += r
            row['python'] += p
            row['lenient'] += lenient
            row['strict'] += strict
            # The originals define the oracle for each rule set: Tungsten's default rules are
            # Ruby's, Tungsten --strict follows Python's.
            expected = (ruby_ok, python_ok, ruby_ok, python_ok)
            if got != expected:
                bad.append((kind, str(target), got, expected))
            row['all_agree'] += (r == p == lenient == strict)
    print(f'{"mutation":18s} {"cases":>6s} {"ruby":>6s} {"python":>7s} {"tung":>6s} {"strict":>7s}   (accepting)')
    for kind, row in tally.items():
        print(f'{kind:18s} {row["cases"]:6d} {row["ruby"]:6d} {row["python"]:7d} {row["lenient"]:6d} {row["strict"]:7d}')
    total = sum(row['cases'] for row in tally.values())
    print(f'{total - len(bad)} of {total} verdicts as expected '
          f'(Tungsten default == Ruby, Tungsten --strict == Python, originals as documented)')
    semantic = [k for k in tally if k not in ('original', 'unsorted', 'crlf', 'blank_line', 'comment_line',
                                              'trailing_space', 'no_final_newline', 'leading_zero',
                                              'cancelling_pair')]
    agree_cases = sum(tally[k]['all_agree'] for k in semantic + ['original', 'uppercase'] if k in tally)
    agree_total = sum(tally[k]['cases'] for k in semantic + ['original', 'uppercase'] if k in tally)
    print(f'all four implementations agree on {agree_cases} of {agree_total} accept/reject cases '
          f'(originals unmodified or mutated so that the originals themselves agree)')
    for item in bad[:20]:
        print('UNEXPECTED', item)
    if bad:
        raise SystemExit('PARITY FAILURES')
    print('PASS mutation parity')


# ----------------------------------------------------------------------------- timing

def children_cpu():
    import resource
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    return usage.ru_utime + usage.ru_stime


def measure(function):
    """(wall seconds, CPU seconds of child processes plus this one) of function()."""
    cpu0, own0, started = children_cpu(), time.process_time(), time.perf_counter()
    function()
    wall = time.perf_counter() - started
    return wall, children_cpu() - cpu0 + time.process_time() - own0


def median(values):
    ordered = sorted(values)
    return ordered[len(ordered) // 2]


def timing_command(args):
    rows = entries(args.corpus)
    script = Path(__file__).resolve()
    print(f'{len(rows)} tensors; {args.runs} runs per Tungsten/single-file cell (median); machine load '
          f'{os.getloadavg()[0]:.1f} (1 min)')

    def report(label, walls, cpus, note=''):
        print(f'{label:46s} wall {median(walls):8.2f} s   cpu {median(cpus):8.2f} s   {note}')

    if not args.skip_corpus:
        print('\nwhole corpus')
        wall, cpu = measure(lambda: [ruby_verdict(p, shape) for p, shape in rows])
        report('ruby verify_tensor.rb, one process per file', [wall], [cpu], '(1 pass)')
        wall, cpu = measure(lambda: [python_verdict(p, shape) for p, shape in rows])
        report('python read_blob + exact, in one process', [wall], [cpu], '(1 pass; no per-file start-up)')
        for name, options in (('dense', ('--gate', 'dense')), ('sparse', ('--gate', 'sparse')),
                              ('both', ()), ('strict, both', ('--strict',))):
            walls, cpus = [], []
            for _ in range(args.runs):
                wall, cpu = measure(lambda: tungsten_batch(args.binary, rows, *options))
                walls.append(wall)
                cpus.append(cpu)
            report(f'tungsten --release --batch, gate {name}', walls, cpus, f'({args.runs} runs)')

    print('\nper invocation (one certificate, one process each time)')
    by_rank = sorted(rows, key=lambda r: Path(r[0]).stat().st_size)
    picks = [('smallest corpus tensor', by_rank[0]), ('median-size tensor', by_rank[len(by_rank) // 2]),
             ('largest tensor (28x32x32, rank 14,271)', by_rank[-1])]
    for label, (path, shape) in picks:
        print(f'{label}: {shape}, {Path(path).stat().st_size} bytes')
        commands = {'ruby': ['ruby', str(RUBY), '--shape', shape, path],
                    'python': [sys.executable, str(script), 'python-one', path, shape],
                    'tungsten dense': [args.binary, '--gate', 'dense', '--shape', shape, path],
                    'tungsten sparse': [args.binary, '--gate', 'sparse', '--shape', shape, path],
                    'tungsten both': [args.binary, '--shape', shape, path]}
        for name, command in commands.items():
            walls, cpus = [], []
            for _ in range(args.runs):
                wall, cpu = measure(lambda: subprocess.run(command, capture_output=True, check=True))
                walls.append(wall)
                cpus.append(cpu)
            report(f'  {name}', walls, cpus)


def python_one(path, shape):
    result = python_verdict(path, shape)
    if not result['ok']:
        raise SystemExit(1)


# ----------------------------------------------------------------------------- fuzzing

VOCABULARY = [b'0', b'00', b'1', b'01', b'7', b'R', b'r', b'#', b'# c', b'MFW1', b'MFW2', b'-1', b'+3', b'0x10',
              b'1_0', b'ff', b'FF', b'g', b'99999999999999999999999', b'1e3', b'12', b'9', b'f', b'0f', b'2', b'3',
              b'\xc3\xa9', b'', b'a b', b'15', b'16', b'1f', b'ffffffffffffffffffffffff']
SEPARATORS = [b' ', b'\t', b'\x0b', b'\x0c', b'\r', b'\0', b'\n', b'  ', b'\r\n', b'\xa0']


def flip_walk(rng, shape, steps):
    """The naive scheme after random flips: exact by construction, with varied factors.

    A flip replaces (s, x1, y1), (s, x2, y2) by (s, x1^x2, y1), (s, x2, y1^y2) on any axis s the two
    terms share, which preserves the sum over GF(2)."""
    n, m, p = shape
    terms = [[1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k)]
             for i in range(n) for j in range(m) for k in range(p)]
    for _ in range(steps if len(terms) > 1 else 0):
        a, b = rng.sample(range(len(terms)), 2)
        axis = rng.randrange(3)
        if terms[a][axis] != terms[b][axis]:
            continue
        x, y = rng.sample([q for q in range(3) if q != axis], 2)
        x1, y1, x2, y2 = terms[a][x], terms[a][y], terms[b][x], terms[b][y]
        if x1 == x2 or y1 == y2:
            continue
        terms[a][x] = x1 ^ x2
        terms[b][y] = y1 ^ y2
    return [tuple(t) for t in terms]


def random_terms(rng, shape):
    n, m, p = shape
    return [(rng.randrange(1, 1 << (n * m)), rng.randrange(1, 1 << (m * p)), rng.randrange(1, 1 << (n * p)))
            for _ in range(rng.randrange(1, 14))]


def fuzz_bases(corpus, rng):
    """(name, shape, text) starting points in every accepted format."""
    seeds = HERE.parent / 'lib/metaflip/seeds/gf2'
    strassen = [tuple(int(w) for w in line.split()) for line in
                (seeds / 'matmul_2x2_rank7_strassen_gf2.txt').read_text().split('\n')[1:] if line.strip()]
    blob, read_blob, _ = load_read_blob()
    out = [('mfw1', '2x2x2', blob((2, 2, 2), strassen)),
           ('checkpoint', '2x2x2', f'{len(strassen)}\n'.encode() + b''.join(b' '.join(str(v).encode() for v in t) + b'\n' for t in strassen)),
           ('rows', '2x2x2', b''.join(b'R ' + b' '.join(str(v).encode() for v in t) + b'\n' for t in strassen))]
    for row in list(csv.DictReader(open(Path(corpus) / 'corpus.tsv'), delimiter='\t')):
        if row['shape'] == '2x4x17' and int(row['rank']) < 130:
            raw = (Path(corpus) / 'mfw' / (row['sha256'] + '.mfw')).read_bytes()
            _, terms = read_blob(raw)
            out.append(('wide-mfw1', '2x4x17', raw))
            out.append(('wide-rows', '2x4x17', b''.join(b'R ' + b' '.join(str(v).encode() for v in t) + b'\n' for t in terms)))
            break
    for _ in range(24):
        shape = (rng.randrange(1, 5), rng.randrange(1, 6), rng.randrange(1, 9))
        dims = 'x'.join(map(str, shape))
        walked = flip_walk(rng, shape, rng.randrange(0, 120))
        out.append(('walk-mfw1', dims, blob(shape, walked)))
        out.append(('walk-rows', dims, b''.join(b'R ' + b' '.join(str(v).encode() for v in t) + b'\n' for t in walked)))
        out.append(('random-mfw1', dims, blob(shape, random_terms(rng, shape))))
    return out


def damage(rng, text):
    for _ in range(rng.choice((1, 1, 2, 3))):
        kind = rng.choice(('insert', 'delete', 'token', 'dup_line', 'drop_line', 'swap_lines', 'ins_line',
                           'upper', 'header', 'strip', 'replace_sep', 'truncate', 'append'))
        lines = text.split(b'\n')
        if kind == 'insert':
            i = rng.randrange(len(text) + 1)
            text = text[:i] + rng.choice(SEPARATORS) + text[i:]
        elif kind == 'delete' and text:
            i = rng.randrange(len(text))
            text = text[:i] + text[i + 1:]
        elif kind == 'token':
            words = text.split(b' ')
            if words:
                words[rng.randrange(len(words))] = rng.choice(VOCABULARY)
                text = b' '.join(words)
        elif kind == 'dup_line' and lines:
            i = rng.randrange(len(lines))
            lines.insert(i, lines[i])
            text = b'\n'.join(lines)
        elif kind == 'drop_line' and lines:
            del lines[rng.randrange(len(lines))]
            text = b'\n'.join(lines)
        elif kind == 'swap_lines' and len(lines) > 1:
            i, j = rng.randrange(len(lines)), rng.randrange(len(lines))
            lines[i], lines[j] = lines[j], lines[i]
            text = b'\n'.join(lines)
        elif kind == 'ins_line':
            lines.insert(rng.randrange(len(lines) + 1), b' '.join(rng.choice(VOCABULARY) for _ in range(rng.randrange(0, 5))))
            text = b'\n'.join(lines)
        elif kind == 'upper':
            text = text.upper() if rng.random() < 0.2 else text.replace(b'f', b'F', 1).replace(b'a', b'A', 1)
        elif kind == 'header':
            head, _, rest = text.partition(b'\n')
            head = head.replace(b'2', rng.choice((b'3', b'1', b'22', b'0')), 1)
            text = head + b'\n' + rest
        elif kind == 'strip':
            text = text.strip()
        elif kind == 'replace_sep':
            text = text.replace(b' ', rng.choice(SEPARATORS), 1)
        elif kind == 'truncate' and text:
            text = text[:rng.randrange(len(text))]
        elif kind == 'append':
            text = text + rng.choice(SEPARATORS + VOCABULARY)
    return text


def fuzz_command(args):
    rng = random.Random(args.seed)
    bases = fuzz_bases(args.corpus, rng)
    work = Path(args.workdir) if args.workdir else Path(tempfile.mkdtemp(prefix='verify-tensor-fuzz-'))
    jobs = []
    for i in range(args.cases):
        name, shape, text = rng.choice(bases)
        damaged = damage(rng, text) if i >= len(bases) else text
        target = work / f'{i:05d}' / shape / 'certificate.txt'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(damaged)
        jobs.append((i, name, shape, target))

    def run(job):
        i, name, shape, target = job
        path = str(target)
        ruby = subprocess.run(['ruby', str(RUBY), '--shape', shape, path], capture_output=True, text=True, errors='replace')
        outcomes = {}
        for gate in ('dense', 'sparse', 'both'):
            outcomes[gate] = subprocess.run([args.binary, '--gate', gate, '--shape', shape, path],
                                            capture_output=True, text=True, errors='replace')
        strict = subprocess.run([args.binary, '--strict', '--shape', shape, path], capture_output=True, text=True, errors='replace')
        python = python_verdict(path, shape)
        problems = []
        for gate, got in outcomes.items():
            if (got.returncode, got.stdout, got.stderr) != (ruby.returncode, ruby.stdout, ruby.stderr):
                problems.append(f'--gate {gate} differs from ruby: ({got.returncode}, {got.stderr.strip()!r}) vs ({ruby.returncode}, {ruby.stderr.strip()!r})')
        if (strict.returncode == 0) != python['ok']:
            problems.append(f'--strict {strict.returncode}/{strict.stderr.strip()!r} vs python {python}')
        elif python['ok'] and strict.stdout != ruby.stdout:
            problems.append('--strict record differs from ruby')
        return job, ruby.returncode, python['ok'], problems

    stats = dict(ruby_accept=0, python_accept=0, both_accept=0)
    messages = {}
    bad = []
    with futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for job, ruby_status, python_ok, problems in pool.map(run, jobs):
            stats['ruby_accept'] += ruby_status == 0
            stats['python_accept'] += python_ok
            stats['both_accept'] += (ruby_status == 0 and python_ok)
            if problems:
                bad.append((job[3], problems))
            elif ruby_status != 0:
                message = Path(job[3]).parent.parent / 'x'
    print(f'{len(jobs)} damaged certificates from {len(bases)} base formats under {work}')
    print(f'ruby accepts {stats["ruby_accept"]}, python accepts {stats["python_accept"]} '
          f'(both {stats["both_accept"]}), rejected by both {len(jobs) - stats["ruby_accept"] - stats["python_accept"] + stats["both_accept"]}')
    print(f'{len(jobs) - len(bad)} of {len(jobs)} cases: Tungsten (3 gates) == Ruby byte for byte, --strict == Python verdict')
    for path, problems in bad[:15]:
        print('MISMATCH', path, *problems, sep='\n  ')
    if bad:
        raise SystemExit('PARITY FAILURES')
    print('PASS fuzz parity')


# ----------------------------------------------------------------------------- strict reader alone

ALPHABET = list(b'0123456789abcdefABCDEF -+_xX\t\r\n#gzG.') + [0, 11, 12, 0xff, 0xc3]


def canonical_texts(rng, corpus, count):
    blob, read_blob, _ = load_read_blob()
    texts = []
    for _ in range(count):
        shape = (rng.randrange(1, 5), rng.randrange(1, 6), rng.randrange(1, 9))
        texts.append(blob(shape, flip_walk(rng, shape, rng.randrange(0, 100))))
        texts.append(blob(shape, random_terms(rng, shape)))
    small = [r for r in csv.DictReader(open(Path(corpus) / 'corpus.tsv'), delimiter='\t') if int(r['rank']) < 300]
    for row in rng.sample(small, min(6, len(small))):
        texts.append((Path(corpus) / 'mfw' / (row['sha256'] + '.mfw')).read_bytes())
    return texts


def damage_canonical(rng, text):
    for _ in range(rng.choice((1, 1, 1, 2, 3))):
        lines = text.split(b'\n')
        kind = rng.choice(('replace', 'insert', 'delete', 'swap_rows', 'dup_row', 'drop_row', 'zeros', 'upper',
                           'header', 'final_newline', 'crlf', 'truncate', 'swap_words'))
        if kind == 'replace' and text:
            i = rng.randrange(len(text))
            text = text[:i] + bytes([rng.choice(ALPHABET)]) + text[i + 1:]
        elif kind == 'insert':
            i = rng.randrange(len(text) + 1)
            text = text[:i] + bytes([rng.choice(ALPHABET)]) + text[i:]
        elif kind == 'delete' and text:
            i = rng.randrange(len(text))
            text = text[:i] + text[i + 1:]
        elif kind == 'swap_rows' and len(lines) > 3:
            i, j = rng.randrange(1, len(lines) - 1), rng.randrange(1, len(lines) - 1)
            lines[i], lines[j] = lines[j], lines[i]
            text = b'\n'.join(lines)
        elif kind == 'dup_row' and len(lines) > 2:
            i = rng.randrange(1, len(lines) - 1)
            lines.insert(i, lines[i])
            text = b'\n'.join(lines)
        elif kind == 'drop_row' and len(lines) > 2:
            del lines[rng.randrange(1, len(lines) - 1)]
            text = b'\n'.join(lines)
        elif kind == 'zeros' and len(lines) > 2:
            i = rng.randrange(1, len(lines) - 1)
            lines[i] = b'0' + lines[i]
            text = b'\n'.join(lines)
        elif kind == 'upper':
            i = rng.randrange(len(lines))
            lines[i] = lines[i].upper()
            text = b'\n'.join(lines)
        elif kind == 'header':
            head = lines[0].split(b' ')
            if len(head) == 5:
                k = rng.randrange(1, 5)
                head[k] = str(max(0, int(head[k]) + rng.choice((-1, 1, 10)))).encode() if head[k].isdigit() else head[k]
                lines[0] = b' '.join(head)
                text = b'\n'.join(lines)
        elif kind == 'final_newline':
            text = text[:-1] if text.endswith(b'\n') else text + b'\n'
        elif kind == 'crlf':
            i = rng.randrange(len(lines))
            lines[i] = lines[i] + b'\r'
            text = b'\n'.join(lines)
        elif kind == 'truncate' and text:
            text = text[:rng.randrange(len(text))]
        elif kind == 'swap_words' and len(lines) > 2:
            i = rng.randrange(1, len(lines) - 1)
            words = lines[i].split(b' ')
            rng.shuffle(words)
            lines[i] = b' '.join(words)
            text = b'\n'.join(lines)
    return text


def parse_fuzz_command(args):
    _, read_blob, _ = load_read_blob()
    rng = random.Random(args.seed)
    work = Path(args.workdir) if args.workdir else Path(tempfile.mkdtemp(prefix='gf2-parse-fuzz-'))
    work.mkdir(parents=True, exist_ok=True)
    bases = canonical_texts(rng, args.corpus, 200)
    paths = []
    for i in range(args.cases):
        text = bases[i % len(bases)] if i < len(bases) else damage_canonical(rng, rng.choice(bases))
        path = work / f'{i:06d}.mfw'
        path.write_bytes(text)
        paths.append(path)
    listing = work / 'list.txt'
    listing.write_text('\n'.join(map(str, paths)) + '\n')
    run = subprocess.run([args.parse_binary, str(listing)], capture_output=True, text=True, errors='replace')
    if run.returncode != 0:
        raise SystemExit(f'driver failed: {run.stderr.strip()}')
    verdicts = {}
    for line in run.stdout.split('\n'):
        if line:
            kind, path, *rest = line.split('\t')
            verdicts[path] = (kind, rest)
    agree_accept = agree_reject = deviations = 0
    bad = []
    for path in paths:
        raw = path.read_bytes()
        try:
            shape, terms = read_blob(raw)
            python_accepts = True
        except Exception:  # every rejection is an assertion or a parse error
            python_accepts = False
        kind, rest = verdicts[str(path)]
        if python_accepts and kind == 'ACCEPT':
            if rest[0] != str(len(terms)) or rest[1] != hashlib.sha256(raw).hexdigest():
                bad.append((str(path), 'accepted with a different rank or digest', rest))
            else:
                agree_accept += 1
        elif not python_accepts and kind == 'REJECT':
            agree_reject += 1
        elif python_accepts and kind == 'REJECT':
            # read_blob lets through negative numbers, non-positive dimensions and rows whose field count
            # is not three (they become tuples of another length); exact refuses each of them later.
            irregular = b'-' in raw or any(dim < 1 for dim in shape) or any(len(t) != 3 for t in terms)
            if irregular:
                deviations += 1
            else:
                bad.append((str(path), 'python accepts, tungsten rejects', rest))
        else:
            bad.append((str(path), 'tungsten accepts, python rejects', rest))
    print(f'{len(paths)} damaged canonical files: both accept {agree_accept}, both reject {agree_reject}, '
          f'documented deviations {deviations} (negative numbers, non-positive dimensions, rows of a field count other than three), unexplained {len(bad)}')
    for item in bad[:15]:
        print('MISMATCH', *item)
    if bad:
        raise SystemExit('PARITY FAILURES')
    print('PASS strict reader parity')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    corpus = sub.add_parser('corpus')
    corpus.add_argument('--corpus', required=True)
    corpus.add_argument('--binary', required=True)
    corpus.add_argument('--out')
    corpus.add_argument('--jobs', type=int, default=3)
    mutate = sub.add_parser('mutate')
    mutate.add_argument('--corpus', required=True)
    mutate.add_argument('--binary', required=True)
    mutate.add_argument('--samples', type=int, default=210)
    mutate.add_argument('--seed', type=int, default=1)
    mutate.add_argument('--max-bytes', type=int, default=400_000)
    mutate.add_argument('--workdir')
    mutate.add_argument('--jobs', type=int, default=3)
    pf = sub.add_parser('parse-fuzz')
    pf.add_argument('--corpus', required=True)
    pf.add_argument('--parse-binary', required=True)
    pf.add_argument('--cases', type=int, default=20000)
    pf.add_argument('--seed', type=int, default=1)
    pf.add_argument('--workdir')
    timing = sub.add_parser('time')
    timing.add_argument('--corpus', required=True)
    timing.add_argument('--binary', required=True)
    timing.add_argument('--runs', type=int, default=3)
    timing.add_argument('--skip-corpus', action='store_true')
    one = sub.add_parser('python-one')
    one.add_argument('path')
    one.add_argument('shape')
    fuzz = sub.add_parser('fuzz')
    fuzz.add_argument('--corpus', required=True)
    fuzz.add_argument('--binary', required=True)
    fuzz.add_argument('--cases', type=int, default=4000)
    fuzz.add_argument('--seed', type=int, default=1)
    fuzz.add_argument('--workdir')
    fuzz.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    if args.command == 'python-one':
        return python_one(args.path, args.shape)
    {'corpus': corpus_command, 'mutate': mutate_command, 'fuzz': fuzz_command, 'time': timing_command,
     'parse-fuzz': parse_fuzz_command}[args.command](args)


if __name__ == '__main__':
    main()
