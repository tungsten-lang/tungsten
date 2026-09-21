import re, sys, hashlib
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
# name string constants by CONTENT so table order does not matter
strs = {}
for m in re.finditer(r'^(@\.str\.\d+) = [^\n]* c"((?:[^"\\]|\\.)*)"', text, re.M):
    strs[m.group(1)] = '@.str.<' + hashlib.sha1(m.group(2).encode()).hexdigest()[:10] + '>'
ids = {}
def canon(m):
    k = m.group(0)
    if k in strs: return strs[k]
    if k not in ids: ids[k] = '%s#%d' % (m.group(1), len(ids))
    return ids[k]
SYM = re.compile(r'(__wy_|@\.str\.|@\.wfm\.|@\.wcs\.)[0-9A-Za-z_]+')
META = re.compile(r'^\s*\{ ptr(, ptr)*, i32, i32 \} \{')
out = []
for line in text.split('\n'):
    if META.match(line) or '@__w_loc_set' in line:
        line = re.sub(r'i32 \d+', 'i32 N', line)
    out.append(SYM.sub(canon, line))
# the string table itself: compare as a sorted set
head = sorted(l for l in out if l.startswith('@.str.<'))
body = [l for l in out if not l.startswith('@.str.<')]
open(dst, 'w').write('\n'.join(head + body))
