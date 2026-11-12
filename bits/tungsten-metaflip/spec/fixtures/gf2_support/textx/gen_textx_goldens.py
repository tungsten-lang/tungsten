#!/usr/bin/env python3
"""Golden fixtures for lib/metaflip/gf2/textx.w, produced by Python itself.

usage: [TEXTX_GOLDEN_SCALE=n] [TEXTX_GOLDEN_SEED=n] gen_textx_goldens.py [OUTDIR]
       (OUTDIR defaults to the directory of this script)

Every expected value below is computed by the Python original of the idiom
(format specs, repr, str.splitlines/split, sorted/min/max, collections.Counter,
zlib.crc32, csv), never by hand. The generator is deterministic (fixed seed).
Run with python3 3.14; the repr table follows Python's Unicode database
(16.0), of which textx.w models the assigned categories (see its header).

Files (all text, UTF-8; strings that may hold control characters or invalid
text are base64 of their UTF-8 bytes):
  format_cases.tsv   fn TAB args... TAB expected   (no field holds a tab or newline)
  repr_cases.tsv     hex code points (space separated) TAB repr(str)
  split_cases.tsv    splitlines|words TAB b64(input) TAB count,b64(item),...
  crc32_cases.tsv    b64(bytes) TAB zlib.crc32
  sort_cases.json    stable sort / min / max cases over tuple keys
  count_cases.json   Counter / most_common / sorted(items) / defaultdict / median
  tsv_read_cases.json   csv.reader / DictReader over text-mode files
  tsv_write_cases.json  csv.writer cases
"""
import base64
import csv
import io
import json
import os
import random
import sys
import tempfile
import zlib
from collections import Counter, defaultdict

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
# The committed fixtures use SCALE 1 and the default seed. A larger SCALE (or another
# SEED) multiplies the random cases for one-off differential runs into a scratch OUTDIR.
SCALE = int(os.environ.get('TEXTX_GOLDEN_SCALE', '1'))
rng = random.Random(int(os.environ.get('TEXTX_GOLDEN_SEED', '20260930')))


def b64(s):
    raw = s if isinstance(s, bytes) else s.encode('utf-8', 'surrogatepass')
    return base64.b64encode(raw).decode()


def write(name, text):
    with open(os.path.join(OUT, name), 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(text)
    print(f'{name}: {len(text.encode())} bytes')


# --------------------------------------------------------------------------- format
INTS = [0, 1, -1, 9, -9, 10, 99, 100, 999, 1000, -1000, 1234, -1234, 12345, 123456, 1234567, -1234567,
        2 ** 31 - 1, 2 ** 31, -2 ** 31, 2 ** 32, 2 ** 47 - 1, 2 ** 47, -2 ** 47, 2 ** 53, 2 ** 62, 2 ** 63 - 1,
        2 ** 63, -2 ** 63, 2 ** 63 + 1, 2 ** 64 - 1, 2 ** 64, 10 ** 18, 10 ** 19, 10 ** 30, -10 ** 30,
        2 ** 100, -2 ** 100, 2 ** 200, -2 ** 200, 3 ** 120, 7 ** 90 + 12345]
INTS += [rng.randrange(-10 ** 6, 10 ** 6) for _ in range(20 * SCALE)]
INTS += [rng.getrandbits(rng.randrange(1, 260)) * rng.choice((1, -1)) for _ in range(30 * SCALE)]
STRINGS = ['', 'a', 'ab', 'x', 'shape', '2x3x4', 'below_all', 'gf2_valid_only', '13x14x16', 'tie', 'a b', '  ',
           'é', 'ñandú', 'naïve', '日本語', '日本語テキスト', 'Ünïcödé', '😀', 'a😀b', '👨‍👩‍👧', 'é',
           'Ω≈ç√', ' ', 'x y', 'long string with several words in it', '0', '-', "it's", '"q"',
           'ᚠᚢᚦ', 'א ב', 'Σ']
STRINGS += [''.join(rng.choice('abcXYZ 09é日😀') for _ in range(rng.randrange(0, 14))) for _ in range(25 * SCALE)]
FILLS = [' ', ' ', ' ', '0', '.', '-', '*', 'é', '日', '😀', '_', '#']

lines = []
for s in STRINGS:
    for width in rng.sample(range(0, 24), 3):
        fill = rng.choice(FILLS)
        lines.append(('pad_left', 's', s, width, fill, format(s, f'{fill}>{width}')))
        fill = rng.choice(FILLS)
        lines.append(('pad_right', 's', s, width, fill, format(s, f'{fill}<{width}')))
for n in INTS:
    for width in rng.sample(range(0, 70), 2):
        fill = rng.choice(FILLS)
        lines.append(('pad_left', 'i', n, width, fill, format(n, f'{fill}>{width}')))
        fill = rng.choice(FILLS)
        lines.append(('pad_right', 'i', n, width, fill, format(n, f'{fill}<{width}')))
for n in INTS:
    for width in rng.sample(range(0, 70), 2):
        lines.append(('zero_pad', n, width, '%0*d' % (width, n)))
    lines.append(('thousands', n, f'{n:,}'))
    lines.append(('signed', n, f'{n:+d}'))
    lines.append(('hex', n, f'{n:x}'))
    lines.append(('parse_hex', f'{n:x}', str(n)))
    if n % 3 == 0:
        lines.append(('parse_hex', f'{n:X}', str(n)))
for n in INTS[:60]:
    text = f'{abs(n):x}'
    lines.append(('parse_hex', ('-' if n < 0 else '+') + '0x' + text, str(n if n < 0 else abs(n))))
    if len(text) > 4:
        cut = len(text) // 2
        lines.append(('parse_hex', text[:cut] + '_' + text[cut:], str(abs(n))))
for text in ['0', '00', '000000000000000ff', 'ffffffffffffff', 'fffffffffffffff', 'ffffffffffffffff',
             '1000000000000000', 'c0ef6e5800000000', '10000000000000000', '0x0', '-0', '+0', '0X1F', '0x_1f',
             'DeadBeef', 'deadbeefdeadbeefdeadbeefdeadbeef', 'f' * 15, 'f' * 16, 'f' * 17, 'f' * 30, '1' + '0' * 60]:
    lines.append(('parse_hex', text, str(int(text, 16))))
for text in ['', '-', '+', '0x', 'g', '1g', 'xyz', '1__2', '_12', '12_', '--1', '0x-1', '1.5', '0x1_']:
    try:
        int(text, 16)
        raise SystemExit(f'python accepts {text!r}')
    except ValueError:
        lines.append(('parse_hex', text, 'ERR'))
write('format_cases.tsv', ''.join('\t'.join(str(c) for c in row) + '\n' for row in lines))


# --------------------------------------------------------------------------- repr
import unicodedata  # noqa: E402

cps = list(range(1, 0x800))
cps += [cp for cp in range(0x800, 0x3400, 41)]
cps += [cp for cp in range(0x3400, 0x30000, 2003)]
boundaries = [(128, 160), (173, 173), (1536, 1541), (1564, 1564), (1757, 1757), (1807, 1807), (2192, 2193),
              (2274, 2274), (5760, 5760), (6158, 6158), (8192, 8207), (8232, 8239), (8287, 8292), (8294, 8303),
              (12288, 12288), (55296, 63743), (65279, 65279), (65529, 65531), (69821, 69821), (69837, 69837),
              (78896, 78911), (113824, 113827), (119155, 119162), (917505, 917505), (917536, 917631),
              (983040, 1048573), (1048576, 1114109)]
for lo, hi in boundaries:
    cps += [lo - 1, lo, lo + 1, hi - 1, hi, hi + 1, (lo + hi) // 2]
cps += [rng.randrange(0x30000, 0x110000) for _ in range(80 * SCALE)]
seen, single = set(), []
for cp in cps:
    if 0 < cp < 0x110000 and cp not in seen and unicodedata.category(chr(cp)) != 'Cn':
        seen.add(cp)
        single.append(cp)
rows = [([cp], repr(chr(cp))) for cp in sorted(single)]
words = ["it's", 'say "hi"', "both ' and \"", "back\\slash", "tab\there", "nl\nx", "cr\rx", "\x00", "\x1b[0m",
         "ends with quote'", '"', "'", "''", '""', "'\"", "\\'", 'é and \xa0', 'x y', '\ud800lone']
for w in words:
    if '\x00' in w:
        continue
    rows.append(([ord(c) for c in w], repr(w)))
for _ in range(120 * SCALE):
    w = ''.join(chr(rng.choice((rng.randrange(1, 128), rng.randrange(1, 128), rng.choice([39, 34, 92, 10, 9, 13, 0xa0, 0xad,
                                                                                            0x200b, 0x3000, 0xe9, 0x1f600, 0x2028])))) for _ in range(rng.randrange(0, 12)))
    if any(unicodedata.category(c) == 'Cn' for c in w):
        continue
    rows.append(([ord(c) for c in w], repr(w)))
write('repr_cases.tsv', ''.join(' '.join(f'{c:x}' for c in cs) + '\t' + r + '\n' for cs, r in rows))


# --------------------------------------------------------------------------- splitting
SEPS = ['\n', '\r', '\r\n', '\x0b', '\x0c', '\x1c', '\x1d', '\x1e', '\x85', ' ', ' ']
SPACES = [' ', '\t', '\n', '\r', '\x0b', '\x0c', '\x1c', '\x1d', '\x1e', '\x1f', '\x85', '\xa0', ' ', ' ',
          ' ', ' ', ' ', ' ', ' ', ' ', '　']
NOT_SPACE = ['​', '᠎', '﻿', '\x00' if False else 'z', ' x', 'é', '日', '\x7f', '\x1b', '­', '‌']
lines = []
inputs = ['', '\n', '\r\n', '\n\n', 'a', 'a\n', 'a\nb', 'a\r\nb\r\n', 'a\rb', '\r\r\n\n', 'x y z',
          '  a  b  ', 'a\tb\nc d', 'MFW1 3 3 3 23\nff 1 2\n', ' ', '　a　', 'a\x85b', 'é\xa0é',
          'line one\x0bline two\x0cline three\x1cfour\x1dfive\x1esix']
for _ in range(220 * SCALE):
    parts = []
    for _ in range(rng.randrange(0, 12)):
        parts.append(rng.choice(['ab', 'c', 'xyz', '12', 'é', '日本', '😀', '', ' ']))
        parts.append(rng.choice(SEPS + SPACES + SPACES + [''] + NOT_SPACE))
    inputs.append(''.join(parts))
for s in inputs:
    for fn, out in (('splitlines', s.splitlines()), ('words', s.split())):
        lines.append(f'{fn}\t{b64(s)}\t{len(out)}' + ''.join(',' + b64(x) for x in out))
write('split_cases.tsv', '\n'.join(lines) + '\n')


# --------------------------------------------------------------------------- crc32
vectors = [b'', b'a', b'abc', b'123456789', b'13x14x16', '2x3x4'.encode(), 'héllo wörld'.encode(), '日本語'.encode(),
           bytes(range(1, 256)), b'\x00', b'\x00\x00\x00\x00', b'\xff' * 33, b'\x80\x81\xfe\xff', b'a' * 1000]
for _ in range(60 * SCALE):
    vectors.append(bytes(rng.randrange(256) for _ in range(rng.randrange(0, 300))))
write('crc32_cases.tsv', ''.join(f'{b64(v)}\t{zlib.crc32(v)}\n' for v in vectors)
      + f'BIG\t{zlib.crc32(b"0123456789abcdef" * 65536)}\n')


# --------------------------------------------------------------------------- sorting
def random_key(shape):
    key = []
    for kind in shape:
        if kind == 'i':
            key.append(rng.randrange(-3, 4))
        elif kind == 'I':
            key.append(rng.randrange(-2 ** 80, 2 ** 80) if rng.random() < 0.5 else rng.randrange(-3, 4))
        elif kind == 's':
            key.append(rng.choice(['a', 'b', 'ab', 'B', '', 'é', '日', 'a0', 'a10', 'a9']))
        elif kind == 'b':
            key.append(rng.random() < 0.5)
    return key


sort_cases = []
for shape in ('i', 'ii', 'iii', 's', 'is', 'si', 'iis', 'I', 'Ii', 'ib', 'sib'):
    for count in (0, 1, 2, 5, 12, 40):
        for _ in range((1 if count > 12 else 2) * SCALE):
            keys = [random_key(shape) for _ in range(count)]
            if len(shape) == 1:
                keys = [k[0] for k in keys]
            order = list(range(count))
            case = {'shape': shape, 'keys': keys,
                    'forward': sorted(order, key=lambda i: keys[i]),
                    'reverse': sorted(order, key=lambda i: keys[i], reverse=True),
                    'first_min': min(order, key=lambda i: keys[i], default=None),
                    'first_max': max(order, key=lambda i: keys[i], default=None)}
            sort_cases.append(case)
write('sort_cases.json', json.dumps(sort_cases, ensure_ascii=False, separators=(',', ':')) + '\n')


# --------------------------------------------------------------------------- counting
count_cases = []
for pool in (['a', 'b', 'c', 'd', 'e'], ['x', 'y'], ['below_all', 'gf2_valid_only', 'tie', 'above'],
             [0, 1, 2, 3, 4, 5, 6], [2 ** 70, 2 ** 70 + 1, -2 ** 70, 3, 3], ['é', '日', '😀', 'a']):
    for count in (0, 1, 2, 3, 7, 20, 60):
        items = [rng.choice(pool) for _ in range(count)]
        counter = Counter(items)
        groups = defaultdict(list)
        for index, item in enumerate(items):
            groups[item].append(index)
        sort_key = (lambda kv: kv[0])
        case = {'items': items,
                'tally': [[k, v] for k, v in counter.items()],
                'most_common': [[k, v] for k, v in counter.most_common()],
                'most_common_2': [[k, v] for k, v in counter.most_common(2)],
                'most_common_0': [[k, v] for k, v in counter.most_common(0)],
                'sorted_items': [[k, v] for k, v in sorted(counter.items(), key=sort_key)],
                'groups': [[k, v] for k, v in groups.items()]}
        count_cases.append(case)
medians = []
for count in (1, 2, 3, 4, 5, 8, 9, 20, 21):
    for _ in range(3):
        values = [rng.randrange(-50, 50) for _ in range(count)]
        ordered = sorted(values)
        medians.append({'values': values, 'lower': ordered[(count - 1) // 2], 'upper': ordered[count // 2]})
    values = [rng.randrange(-40, 40) / 8 for _ in range(count)]
    ordered = sorted(values)
    medians.append({'values': values, 'lower': ordered[(count - 1) // 2], 'upper': ordered[count // 2]})
    values = [rng.randrange(-2 ** 90, 2 ** 90) for _ in range(count)]
    ordered = sorted(values)
    medians.append({'values': values, 'lower': ordered[(count - 1) // 2], 'upper': ordered[count // 2]})
write('count_cases.json', json.dumps({'counts': count_cases, 'medians': medians}, ensure_ascii=False,
                                     separators=(',', ':')) + '\n')


# --------------------------------------------------------------------------- csv
def read_text_mode(text):
    """csv.reader / DictReader over a text-mode file, exactly as the originals open theirs."""
    with tempfile.NamedTemporaryFile('wb', suffix='.tsv', delete=False) as fh:
        fh.write(text.encode('utf-8'))
    try:
        with open(fh.name, encoding='utf-8') as f:
            rows = list(csv.reader(f, delimiter='\t'))
        with open(fh.name, encoding='utf-8') as f:
            records = []
            try:
                for record in csv.DictReader(f, delimiter='\t'):
                    if None in record:
                        raise ValueError('long row')
                    records.append(record)
            except ValueError:
                records = 'ERR'
        if rows and rows[0] == []:
            records = 'SKIP'          # DictReader takes a blank first line as the header; textx skips it
        return rows, records
    finally:
        os.unlink(fh.name)


ALPHA = ['a', 'b', 'c', ' ', '\t', '\t', '"', '"', '\n', '\r', '\r\n', 'é', '日', '1']
texts = ['', '\n', '\r\n', '\r', 'a', 'a\n', 'a\tb', 'a\tb\n', 'a\t', 'a\t\t', '\ta', 'a\tb\r\nc\td\r\n', 'a\r\n\r\nb',
         '"a"', '"a"\tb', '"a\tb"', '"a""b"', '"a\nb"', '"a\r\nb"', '"a\rb"', '"unterminated', '"unterminated\n',
         'a"b', 'a"b"c', '"a"b', '"a"b"c"', '""', '""\t""', '"" ', '" "', 'a\t"b\tc"\td', ' \t ', '\t\t\t',
         '"a"\n"b"\n', '"a\n', 'x\n\n\ny', '"multi\nline\ttab""q"\nz', 'a\r', 'a\rb', 'ünï\tcödé\n日本\t😀',
         'h1\th2\th3\n1\t2\t3\n4\t5\n\n6\t7\t8\n', 'h1\th2\n1\t2\t3\n', '\nh1\th2\n1\t2\n', 'h\th\n1\t2\n',
         '"q""""\t"\n"', 'ab"\tcd"ef', '"a"  \tb', '"a"\t', '"a"\n\n']
for _ in range(260 * SCALE):
    texts.append(''.join(rng.choice(ALPHA) for _ in range(rng.randrange(0, 24))))
tsv_read = []
for text in texts:
    try:
        rows, records = read_text_mode(text)
    except csv.Error as exc:  # pragma: no cover - none expected in text mode
        raise SystemExit(f'csv.Error for {text!r}: {exc}')
    tsv_read.append({'text': text, 'rows': rows, 'records': records})
FIELDS = ['', 'a', 'b c', 'x\ty', 'q"r', '"', 'l1\nl2', 'cr\rx', 'crlf\r\nx', 5, -3, 0, 2 ** 70, None, 'é', '日本', ' lead', 'trail ']
tsv_write = []
for _ in range(140 * SCALE):
    table = [[rng.choice(FIELDS) for _ in range(rng.choice((0, 1, 1, 2, 3, 5)))] for _ in range(rng.randrange(0, 6))]
    for eol in ('\r\n', '\n'):
        out = io.StringIO(newline='')
        writer = csv.writer(out, delimiter='\t', lineterminator=eol)
        writer.writerows(table)
        tsv_write.append({'rows': table, 'eol': eol, 'text': out.getvalue()})
write('tsv_read_cases.json', json.dumps(tsv_read, ensure_ascii=False, separators=(',', ':')) + '\n')
write('tsv_write_cases.json', json.dumps(tsv_write, ensure_ascii=False, separators=(',', ':')) + '\n')
