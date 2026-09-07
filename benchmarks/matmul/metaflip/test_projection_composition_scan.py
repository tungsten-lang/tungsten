import itertools
import random
import unittest
from collections import Counter

from projection_composition_scan import ProjectionCache, families, validate_keep

EDGES=((0,1),(1,2),(0,2))


def naive(shape):
    n,m,p=shape
    return [(1<<(i*m+j),1<<(j*p+k),1<<(i*p+k)) for i,j,k in itertools.product(range(n),range(m),range(p))]


def direct(shape,terms,keep):
    counts=Counter()
    for term in terms:
        result=[]
        for word,(a,b) in zip(term,EDGES):
            out=0
            for i,old_i in enumerate(keep[a]):
                for j,old_j in enumerate(keep[b]):
                    out|=((word>>(old_i*shape[b]+old_j))&1)<<(i*len(keep[b])+j)
            result.append(out)
        if all(result):counts[tuple(result)]+=1
    return sorted(t for t,n in counts.items() if n%2)


class ProjectionCompositionTest(unittest.TestCase):
    def test_all_nonempty_restrictions_of_small_naive_tensor(self):
        shape=(2,3,2);terms=naive(shape);cache=ProjectionCache(shape,terms)
        choices=[sum((list(itertools.combinations(range(n),k)) for k in range(1,n+1)),[]) for n in shape]
        for keep in itertools.product(*choices):
            actual=cache.restrict(keep,True)
            self.assertEqual(actual,sorted(naive(tuple(map(len,keep)))))
            self.assertEqual(cache.restrict(keep),len(actual))

    def test_matches_independent_bit_grid_with_duplicates_and_zeros(self):
        rng=random.Random(949907)
        for _ in range(150):
            shape=(3,4,5)
            terms=[tuple(rng.randrange(1<<(shape[a]*shape[b])) for a,b in EDGES) for _ in range(24)]
            terms+=terms[:3]
            keep=tuple(tuple(sorted(rng.sample(range(n),rng.randrange(1,n+1)))) for n in shape)
            cache=ProjectionCache(shape,terms);expected=direct(shape,terms,keep)
            self.assertEqual(expected,cache.restrict(keep,True))
            self.assertEqual(len(expected),cache.restrict(keep))

    def test_newly_equal_terms_cancel(self):
        cache=ProjectionCache((2,1,1),[(1,1,1),(3,1,1)])
        self.assertEqual([],cache.restrict(((0,),(0,),(0,)),True))

    def test_bad_coordinates_and_masks_are_rejected(self):
        for keep in [((0,0),(0,),(0,)),((1,0),(0,),(0,)),((2,),(0,),(0,)),
                     ((),(0,),(0,)),((True,),(0,),(0,))]:
            with self.assertRaises(ValueError):validate_keep((2,2,2),keep)
        with self.assertRaises(ValueError):ProjectionCache((2,2,2),[(16,1,1)])

    def test_family_counts_and_explicit_large_family_skip(self):
        rows=list(families((6,6,9),[(6,6,6)],20000))
        self.assertEqual(489,rows[0][2])
        self.assertEqual(84,rows[1][2])
        skipped=list(families((9,9,9),[(6,6,6)],20000))[-1]
        self.assertIsNone(skipped[1]);self.assertEqual(592704,skipped[2])


if __name__=='__main__':unittest.main()
