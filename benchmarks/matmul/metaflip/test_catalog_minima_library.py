import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import catalog_minima_library as library
from test_catalog_gf2_import import naive_rectangular


class CatalogLibraryTest(unittest.TestCase):
    def entry(self, rank=12, **extra):
        return dict(format=[2, 2, 3], rank=rank, verified=True, fields=["F2"], file=f"r{rank}.json", **extra)

    def test_minima_keep_all_ties_but_exclude_other_fields_and_families(self):
        rows = [self.entry(), self.entry(13), dict(self.entry(), file="tie.json", format=[3, 2, 2])]
        for changes in [dict(fields=["Q"]), dict(fields_not=["F2"]), dict(verified=False),
                        dict(commutative=True), dict(scheme_type="non_bilinear")]:
            rows.append(dict(self.entry(1), **changes))
        rows.append(dict(self.entry(1), format=[2, 2, 17]))
        self.assertEqual(["r12.json", "tie.json"], [e["file"] for e in library.minima(dict(schemes=rows), 16)])

    def test_duplicate_paths_bad_ranks_and_traversals_rejected(self):
        for rows in [[self.entry(), self.entry()], [self.entry(0)], [self.entry(True)]]:
            with self.assertRaises(ValueError):
                library.minima(dict(schemes=rows), 16)
        for name in ["../bad.json", "/bad.json", "a/../../bad.json", "a\\bad.json", ""]:
            with self.assertRaises(ValueError):
                library.source_path(dict(file=name))

    def test_cached_blob_is_reconstructed_and_checked_not_trusted(self):
        data, expected = naive_rectangular()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("cache", "sources", "witnesses"):
                (root / name).mkdir()
            raw = json.dumps(data).encode()
            blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
            cached = root / "cache" / (blob + ".json")
            cached.write_bytes(raw)
            entry = self.entry()
            tree = {library.source_path(entry): dict(type="blob", sha=blob)}
            row = library.fetch_one(entry, commit="a" * 40, tree=tree, root=root, caches=[root / "cache"])
            self.assertTrue(row["exact_f2_verified"])
            self.assertTrue(row["cached"])
            self.assertEqual(expected, (root / row["witness"]).read_text())
            cached.write_bytes(raw + b" ")
            with self.assertRaisesRegex(ValueError, "Git blob"):
                library.fetch_one(entry, commit="a" * 40, tree=tree, root=root, caches=[root / "cache"])

    def test_source_index_disagreement_rejected_before_import(self):
        good, _ = naive_rectangular()
        for changes in [dict(m=13), dict(fields=["Q"]), dict(fields_not=["F2"]),
                        dict(commutative=True), dict(scheme_type="non_bilinear"), dict(verified=False)]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'sources').mkdir()
                data = copy.deepcopy(good)
                data.update(changes)
                raw = json.dumps(data).encode()
                blob = hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest()
                (root / (blob + ".json")).write_bytes(raw)
                entry = self.entry()
                tree = {library.source_path(entry): dict(type="blob", sha=blob)}
                with self.assertRaisesRegex(ValueError, "source/index"):
                    library.fetch_one(entry, commit="a" * 40, tree=tree, root=root, caches=[root])


if __name__ == "__main__":
    unittest.main()
