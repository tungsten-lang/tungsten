import copy,importlib.util,json,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import memory_policy as p

G=2**30
PAGE=16384

def fixture(free=3,spec=1,purge=1,inactive=64,file=40,level=1,swap='0.00M',swapouts=0):
    counts={'Pages free':free,'Pages speculative':spec,'Pages purgeable':purge,
            'Pages inactive':inactive,'File-backed pages':file,
            'Pages occupied by compressor':4}
    vm='Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
    vm+='\n'.join(f'{k}: {int(v*G/PAGE)}.' for k,v in counts.items())
    vm+=f'\nSwapouts: {swapouts}.\n'
    ctl=f'kern.memorystatus_vm_pressure_level: {level}\nvm.swapusage: total = 8000.00M  used = {swap}  free = 8000.00M  (encrypted)\n'
    return p.parse(vm,ctl)

class PolicyTests(unittest.TestCase):
    def test_discount_and_overlap(self):
        f=fixture();self.assertEqual(f['immediate_bytes'],5*G)
        self.assertEqual(f['reclaim_credit_bytes'],19*G)
        self.assertEqual(f['estimated_headroom_bytes'],24*G)
        self.assertIsNone(p.reason(f))
    def test_anonymous_inactive_is_not_available(self):
        self.assertIn('headroom',p.reason(fixture(file=0)))
    def test_credit_bounded_by_inactive(self):
        f=fixture(inactive=6);self.assertEqual(f['reclaim_credit_bytes'],2*G)
    def test_reclaim_clamped(self):
        self.assertEqual(fixture(inactive=1)['reclaim_credit_bytes'],0)
    def test_warning_critical_unknown(self):
        for level in [0,2,4,7]:
            self.assertIn('pressure',p.reason(fixture(level=level)))
    def test_immediate_floor(self):
        self.assertIn('512 MiB',p.reason(fixture(free=0,spec=0,purge=0)))
    def test_swap_usage_growth(self):
        self.assertIn('256 MiB',p.reason(fixture(swap='256.00M'),fixture()))
    def test_swap_write_growth(self):
        self.assertIn('64 MiB',p.reason(fixture(swapouts=4096),fixture()))
    def test_stable_old_swap_allowed(self):
        self.assertIsNone(p.reason(fixture(swap='1.00G'),fixture(swap='1.00G')))
    def test_missing_fields_fail_closed(self):
        for vm,ctl in [('', ''),('page size of 16384 bytes',''),('', 'kern.memorystatus_vm_pressure_level: 1')]:
            with self.assertRaises(ValueError):p.parse(vm,ctl)
    def test_preflight_never_starts_child_under_warning(self):
        import memory_guard as guard
        from types import SimpleNamespace
        with tempfile.TemporaryDirectory() as d:
            report=Path(d)/'guard.json';marker=Path(d)/'started'
            args=SimpleNamespace(command=[sys.executable,'-c',f'open({str(marker)!r},"w").write("bad")'],
                                 limit_gib=1,sample_seconds=.1,report=report,timeout_seconds=1)
            with patch.object(guard,'read_system',return_value=fixture(level=2)):
                with self.assertRaises(SystemExit):guard.main(args)
            self.assertFalse(marker.exists());self.assertIn('pressure',json.loads(report.read_text())['reason'])

if __name__=='__main__':unittest.main()
