#!/usr/bin/env python3
"""Independent arbitrary-integer replay of native packed pair compositions."""
from collections import defaultdict
from hashlib import sha256
from itertools import product
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'benchmarks/matmul/metaflip'))
from verify_representation_portfolio import parse_terms
from verify_coordinate_projections import project_grid
from verify_cofactor_mergers import compress_shared
from pair_reduction_scan import reduce_pairs

EDGES = ((0,1), (1,2), (0,2))


def bits(x):
    while x:
        lo = x & -x
        yield lo.bit_length()-1
        x ^= lo


def exact(shape, terms):
    n,m,p = shape
    fibers = defaultdict(int)
    for u,v,w in terms:
        assert 0 < u < 1 << (n*m) and 0 < v < 1 << (m*p) and 0 < w < 1 << (n*p)
        for a in bits(u):
            for b in bits(v):
                fibers[a,b] ^= w
    for i,j,k in product(range(n), range(m), range(p)):
        fibers[i*m+j, j*p+k] ^= 1 << (i*p+k)
    assert not any(fibers.values())


def naive(shape):
    n,m,p = shape
    return [(1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
            for i,j,k in product(range(n),range(m),range(p))]


def orient(shape, terms, perm):
    result = []
    for term in terms:
        row = []
        for a,b in EDGES:
            r,c = perm[a],perm[b]
            old = EDGES.index(tuple(sorted((r,c))))
            value = term[old]
            if r > c:
                value = sum(1 << ((v % shape[r])*shape[c]+v//shape[r]) for v in bits(value))
            row.append(value)
        result.append(tuple(row))
    return result


def expected(shape, terms, axis, k, pair):
    expand = (2,0,1)[axis]
    scale = tuple(1 if j == expand else k for j in range(3))
    leaf_shape = tuple(2*s if j == expand else s for j,s in enumerate(scale))
    perm = ((1,2,0),(0,1,2),(1,0,2))[axis]
    pair = orient((2,k,k), pair, perm)
    groups, used = [], set()
    for i,t in enumerate(terms):
        if i in used:
            continue
        partner = next((j for j in range(i+1,len(terms)) if j not in used and terms[j][axis] == t[axis]), None)
        members = [i] if partner is None else [i,partner]
        used.update(members); groups.append(members)
    result = set()
    for members in groups:
        dims = scale if len(members) == 1 else leaf_shape
        leaf = naive(scale) if len(members) == 1 else pair
        maps = []
        for f,(r,c) in enumerate(EDGES):
            values = []
            for i,j in product(range(dims[r]),range(dims[c])):
                coords = [0,0,0]; coords[r]=i//scale[r]; coords[c]=j//scale[c]
                parent = terms[members[coords[expand]]][f]
                values.append(sum(1 << ((b//shape[c]*scale[r]+i%scale[r])*(shape[c]*scale[c])+b%shape[c]*scale[c]+j%scale[c]) for b in bits(parent)))
            maps.append(values)
        for term in leaf:
            t = []
            for f,v in enumerate(term):
                out = 0
                for b in bits(v):
                    out ^= maps[f][b]
                t.append(out)
            if 0 not in t:
                t = tuple(t)
                if t in result: result.remove(t)
                else: result.add(t)
    return tuple(x*y for x,y in zip(shape,scale)), sorted(result)


def leaf_schemes():
    seeds = ROOT / 'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'
    two = parse_terms((seeds/'matmul_2x2_rank7_strassen_gf2.txt').read_bytes(),7)
    source = parse_terms((seeds/'matmul_2x3x5_rank26_peterson_2026_block15_11_gf2.txt').read_bytes(),26)
    three = project_grid((2,3,5),source,[[0,1],[0,1,2],[0,1,2]])
    three,_ = reduce_pairs(three,(0,1,2)); three,_ = compress_shared(three,max_bits=63)
    four = []
    for jr,kr in product((0,2),repeat=2):
        for term in two:
            offsets = (0,jr,kr)
            four.append(tuple(sum(1 << ((b//2+offsets[r])*4+b%2+offsets[c]) for b in bits(v))
                              for v,(r,c) in zip(term, EDGES)))
    assert len(three) == 15
    return {2:two,3:three,4:four}


def check(binary, external=None):
    subprocess.run([binary],check=True,timeout=30)
    seeds = ROOT / 'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'
    parents = [((2,3,2),naive((2,3,2))), ((2,2,2),parse_terms((seeds/'matmul_2x2_rank7_strassen_gf2.txt').read_bytes(),7)),
               ((3,3,3),parse_terms((seeds/'matmul_3x3_rank23_d139_gf2.txt').read_bytes(),23)),
               ((4,4,4),parse_terms((seeds/'matmul_4x4_rank47_d450_gf2.txt').read_bytes(),47)),
               ((1,63,1),naive((1,63,1)))]
    # Redundant terms test parity cancellation and non-injective group maps.
    redundant = naive((2,2,2)); redundant += [redundant[0]]*2
    parents.append(((2,2,2),redundant))
    # 80 same-U terms exercises a larger bucket and input parity reduction.
    many = naive((2,2,2)); many += [many[0]]*80
    parents.append(((2,2,2),many))
    if external:
        parents.append(((4,7,4),parse_terms(Path(external).read_bytes(),85)))
    leaves = leaf_schemes()
    with tempfile.TemporaryDirectory(prefix='metaflip-packed-') as directory:
        root = Path(directory); (root/'objects').mkdir()
        def store(shape, terms):
            exact(shape,terms)
            data = (f'MFR1 {" ".join(map(str,shape))} {len(terms)}\n'+''.join(' '.join(map(str,t))+'\n' for t in sorted(terms))).encode()
            key=sha256(data).hexdigest(); (root/'objects'/f'{key}.tensor').write_bytes(data)
            return key
        leafids = {k:store((2,k,k),t) for k,t in leaves.items()}
        cases = 0
        for shape,terms in parents:
            terms = sorted(terms); key=store(shape,terms)
            for axis,k in product(range(3),range(2,5)):
                path=root/'output.tensor'
                subprocess.run([binary,'--compose',directory,key,leafids[k],str(axis),str(k),str(path)],check=True,timeout=30,stdout=subprocess.DEVNULL)
                target, expected_terms = expected(shape,terms,axis,k,leaves[k])
                lines=path.read_text().splitlines(); header=lines.pop(0).split()
                actual=[tuple(int(v,16) for v in line.split()) for line in lines]
                assert header == ['MFW1',*map(str,target),str(len(actual))]
                assert actual == expected_terms
                exact(target,actual)
                if shape == (4,7,4) and axis == 2 and k == 3:
                    assert target == (12,7,12) and len(actual) == 651
                cases += 1
    print(f'PASS packed composition: {cases} full independent tensor/term-set replays')


if __name__ == '__main__':
    check(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else None)
