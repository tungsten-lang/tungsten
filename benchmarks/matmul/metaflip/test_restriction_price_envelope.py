from itertools import combinations_with_replacement
from math import prod
import random
import unittest

from restriction_price_envelope import restriction_envelope, screen, verify_envelope


class RestrictionEnvelopeTest(unittest.TestCase):
    def prices(self,n=5):
        return {s:prod(s) for s in combinations_with_replacement(range(1,n+1),3)}

    def plan(self,prices):
        return dict(complete=True,field='GF(2)',record_claim=False,
            model_shapes=list(prices),baseline_recipes=[dict(kind='seed',rank=r) for r in prices.values()])

    def test_naive_table_stays_unchanged(self):
        prices=self.prices()
        self.assertEqual(restriction_envelope(prices),{s:(r,s) for s,r in prices.items()})

    def test_all_roots_match_brute_force_supersets(self):
        rng=random.Random(822607)
        for _ in range(30):
            prices={s:rng.randrange(1,prod(s)+1) for s in self.prices()}
            actual=restriction_envelope(prices)
            for target,(rank,source) in actual.items():
                expected=min(r for s,r in prices.items() if all(a<=b for a,b in zip(target,s)))
                self.assertEqual(rank,expected)
                self.assertEqual(prices[source],rank)
                self.assertTrue(all(a<=b for a,b in zip(target,source)))

    def test_reference_is_corrected_before_counting_a_crossing(self):
        prices=self.prices(3);prices[(3,3,3)]=11
        refs=self.prices(3);refs[(3,3,3)]=10
        result=screen(self.plan(prices),dict(complete=True,record_claim=False,
            rows=[dict(shape=s,reference=r) for s,r in refs.items()]))
        row=next(r for r in result['rows'] if r['shape']==(2,3,3))
        self.assertEqual((row['rank'],row['raw_rank'],row['reference'],row['raw_reference']),(11,18,10,18))
        self.assertFalse(row['below_reference']);self.assertFalse(row['new_crossing'])
        self.assertFalse(result['record_claim']);self.assertFalse(result['constructive_sources_reverified'])

    def test_malformed_tables_and_false_witness_roots_rejected(self):
        prices=self.prices(3)
        for bad in ({},dict(list(prices.items())[1:]),dict(prices,**{'bad':1}),
                    {**prices,(1,2,3):True},{**prices,(3,2,3):7}):
            with self.assertRaises(ValueError):restriction_envelope(bad)
        prices[(3,3,3)]=7;closed=restriction_envelope(prices)
        for replacement in ((8,(3,3,3)),(7,(1,1,1)),(18,(2,3,3))):
            bad=dict(closed);bad[(2,3,3)]=replacement
            with self.assertRaises(ValueError):verify_envelope(prices,bad)
        with self.assertRaises(ValueError):screen(dict(self.plan(prices),complete=False))
        with self.assertRaises(ValueError):screen(dict(self.plan(prices),record_claim=True))
        plan=self.plan(prices);plan['model_shapes'].append((1,1,1))
        with self.assertRaises(ValueError):screen(plan)


if __name__=='__main__':unittest.main()
