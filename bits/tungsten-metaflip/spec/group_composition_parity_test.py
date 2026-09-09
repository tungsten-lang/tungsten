#!/usr/bin/env python3
"""Independent bucket DP, linear substitution and full GF(2) tensor replay."""
from collections import defaultdict
from hashlib import sha256
from itertools import product
from pathlib import Path
import subprocess
import sys
import tempfile
from packed_composition_parity_test import ROOT, EDGES, bits, exact, naive, orient, parse_terms

RUNTIME = ROOT/'bits/tungsten-metaflip/lib/metaflip'


def narrow(root, key):
    raw = (root/'objects'/f'{key}.tensor').read_bytes()
    assert sha256(raw).hexdigest() == key
    lines = raw.decode().splitlines(); header = lines.pop(0).split()
    shape = tuple(map(int, header[1:4]))
    terms = [tuple(map(int, line.split())) for line in lines]
    assert header == ['MFR1', *map(str, shape), str(len(terms))]
    assert terms == sorted(terms)
    exact(shape, terms)
    return shape, terms


def bank(root, key, scale):
    raw = (root/'composition/banks'/key).read_bytes()
    assert sha256(raw).hexdigest() == key
    fields = raw.decode().split()
    assert len(fields) == 8 and fields[:2] == ['MFC_BANK1', str(scale)]
    assert raw == (' '.join(fields)+'\n').encode()
    leaves = {}
    for k, identity in enumerate(fields[2:], 1):
        shape, terms = narrow(root, identity)
        assert shape == (k, scale, scale)
        leaves[k] = terms
    return leaves


def plan(terms, axis, costs):
    buckets = defaultdict(list)
    for i, term in enumerate(terms):
        buckets[term[axis]].append(i)
    # Tuple minimization spells out the tie rule independently: larger k.
    dp, choices = [0], [0]
    for n in range(1, len(terms)+1):
        cost, neg_k = min((dp[n-k]+costs[k], -k) for k in costs if k <= n)
        dp.append(cost); choices.append(-neg_k)
    groups = []
    for members in buckets.values():
        n = len(members)
        while n:
            k = choices[n]
            groups.append(members[n-k:n]); n -= k
    return sum(costs[len(g)] for g in groups), groups


def expected_groups(shape, terms, axis, scale, leaves):
    price, groups = plan(terms, axis, {k:len(v) for k,v in leaves.items()})
    expand = (2,0,1)[axis]
    scales = tuple(1 if j == expand else scale for j in range(3))
    target = tuple(d*s for d,s in zip(shape,scales))
    perm = ((1,2,0),(0,1,2),(1,0,2))[axis]
    oriented = {k:orient((k,scale,scale),leaf,perm) for k,leaf in leaves.items()}
    result = set()
    for members in groups:
        k = len(members)
        dims = tuple(s*k if j == expand else s for j,s in enumerate(scales))
        maps = []
        for f,(r,c) in enumerate(EDGES):
            values = []
            for i,j in product(range(dims[r]),range(dims[c])):
                coords = [0,0,0]; coords[r] = i//scales[r]; coords[c] = j//scales[c]
                parent = terms[members[coords[expand]]][f]
                values.append(sum(1 << ((b//shape[c]*scales[r]+i%scales[r])*target[c]
                                         +b%shape[c]*scales[c]+j%scales[c]) for b in bits(parent)))
            maps.append(values)
        for term in oriented[k]:
            mapped = []
            for f,v in enumerate(term):
                image = 0
                for b in bits(v): image ^= maps[f][b]
                mapped.append(image)
            if 0 not in mapped:
                t = tuple(mapped)
                if t in result: result.remove(t)
                else: result.add(t)
    return target, sorted(result), price


def check(binary):
    subprocess.run([binary,'--plan-test'],check=True,timeout=30)
    seeds = RUNTIME/'seeds/gf2'
    parents = [((2,3,2), naive((2,3,2))), ((1,63,1), naive((1,63,1)))]
    for shape, name, rank in [
        ((2,2,2), 'matmul_2x2_rank7_strassen_gf2.txt', 7),
        ((3,3,3), 'matmul_3x3_rank23_d139_gf2.txt', 23),
        ((4,4,4), 'matmul_4x4_rank47_d450_gf2.txt', 47),
        ((2,2,6), 'matmul_2x2x6_rank21_strassen_blocks_gf2.txt', 21),
        ((2,2,8), 'matmul_2x2x8_rank28_catalog_gf2.txt', 28),
        ((2,2,9), 'matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt', 32),
    ]:
        parents.append((shape, parse_terms((seeds/name).read_bytes(), rank)))
    for copies in (2,80):
        terms = naive((2,2,2)); parents.append(((2,2,2), terms+[terms[0]]*copies))
    with tempfile.TemporaryDirectory(prefix='metaflip-groups-') as directory:
        root = Path(directory); (root/'objects').mkdir()
        ids, leaves = {}, {}
        for scale in (2,3,4):
            p = subprocess.run([binary,'--bank',directory,str(RUNTIME),str(scale)],
                               capture_output=True,text=True,check=True,timeout=60)
            ids[scale] = p.stdout.strip().splitlines()[-1]
            leaves[scale] = bank(root,ids[scale],scale)
            assert [len(leaves[scale][k]) for k in range(1,7)] == {
                2:[4,7,11,14,18,21], 3:[9,15,23,29,36,44], 4:[16,26,38,47,60,73]}[scale]
            again = subprocess.run([binary,'--bank',directory,str(RUNTIME),str(scale)],
                                   capture_output=True,text=True,check=True,timeout=60)
            assert again.stdout.strip().splitlines()[-1] == ids[scale]
        cases = 0
        for shape, terms in parents:
            terms = sorted(terms); exact(shape,terms)
            data = (f'MFR1 {" ".join(map(str,shape))} {len(terms)}\n'
                    +''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()
            key = sha256(data).hexdigest(); (root/'objects'/f'{key}.tensor').write_bytes(data)
            for axis,scale in product(range(3),(2,3,4)):
                output = root/'output.tensor'
                p = subprocess.run([binary,'--compose',directory,key,ids[scale],str(axis),str(scale),str(output)],
                                   capture_output=True,text=True,check=True,timeout=60)
                target, want, price = expected_groups(shape,terms,axis,scale,leaves[scale])
                lines = output.read_text().splitlines(); header = lines.pop(0).split()
                got = [tuple(int(v,16) for v in line.split()) for line in lines]
                assert header == ['MFW1', *map(str,target), str(len(want))]
                assert got == want and f'price={price} ' in p.stdout
                exact(target,got)
                if shape == (2,2,8) and axis == 0 and scale == 4:
                    assert target == (8,8,8) and price == len(got) == 329
                cases += 1
    print(f'PASS grouped composition: 18 exact leaves; {cases} independent full tensor/term-set replays; known 8x8x8/r329')


if __name__ == '__main__':
    check(sys.argv[1])
