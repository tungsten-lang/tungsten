#!/usr/bin/env python3
"""Golden data for spec/gf2_support_test.w: json.dumps output for random nested structures.

usage: gen_json_goldens.py OUT_DIR [COUNT [SEED [FUZZ_COUNT]]]

Writes into OUT_DIR
  structs.jsonl        one structure per line, json.dumps(x) (ASCII, default separators)
  dumps_<name>.jsonl   one line per structure: the JSON string literal of json.dumps(x, <options>)
  floats.tsv           bit pattern (hex) \t repr \t fixed / general / percent renderings \t repr(round(x, 2)) of finite doubles
  decimals.tsv         decimal text \t hex bit pattern of float(text) (or ERR)
  parse_cases.jsonl    {"input": text, "dumps": json.dumps(json.loads(text))} or {"input": text, "error": message}
  fuzz_cases.jsonl     the same for randomly spelled documents (odd whitespace, escapes, number spellings) and
                       for those documents with one random character deleted, inserted or replaced
  ruby_pretty.jsonl    {"i": line number in structs.jsonl, "out": JSON.pretty_generate(...)} from ruby (needs ruby)
The structures mix integers up to 2**200 (and the 2**47 / 2**63 / 2**64 boundaries), floats (random bit
patterns, subnormals, 1e16 / 1e-5 formatting boundaries, -0.0, NaN, infinities), strings with quotes,
backslashes, control characters, DEL, Latin-1, CJK, astral characters and lone surrogates, keys that
are empty or need escapes, empty containers and nesting up to depth 9.
"""
import json
import math
import random
import struct
import subprocess
import sys
from pathlib import Path

OPTIONS = {
    'default': dict(),
    'indent1': dict(indent=1),
    'indent2_sorted': dict(indent=2, sort_keys=True),
    'compact_utf8': dict(separators=(',', ':'), ensure_ascii=False),
    'indent4_utf8_sorted': dict(indent=4, ensure_ascii=False, sort_keys=True),
    'tab': dict(indent='\t'),
}

STRINGS = ['', 'a', 'abc', 'GF(2)', 'x"y', 'back\\slash', 'line\nbreak', 'tab\there', 'cr\rlf\n', '\x00nul', '\x1f', '\x7f del',
           'café', '×U⟨1,1,2⟩', 'snow ☃', '中文', 'emoji \U0001f600', '\ud83d lone', '\udc00', '/slash/',
           '  ', 'a' * 70, ' ' * 5, '\b\f']


def bits_float(rnd):
    while True:
        x = struct.unpack('<d', struct.pack('<Q', rnd.getrandbits(64)))[0]
        if math.isfinite(x):
            return x


def rand_float(rnd):
    pick = rnd.random()
    if pick < 0.35:
        return bits_float(rnd)
    if pick < 0.6:
        return round(rnd.uniform(-1000, 1000), rnd.choice([1, 2, 3, 5]))
    if pick < 0.75:
        return float(rnd.randint(-10**6, 10**6))
    return rnd.choice([0.0, -0.0, 1e16, 1e15, 1e-4, 1e-5, 5e-324, 1.7976931348623157e308, 0.1, 100.0, 1e22, 1e23,
                       math.nan, math.inf, -math.inf, 2.675, 9007199254740993.0, 0.30000000000000004])


def rand_int(rnd):
    pick = rnd.random()
    if pick < 0.4:
        return rnd.randint(-100, 1000)
    if pick < 0.6:
        return rnd.choice([0, 1, -1, 2**47 - 1, 2**47, -2**47, -2**47 - 1, 2**62, 2**63 - 1, 2**63, -2**63, 2**64, 2**64 - 1])
    return rnd.randint(-2**rnd.randint(8, 200), 2**rnd.randint(8, 200))


def rand_string(rnd):
    if rnd.random() < 0.5:
        return rnd.choice(STRINGS)
    return ''.join(rnd.choice(STRINGS[1:12] + ['0', 'Z', ' ', 'é', '\U0001f4a9']) for _ in range(rnd.randint(0, 6)))


def rand_value(rnd, depth):
    pick = rnd.random()
    if depth >= 9 or pick < 0.42:
        kind = rnd.random()
        if kind < 0.25:
            return rand_int(rnd)
        if kind < 0.45:
            return rand_float(rnd)
        if kind < 0.75:
            return rand_string(rnd)
        return rnd.choice([True, False, None])
    if pick < 0.72:
        return [rand_value(rnd, depth + 1) for _ in range(rnd.choice([0, 0, 1, 2, 3, 5]))]
    out = {}
    for _ in range(rnd.choice([0, 0, 1, 2, 3, 4])):
        out[rand_string(rnd)] = rand_value(rnd, depth + 1)
    return out


def write_floats(out, rnd, count):
    vals = [bits_float(rnd) for _ in range(count)]
    vals += [round(rnd.uniform(-1000, 1000), rnd.choice([1, 2, 3, 4])) for _ in range(count // 3)]
    vals += [0.0, -0.0, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308, 0.1, 100.0, 1e15, 1e16, 1e-4, 1e-5, 2.675, 0.125, 0.375, 1.5, 2.5, 3.5]
    with open(out / 'floats.tsv', 'w') as fh:
        for x in vals:
            small = abs(x) < 1e30
            row = [format(struct.unpack('<Q', struct.pack('<d', x))[0], '016x'), repr(x)]
            row += ['%.*f' % (p, x) if small else '-' for p in (0, 1, 2, 4, 6)]
            row += [format(x, '.%dg' % p) for p in (1, 3, 6, 17)]
            row += [format(x, '.%d%%' % p) if small else '-' for p in (0, 1)]
            row.append(repr(round(x, 2)) if abs(x) < 1e15 else '-')
            fh.write('\t'.join(row) + '\n')


def write_decimals(out, rnd, count):
    strs = []
    for _ in range(count):
        digits = ''.join(rnd.choice('0123456789') for _ in range(rnd.randint(1, 40)))
        strs.append('%s%se%d' % (rnd.choice(['', '-']), digits, rnd.randint(-330, 310)))
        cut = rnd.randint(0, len(digits))
        strs.append('%s.%s' % (digits[:cut] or '0', digits[cut:] or '0'))
    strs += ['9007199254740993', '9007199254740995', '4503599627370497.5', '1e400', '-1e400', '1e-400', '2.4703282292062327e-324',
             '2.4703282292062328e-324', '17976931348623157' + '0' * 292, '17976931348623158' + '0' * 292, '00012.5', '12.', '.5', '1_000.5',
             '+1.5', '  3.25  ', 'inf', '-Infinity', 'nan', '', '1e', 'e5', '1.2.3', '0x10', '1__0']
    with open(out / 'decimals.tsv', 'w') as fh:
        for s in strs:
            try:
                x = float(s)
            except ValueError:
                fh.write(s + '\tERR\n')
                continue
            fh.write(s + ('\tNAN\n' if x != x else '\t%016x\n' % struct.unpack('<Q', struct.pack('<d', x))[0]))


PARSE_CASES = ['', ' ', '[1, 2,]', '{"a": 1,}', '{"a" 1}', '{"a": 1 "b": 2}', '[1 2]', '{1: 2}', '[', '{', '"abc', '"a\\x"', '"a\\u12"',
               '"a\\u12zz"', '"tab\there"', '01', '-', '-a', '1.', '.5', '+1', '1e', '1e+', 'nul', 'truex', 'True', 'NaN', 'Infinity',
               '-Infinity', '-inf', '1 2', '[1] x', '{"a": 1}}', '"\\ud800"', '"\\ud800\\ud800"', '"\\ud83d\\ude00"', '1E5', '1e+5',
               '-0', '-0.0', '0.1e1', '[1,\n2,\n  x]', '\ufeff[1]', '[1,2]\n', '  [1]  ', '"\\/"', '"\\b\\f"', '{"a": 1, "a": 2}',
               '{"b": 1, "a": 2, "b": 3}', '123456789012345678901234567890', '-123456789012345678901234567890', '1.7976931348623157e309',
               '-1e999', '"\u00e9"', '"\u00e9\U0001f600"', '[[[]]]', '{"a": {"b": {}}}', '\x00', '"\x01"', '[1,,2]', '[,1]', '{,}', '[1]]', '[1,', '{"a":1,',
               '{"a":', '[1 ,2 , 3 ]', ' { "a" : [ 1 , 2 ] } ', '"\\u00e9"', '"\\uD834\\uDD1E"', '"\\uDD1E\\uD834"', '"\\u0000"', 'tru', 'fals', 'nulll',
               '[1e5,1E-5,1.5e+3,-2.5E-3]', '0.0', '-0e0', '1e-400', '123456789012345678', '1234567890123456789', '9223372036854775807',
               '9223372036854775808', '-9223372036854775808', '-9223372036854775809', '140737488355327', '140737488355328']


def write_parse_cases(out):
    with open(out / 'parse_cases.jsonl', 'w') as fh:
        for text in PARSE_CASES:
            try:
                row = {'input': text, 'dumps': json.dumps(json.loads(text))}
            except ValueError as exc:
                row = {'input': text, 'error': str(exc)}
            fh.write(json.dumps(row) + '\n')


WHITESPACE = ['', '', '', ' ', '  ', '\n', '\t', '\r\n', ' \n ']


def spell_string(rnd, text):
    """A JSON string literal for text with a random mix of raw characters and \\-escapes."""
    out = ['"']
    for ch in text:
        code = ord(ch)
        pick = rnd.random()
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif code < 32 or 0xD800 <= code <= 0xDFFF:
            out.append('\\u%04x' % code if rnd.random() < 0.5 else '\\u%04X' % code)
        elif ch == '/' and pick < 0.3:
            out.append('\\/')
        elif pick < 0.12:
            out.append('\\u%04x' % code if code < 0x10000 else ''.join('\\u%04x' % u for u in struct.unpack('<2H', ch.encode('utf-16-le'))))
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


def spell_number(rnd, value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, int):
        return str(value)
    if value != value:
        return 'NaN'
    if value in (math.inf, -math.inf):
        return 'Infinity' if value > 0 else '-Infinity'
    pick = rnd.random()
    if pick < 0.3:
        return repr(value)
    if pick < 0.5:
        return '%.17g' % value
    mant, _, exp = ('%.16e' % value).partition('e')
    exponent = int(exp)
    return mant + rnd.choice(['e', 'E']) + rnd.choice(['', '+']) * (exponent >= 0) + ('-' if exponent < 0 else '') + '0' * rnd.randint(0, 2) + str(abs(exponent))


def spell(rnd, value):
    ws = lambda: rnd.choice(WHITESPACE)
    if isinstance(value, dict):
        items = [ws() + spell_string(rnd, k) + ws() + ':' + ws() + spell(rnd, v) + ws() for k, v in value.items()]
        return '{' + ','.join(items) + '}'
    if isinstance(value, list):
        return '[' + ','.join(ws() + spell(rnd, v) + ws() for v in value) + ']'
    if isinstance(value, str):
        return spell_string(rnd, value)
    if value is None:
        return 'null'
    return spell_number(rnd, value)


def mutate(rnd, text):
    if not text:
        return text
    at = rnd.randrange(len(text))
    kind = rnd.random()
    if kind < 0.35:
        return text[:at] + text[at + 1:]
    if kind < 0.7:
        return text[:at] + rnd.choice('[]{},:"\\ 0123456789eE.-+tfnuNI\n\t\x01') + text[at:]
    if kind < 0.9:
        return text[:at] + rnd.choice('[]{},:"\\ 0123456789eE.-+tfnuNI') + text[at + 1:]
    return text[:at]


def write_fuzz(out, rnd, structs, count):
    rows = []
    for i in range(count):
        value = structs[i % len(structs)]
        text = spell(rnd, value)
        if rnd.random() < 0.5:
            text = mutate(rnd, text)
        try:
            row = {'input': text, 'dumps': json.dumps(json.loads(text))}
        except ValueError as exc:
            row = {'input': text, 'error': str(exc)}
        rows.append(row)
    with open(out / 'fuzz_cases.jsonl', 'w') as fh:
        for row in rows:
            fh.write(json.dumps(row) + '\n')
    return sum('error' in r for r in rows)


RUBY_PRETTY = """
require 'json'
File.readlines(ARGV[0]).each_with_index do |line, i|
  begin
    value = JSON.parse(line, allow_nan: false)
    out = JSON.pretty_generate(value)
    out.encode('UTF-8')
    raise 'invalid' unless out.valid_encoding?
    puts JSON.generate({'i' => i, 'out' => out})
  rescue StandardError, JSON::JSONError
    next
  end
end
"""


def write_ruby(out):
    result = subprocess.run(['ruby', '-e', RUBY_PRETTY, str(out / 'structs.jsonl')], capture_output=True, text=True, check=True)
    (out / 'ruby_pretty.jsonl').write_text(result.stdout)
    return result.stdout.count('\n')


def main():
    out = Path(sys.argv[1])
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 250
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 20260929
    fuzz = int(sys.argv[4]) if len(sys.argv) > 4 else count
    out.mkdir(parents=True, exist_ok=True)
    rnd = random.Random(seed)
    structs = [rand_value(rnd, 0) for _ in range(count)]
    structs = [{'id': i, 'value': v} if not isinstance(v, (dict, list)) else v for i, v in enumerate(structs)]
    with open(out / 'structs.jsonl', 'w') as fh:
        for x in structs:
            fh.write(json.dumps(x) + '\n')
    for name, kw in OPTIONS.items():
        with open(out / f'dumps_{name}.jsonl', 'w') as fh:
            for x in structs:
                fh.write(json.dumps(json.dumps(x, **kw)) + '\n')
    write_floats(out, rnd, max(200, count))
    write_decimals(out, rnd, max(100, count))
    write_parse_cases(out)
    fuzz_errors = write_fuzz(out, rnd, structs, fuzz)
    ruby = write_ruby(out)
    print(f'{count} structures, {len(OPTIONS)} option sets, {ruby} ruby renderings, {len(PARSE_CASES)} parse cases, {fuzz} fuzz documents ({fuzz_errors} malformed) -> {out}')


if __name__ == '__main__':
    main()
