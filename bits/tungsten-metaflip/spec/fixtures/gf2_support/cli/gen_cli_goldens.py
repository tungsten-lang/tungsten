#!/usr/bin/env python3
"""Goldens for spec/gf2_support/cli_cases.w, made by the real argparse.

Each parser shape below is the declaration of a record-hunt tool (the file it comes
from is named next to it); `synthetic` shapes exercise features the port supports but
no single original combines (short options with values, positional lists, a usage
override).  Every shape is built from one JSON-able spec, written to parsers.json, so
the Tungsten test builds exactly the parser Python built.  The vectors are parsed with
`allow_abbrev=False` (the port refuses --prefix abbreviations, see cli.w) and
COLUMNS=80, and every outcome is recorded: the namespace, the usage or error text that
argparse printed, or the help text.

usage: gen_cli_goldens.py [--out DIR] [--random N] [--soup N] [--seed S] [--wrap N] [--widths]
  --random N  random argument vectors per parser on top of the fixed ones (default 3)
  --soup N    uniform random token sequences per parser (default 0)
  --wrap N    random textwrap cases (default 24)
The committed fixtures are the defaults; the evidence runs use larger N into a scratch
directory (GF2_CLI_GOLDEN=DIR makes cli_cases.w read that directory instead).
"""
import argparse
import ast
import contextlib
import io
import json
import os
import random
import re
import sys
import textwrap
from pathlib import Path

os.environ['COLUMNS'] = '80'
HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[3] / 'tools'          # bits/tungsten-metaflip/tools


def docstring(path):
    return ast.get_docstring(ast.parse(Path(path).read_text()), clean=False)


def first_paragraph(path):
    return docstring(path).split('\n\n')[0]


def a(name, **kw):
    return dict(name=name, **kw)


# --- the parser shapes ----------------------------------------------------------------

BOARD = dict(  # tools/gf2_record_board.py main()
    id='board', prog='gf2_record_board.py', description=first_paragraph(TOOLS / 'gf2_record_board.py'),
    bases=[['--lille', 'L', '--witness', 'w']],
    args=[a('--lille', required=True), a('--matmulcatalog'), a('--fmm-repo'), a('--fmm-revision', default='HEAD'),
          a('--extra-repo', action='append', default=[]),
          a('--witness', action='append', required=True, help='file or directory (repeatable)'),
          a('--cache', help='JSON verification cache keyed by SHA-256'),
          a('--jobs', type='int', default=6, help='processes for verifying new witness files'),
          a('--json', help='write every row here'),
          a('--verbose', short='-v', action='store_true')])

VERIFY = dict(  # tools/verify_gf2_lineage.py main()
    id='verify', prog='verify_gf2_lineage.py', description=first_paragraph(TOOLS / 'verify_gf2_lineage.py'),
    bases=[['b']],
    args=[a('bundle', type='path'), a('--replay-walk', help='compiled tools/wide_rect_walk.w'),
          a('--replay-max-rank', type='int', default=10 ** 9, help='replay only walks whose result has at most this rank'),
          a('--source', action='append', default=[], help='NAME=CLONE for re-derivation'),
          a('--cache-dir', default='mmc-cache', help='matmulcatalog replay cache'),
          a('--repo-root', type='path', help='checkout root for `retained` rows'),
          a('--no-ruby', action='store_true', help='skip the independent Ruby check')])

PUBLIC = dict(  # tools/screen_public_ternary_gf2.py main(): subcommands seeds / walk
    id='public', prog='screen_public_ternary_gf2.py', description=first_paragraph(TOOLS / 'screen_public_ternary_gf2.py'),
    bases=[['seeds', '--repo', 'r', '--out', 'o'], ['walk', '--seeds', 's', '--walker', 'w', '--out', 'o']],
    args=[dict(subcommands=dict(dest='command', required=True, commands=[
        dict(name='seeds', help='convert public integer schemes to exact GF(2) seeds', args=[
            a('--repo', required=True, help='local (partial) clone in FastMatrixMultiplication format'),
            a('--revision', default='HEAD'), a('--url', help='canonical repository URL recorded in the manifest'),
            a('--out', required=True, help='new output directory'), a('--min-dim', type='int', default=2),
            a('--min-max-dim', type='int', default=5, help='skip shapes whose largest side is smaller'),
            a('--max-dim', type='int', default=16),
            a('--include-rational', action='store_true', help='also try _Q files; only odd-denominator schemes pass the parity gate'),
            a('--alternatives', type='int', default=0, help='also convert every integer file within best+N (distinct GF(2) seeds only)')]),
        dict(name='walk', help='directed GF(2) walks from converted seeds', args=[
            a('--seeds', required=True), a('--walker', required=True, help='compiled tools/wide_rect_walk.w'),
            a('--out', required=True, help='JSONL log (appended; finished walks are skipped)'),
            a('--steps', type='int', default=40000000), a('--jobs', type='int', default=6),
            a('--repeats', type='int', default=1, help='independent nonces per seed'),
            a('--nonce-base', type='int', default=1), a('--min-rank', type='int', default=0),
            a('--largest-first', action='store_true', help='queue high-rank seeds first')])]))])

MMC_COMMON = [a('--clone', required=True, help='local matmulcatalog clone (a partial clone works)'),
              a('--revision', default='HEAD', help='pinned catalogue revision (recorded per seed)'),
              a('--cache-dir', default='mmc-cache')]
MMC = dict(  # tools/mmc_gf2_seeds.py main(): subcommands targets / replay sharing common()
    id='mmc', prog='mmc_gf2_seeds.py', description=first_paragraph(TOOLS / 'mmc_gf2_seeds.py'),
    bases=[['targets', '--clone', 'c', '--lille', 'l', '--board', 'b', '--out', 'o'], ['replay', '--clone', 'c', '--targets', 't', '--out', 'o']],
    args=[dict(subcommands=dict(dest='command', required=True, commands=[
        dict(name='targets', help='select catalogue schemes worth replaying', args=MMC_COMMON + [
            a('--lille', required=True, help='fmm_digest fmm_sota.json'), a('--fmm-repo', help='FastMatrixMultiplication clone'),
            a('--fmm-revision', default='HEAD'), a('--extra-repo', action='append', default=[]),
            a('--board', required=True, help='scoreboard JSON from gf2_record_board.py --json'),
            a('--slack', type='int', default=0, help='also accept ranks up to best listed + SLACK'),
            a('--min-dim', type='int', default=2), a('--out', required=True)]),
        dict(name='replay', help='materialize targets over GF(2) into exact seeds', args=MMC_COMMON + [
            a('--targets', required=True), a('--out', required=True),
            a('--board', help='scoreboard JSON: exact local witnesses may serve as leaves'),
            a('--allow-nonf2', action='store_true', help='diagnostics: also replay non-F2 schemes'),
            a('--retry-failed', action='store_true'),
            a('--only', nargs='*', help='canonical shapes or catalogue files to replay'),
            a('--jobs', type='int', default=1)])]))])

TOP_TWO = dict(  # tools/screen_top_two_projection_children.py main(): a required exclusive group
    id='top_two', prog='screen_top_two_projection_children.py',
    description=docstring(TOOLS / 'screen_top_two_projection_children.py'),
    groups=[dict(required=True)], bases=[['--digest', 'd'], ['--replay-manifest', 'm', '--output-dir', 'o']],
    args=[a('--digest', type='path', group=0), a('--replay-manifest', type='path', group=0),
          a('--output-dir', type='path')])

TWO_PASS = dict(  # tools/screen_two_pass_basis_children.py main(): exclusive group and choices
    id='two_pass', prog='screen_two_pass_basis_children.py',
    description=docstring(TOOLS / 'screen_two_pass_basis_children.py'), groups=[dict(required=True)],
    bases=[['--digest', 'd'], ['--replay-manifest', 'm', '--output-dir', 'o']],
    args=[a('--digest', type='path', group=0), a('--replay-manifest', type='path', group=0),
          a('--parent-set', choices=['structured-projections', 'first-generation', 'second-generation',
                                     'composed-chain', 'composed-descendants']),
          a('--output-dir', type='path'), a('--manifest-path', type='path')])

NEUTRAL = dict(  # tools/screen_neutral_basis_children.py main()
    id='neutral', prog='screen_neutral_basis_children.py',
    description=docstring(TOOLS / 'screen_neutral_basis_children.py'), groups=[dict(required=True)],
    bases=[['--digest', 'd'], ['--replay-manifest', 'm', '--output-dir', 'o']],
    args=[a('--digest', type='path', group=0), a('--replay-manifest', type='path', group=0),
          a('--depth', type='int', default=1), a('--parent-set', choices=['composed-chain', 'structured-projections']),
          a('--output-dir', type='path')])

COLLECT = dict(  # work/collect_chains.py main(): positionals and a float option
    id='collect', prog='collect_chains.py',
    # work/collect_chains.py is a campaign driver outside the repository: its description is copied
    description='Reconstruct seed -> projection/basis/walk chains for scoreboard witnesses from the campaign logs.',
    bases=[['b.json', 'o.json']],
    args=[a('board'), a('out'), a('--shapes'), a('--kinds', default='below_all,gf2_valid_only'),
          a('--max-rank', type='int', default=10 ** 9), a('--exclude', default='', help='root kinds to skip'),
          a('--budget-mb', type='float', default=1e9),
          a('--min-steps', type='int', default=1, help='skip chains with fewer search steps after the root'),
          a('--max-steps', type='int', default=10 ** 9, help='skip chains with more steps after the root')])

SEARCH = dict(  # tools/search_wide_projection_walks.py main()
    id='search', prog='search_wide_projection_walks.py', description=docstring(TOOLS / 'search_wide_projection_walks.py'),
    bases=[['--seed', 's', '--digest', 'd']],
    args=[a('--seed', type='path', required=True), a('--digest', type='path', required=True, help='dated rank table for scheduling only'),
          a('--walker', type='path'), a('--output-dir', type='path'), a('--depth', type='int', default=1),
          a('--beam', type='int', default=2), a('--steps', type='int', default=100000000),
          a('--nonce-base', type='int', default=19071), a('--list-only', action='store_true')])

# synthetic shapes: what the Ruby OptionParser of verify_tensor.rb needs (a usage banner, a
# positional list), short options that take values and combine, and star/plus positionals.
VERIFY_TENSOR = dict(
    id='verify_tensor', prog='verify_tensor.rb', description='Independent GF(2) reconstruction of tensor certificates.',
    usage='%(prog)s [--shape NxMxP] CERTIFICATE...',
    bases=[['c1'], ['--shape', '3x3x3', 'c1', 'c2']],
    args=[a('--shape', metavar='SHAPE'), a('certificates', nargs='+')])
SHORTS = dict(
    id='shorts', prog='shorts.py', description=None, epilog='Options may be spelled short or long.',
    bases=[['run1']],
    args=[a('--jobs', short='-j', type='int', default=4, help='worker count'), a('--verbose', short='-v', action='store_true'),
          a('--quiet', short='-q', action='store_true', help='fewer words'),
          a('--tag', short='-t', action='append'), a('name', help='the run name')])
STARS = dict(
    id='stars', prog='stars.py', description='A star positional after a plain one.',
    bases=[['h'], ['h', 'r1', 'r2']],
    args=[a('head'), a('rest', nargs='*', metavar='REST'), a('--opt'), a('--flag', action='store_true'),
          a('--many', nargs='+')])

GROUPED = dict(  # optional and non-contiguous exclusive groups, in the usage line and in the help
    id='grouped', prog='grouped.py', description='Two exclusive groups around a plain option.',
    groups=[dict(required=False), dict(required=True)], bases=[['--pick-a', 'x', 'target'], ['--big', '--right', 'target']],
    args=[a('--left', group=0, help='left or right, not both'), a('--other', type='int'), a('--right', action='store_true', group=0),
          a('--pick-a', group=1), a('--big', action='store_true', group=1), a('target')])

SPECS = [BOARD, VERIFY, PUBLIC, MMC, TOP_TWO, TWO_PASS, NEUTRAL, COLLECT, SEARCH, VERIFY_TENSOR, SHORTS, STARS, GROUPED]


# --- building the Python parsers -------------------------------------------------------

def add_args(target, entries, groups):
    for entry in entries:
        if 'subcommands' in entry:
            sub = entry['subcommands']
            holder = target.add_subparsers(dest=sub['dest'], required=sub['required'])
            for command in sub['commands']:
                child = holder.add_parser(command['name'], help=command.get('help'), allow_abbrev=False)
                add_args(child, command['args'], [])
            continue
        entry = dict(entry)
        name = entry.pop('name')
        names = [entry.pop('short')] + [name] if 'short' in entry else [name]
        group = entry.pop('group', None)
        kwargs = {}
        for key, value in entry.items():
            if key == 'type':
                if value == 'int':
                    kwargs['type'] = int
                elif value == 'float':
                    kwargs['type'] = float
            elif key == 'action':
                kwargs['action'] = value
            else:
                kwargs[key] = value
        if not name.startswith('-') and 'required' in kwargs:
            del kwargs['required']
        (groups[group] if group is not None else target).add_argument(*names, **kwargs)


def build(spec):
    parser = argparse.ArgumentParser(prog=spec['prog'], description=spec.get('description'), epilog=spec.get('epilog'),
                                     usage=spec.get('usage'), allow_abbrev=False)
    groups = [parser.add_mutually_exclusive_group(required=g['required']) for g in spec.get('groups', [])]
    add_args(parser, spec['args'], groups)
    return parser


def all_parsers(parser, found=None):
    """{prog: parser} for a parser and its subparsers."""
    found = {} if found is None else found
    found[parser.prog] = parser
    for action in parser._actions:
        if isinstance(action, argparse._SubParsersAction):
            for child in action.choices.values():
                all_parsers(child, found)
    return found


# --- vectors -------------------------------------------------------------------------

INT_VALUES = ['3', '-1', '0', 'x', '1.5', '', ' 7 ', '1_000', '+5', '1__0', '12345678901234567890', '-0', '0x10', '07']
FLOAT_VALUES = ['2.5', '-1e3', '.5', '5.', '1e', 'abc', '1_0.5', '3', '-2', '1e5', '+.5e-3', '']
STR_VALUES = ['v', 'a b', '-x', '', 'x=y', '--', '-5', 'HEAD', 'A']
NOISE = [['--nope'], ['--nope=1'], ['-z'], ['-zz'], ['--'], ['stray'], ['-5'], ['-.5'], ['-1x'], ['two words'], ['-'], [''],
         ['-h'], ['--help'], ['stray', 'more'], ['--', '-h'], ['--', 'a', 'b'], ['-x=1'], ['--=1'], ['--nope', 'stray']]


def option_items(entry):
    """Token groups an option can contribute: bare, with a value, with =value, wrong kinds."""
    name = entry['name']
    kind = entry.get('type', 'str')
    flag = entry.get('action') == 'store_true'
    spellings = [name] + ([entry['short']] if 'short' in entry else [])
    items = []
    for spelling in spellings:
        if flag:
            items += [[spelling], [spelling + '=1'], [spelling, 'extra']]
            continue
        if entry.get('choices'):
            values = entry['choices'][:2] + ['bogus']
        elif kind == 'int':
            values = INT_VALUES
        elif kind == 'float':
            values = FLOAT_VALUES
        else:
            values = STR_VALUES
        items.append([spelling])
        if entry.get('nargs') in ('*', '+'):
            items += [[spelling, 'a', 'b'], [spelling, 'a', 'b', 'c'], [spelling + '=a']]
        for value in values:
            items.append([spelling, value])
            if spelling.startswith('--'):
                items.append([spelling + '=' + value])
            else:
                items.append([spelling + value])
    return items


def positional_items(entry):
    if entry.get('nargs') in ('*', '+'):
        return [['p1'], ['p1', 'p2'], ['p1', 'p2', 'p3']]
    return [['p1'], ['p2']]


def vocabulary(spec):
    """(option items, positional items, {command: (items, positionals)}) of a parser."""
    items, positionals, commands = [], [], {}
    for entry in spec['args']:
        if 'subcommands' in entry:
            for command in entry['subcommands']['commands']:
                sub_items, sub_pos, _ = vocabulary(dict(args=command['args']))
                commands[command['name']] = (sub_items, sub_pos)
        elif entry['name'].startswith('-'):
            items += option_items(entry)
        else:
            positionals += positional_items(entry)
    return items, positionals, commands


def pool_for(spec, base):
    items, positionals, commands = vocabulary(spec)
    if commands and base and base[0] in commands:
        sub_items, sub_pos = commands[base[0]]
        return sub_items + sub_pos + NOISE
    return items + positionals + NOISE


def fixed_vectors(spec):
    """The vectors every run includes: nothing, help, each valid base with a few small
    mistakes, and an unknown subcommand."""
    vectors = [[], ['-h'], ['stray']]
    for base in spec['bases']:
        vectors += [base, base + ['-h'], base + ['--nope'], base + ['stray'], base[:-1]]
        # a unique-prefix abbreviation: argparse accepts it by default, the port refuses it
        vectors += [[token[:4] if token.startswith('--') and len(token) > 5 else token for token in base]]
        if not base[0].startswith('-'):
            vectors += [[base[0], '-h']]
    if any('subcommands' in entry for entry in spec['args']):
        vectors += [['bogus'], ['bogus', '--x']]
    return vectors


def random_vectors(spec, rng, count):
    """A valid base with up to three items from the parser's vocabulary spliced in (many of
    them wrong: bad values, unknown options, values missing), sometimes a token dropped."""
    out = []
    for _ in range(count):
        base = list(rng.choice(spec['bases']))
        pool = pool_for(spec, base)
        # keep the subcommand name first: splice after it
        head = 1 if any('subcommands' in entry for entry in spec['args']) and base else 0
        tokens = base[:]
        for _ in range(rng.randint(1, 3)):
            at = rng.randint(head, len(tokens))
            tokens[at:at] = rng.choice(pool)
        if rng.random() < 0.15 and len(tokens) > head:
            del tokens[rng.randint(head, len(tokens) - 1)]
        out.append(tokens)
    return out


def flat_tokens(spec):
    """Every option spelling of the parser (and its subparsers), value-ish words, and noise."""
    tokens = ['a', 'b', '3', '-3', 'x y', '', '-', '--', '-1', '-.5', '=', 'p1', 'p2', '--nope', '-z', '-h', '--help', '1.5', 'HEAD']
    def walk(entries):
        for entry in entries:
            if 'subcommands' in entry:
                for command in entry['subcommands']['commands']:
                    tokens.append(command['name'])
                    walk(command['args'])
            elif entry['name'].startswith('-'):
                tokens.extend([entry['name'], entry['name'] + '=a', entry['name'] + '=3'])
                if 'short' in entry:
                    tokens.extend([entry['short'], entry['short'] + '3', entry['short'] + '=3', entry['short'] + 'v'])
                for value in entry.get('choices', []):
                    tokens.append(value)
    walk(spec['args'])
    tokens += ['-vq', '-vv', '-qv3', '-jv', '-v3', '-tx', '-t=x']
    return tokens


def soup_vectors(spec, rng, count):
    """Uniform random token sequences: no valid base, nothing kept intact."""
    tokens = flat_tokens(spec)
    return [[rng.choice(tokens) for _ in range(rng.randint(0, 8))] for _ in range(count)]


# --- running argparse ---------------------------------------------------------------

def norm(value):
    if isinstance(value, list):
        return [norm(v) for v in value]
    return value


def outcome(parser, argv, usages, helps):
    out, err = io.StringIO(), io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            namespace = parser.parse_args(argv)
    except SystemExit as stop:
        code = stop.code or 0
        if code == 0:
            (prog,) = [p for p, text in helps.items() if text == out.getvalue()]
            assert err.getvalue() == ''
            return dict(k='help', u=prog)
        assert code == 2 and out.getvalue() == ''
        text = err.getvalue()
        lines = text.split('\n')
        assert lines[-1] == '' and 'error: ' in lines[-2]
        line = lines[-2]
        prog = line.split(': error: ')[0]
        assert text == usages[prog] + line + '\n', (argv, text)
        return dict(k='err', u=prog, e=line[len(prog) + len(': error: '):])
    return dict(k='ok', ns={key: norm(value) for key, value in vars(namespace).items()})


# --- textwrap and number cases --------------------------------------------------------

WORDS = ['alpha', 'be', 'a', 'cache', 'GF(2)', 'fmm-repo', '--flag-like', '-b', 'well-known-name', 'x-y', 'co-op', '3-4', 'sha-256',
         'goof-ball,', 'use', 'the', 'option!', 'a--b', 'foo--bar', '--', 'JSON', 'verification', 'keyed', 'by', 'SHA-256',
         'files', 'processes', 'repeatable)', '(file', 'or', 'directory', 'pseudo-randomly-generated', 'x', 'r2-d2',
         'un-', '-x-', 'a-b-c-d', 'e.g.', 'mid-word-hyphens-galore', 'supercalifragilisticexpialidocious-and-more', 'Zeta_2-3',
         'é-ê', 'naïve-approach', 'quick', 'brown', 'fox', 'jumps', 'over', 'lazy', 'dog', "don't", 'multiword\tsplit', 'line\nbreak']


def wrap_cases(rng, count):
    cases = []
    for _ in range(count):
        text = ' '.join(rng.choice(WORDS) for _ in range(rng.randint(1, 30)))
        if rng.random() < 0.3:
            text = '  ' + text.replace(' ', '   ', 2) + ' \n'
        width = rng.randint(11, 78)
        first = ' ' * rng.choice([0, 0, 2, 4])
        rest = ' ' * rng.choice([0, 0, 2, 4])
        flat = re.sub(r'\s+', ' ', text, flags=re.ASCII).strip()
        cases.append(dict(t=text, w=width, f=len(first), r=len(rest),
                          l=textwrap.wrap(flat, width, initial_indent=first, subsequent_indent=rest)))
    return cases


INT_STRINGS = ['0', '7', '-7', '+7', ' 7', '7 ', ' 7 ', '\t7\n', '1_000', '1__0', '_1', '1_', '-1_0', '+ 5', '- 5', '', ' ', '-', '+',
               '0x10', '010', '00', '-0', '1e3', '1.5', '.5', 'x', '12x', '٣',
               '9223372036854775807', '9223372036854775808', '-9223372036854775809', '123456789012345678901234567890',
               '1' * 40, '-' + '9' * 50, '0' * 30 + '5', '1_2_3_4', '1 2']
FLOAT_STRINGS = ['0', '1', '-1', '+1', '1.5', '-1.5', '.5', '5.', '-.5', '+.5', '.', '-.', '', ' 2.5 ', '1e5', '1E5', '1e+5', '1e-5',
                 '1e', 'e5', '1e5.5', '1.5.5', '1_0.5', '1._5', '1_.5', '1e1_0', '1e_1', '0.1', '0.30000000000000004',
                 '123456789.123456789', '1e22', '1e23', '5e-324', '2.2250738585072014e-308', '1.7976931348623157e308',
                 '9007199254740993', '4.35', '2.675', '1e400', '-1e400', '0e0', '-0.0', 'x', '1,5', '1 5', '--1', '0x1p3',
                 'inf', '-inf', '+Inf', 'Infinity', '-infinity', 'nan', 'NaN', '-nan', 'infinit', 'in f', 'nan1']


def number_cases():
    ints = []
    for text in INT_STRINGS:
        try:
            ints.append([text, int(text)])
        except ValueError:
            ints.append([text, None])
    floats = []
    for text in FLOAT_STRINGS:
        try:
            value = float(text)
            floats.append([text, 'nan' if value != value else value if abs(value) != float('inf') else ('inf' if value > 0 else '-inf')])
        except ValueError:
            floats.append([text, None])
    # the port refuses non-ASCII digits: keep them out of the agreement counts
    return dict(int=[c for c in ints if c[0].isascii()], float=[c for c in floats if c[0].isascii()])


def width_texts(everything=False):
    """Usage and help at narrow widths, to exercise the other wrapping branches."""
    out = {}
    plan = ((30, ['board', 'stars']), (50, ['board', 'public', 'stars']))
    if everything:
        plan = [(columns, [spec['id'] for spec in SPECS]) for columns in (14, 20, 24, 30, 40, 50, 60, 72, 80, 100, 140, 200)]
    for columns, ids in plan:
        os.environ['COLUMNS'] = str(columns)
        for spec in SPECS:
            if spec['id'] in ids:
                built = build(spec)
                assert built.format_help().split('\n\n')[0] + '\n' == built.format_usage()
                out.setdefault(str(columns), {})[spec['id']] = built.format_help()
    os.environ['COLUMNS'] = '80'
    return out


PROCESS_ARGVS = [
    ['--lille', 'L', '--witness', 'a', '--witness', 'b', '--jobs', '3', '-v'],
    ['--lille=L', '--witness=w', '--extra-repo', 'x', '--extra-repo', 'y', '--cache', 'c.json', '--json', 'o.json'],
    ['--lille', 'L', '--witness', 'w', '--json', 'o.json'],
    ['--jobs', 'x'], ['--lille'], ['--lille', 'L', '--witness', 'w', '--bogus'], ['-h'], [],
]


def process_cases():
    """What driver.w (the option set of gf2_record_board.py) prints for each argv on stdout and
    on stderr, and its exit status; the driver's own parser.error check included."""
    cases = []
    for argv in PROCESS_ARGVS:
        parser = build(BOARD)
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                namespace = parser.parse_args(argv)
                if namespace.json is not None and namespace.cache is None:
                    parser.error('--json needs --cache')
                print(json.dumps(vars(namespace), separators=(',', ':')))
            except SystemExit as stop:
                code = stop.code or 0
        cases.append(dict(a=argv, code=code, stdout=out.getvalue(), stderr=err.getvalue()))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--out', type=Path, default=HERE)
    parser.add_argument('--random', type=int, default=3)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--soup', type=int, default=0)
    parser.add_argument('--widths', action='store_true', help='usage and help of every parser at 12 widths')
    parser.add_argument('--wrap', type=int, default=24)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    usages, helps, cases = {}, {}, []
    for spec in SPECS:
        root = build(spec)
        family = all_parsers(root)
        for prog, member in family.items():
            usages[prog] = member.format_usage()
            helps[prog] = member.format_help()
    stats = {}
    for spec in SPECS:
        root = build(spec)
        vectors = fixed_vectors(spec) + random_vectors(spec, rng, args.random) + soup_vectors(spec, rng, args.soup)
        seen = set()
        kinds = {}
        for argv in vectors:
            key = tuple(argv)
            if key in seen:
                continue
            seen.add(key)
            result = outcome(root, argv, usages, helps)
            kinds[result['k']] = kinds.get(result['k'], 0) + 1
            cases.append(dict(p=spec['id'], a=argv, **result))
        stats[spec['id']] = (len(seen), kinds)
    for prog, text in helps.items():   # the usage block is the first paragraph of the help
        assert text.split('\n\n')[0] + '\n' == usages[prog], prog
    golden = dict(help=helps, cases=cases)
    (args.out / 'parsers.json').write_text(json.dumps(SPECS, separators=(',', ':'), ensure_ascii=False) + '\n')
    (args.out / 'golden.json').write_text(json.dumps(golden, separators=(',', ':'), ensure_ascii=False) + '\n')
    (args.out / 'wrap.json').write_text(json.dumps(wrap_cases(rng, args.wrap), separators=(',', ':'), ensure_ascii=False) + '\n')
    (args.out / 'numbers.json').write_text(json.dumps(number_cases(), separators=(',', ':'), ensure_ascii=False) + '\n')
    (args.out / 'widths.json').write_text(json.dumps(width_texts(args.widths), separators=(',', ':'), ensure_ascii=False) + '\n')
    (args.out / 'process.json').write_text(json.dumps(process_cases(), separators=(',', ':'), ensure_ascii=False) + '\n')
    for spec_id, (count, kinds) in stats.items():
        print(f'{spec_id:14} {count:4} vectors {kinds}')
    print(f'{len(cases)} vectors; {len(usages)} usage/help texts; wrote {args.out}')


if __name__ == '__main__':
    main()
