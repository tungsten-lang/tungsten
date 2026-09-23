#!/usr/bin/env python3
"""Independently expand retained rectangular GF(2) tensor certificates."""
import base64
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
METAFLIP = ROOT / 'bits/tungsten-metaflip'
CERTS = METAFLIP / 'tools/certificates/wide-rectangular-walk-20260922'
PORTFOLIO = METAFLIP / 'tools/certificates/structured-parent-portfolio-20260922/manifest.json'
VERIFIER = ROOT / 'benchmarks/matmul/metaflip/verify_block_composition_records.py'


class WideRectangularCertificateTest(unittest.TestCase):
    def check_certificate(self, shape, rank, digest, portfolio_shape, parent_rank, catalog_bound,
                          compressed=False):
        name = 'x'.join(map(str, shape))
        suffix = '.mfw.gz.b64' if compressed else '.mfw'
        raw = (CERTS / f'{name}-r{rank}{suffix}').read_bytes()
        if compressed:
            raw = gzip.decompress(base64.b64decode(raw.replace(b'\n', b''), validate=True))
        self.assertEqual(hashlib.sha256(raw).hexdigest(), digest)
        lines = raw.decode('ascii').splitlines()
        self.assertEqual(lines.pop(0), f'MFW1 {" ".join(map(str, shape))} {rank}')
        self.assertEqual(len(lines), rank)
        manifest = json.loads(PORTFOLIO.read_text())
        parent = next(row for row in manifest['rows'] if row['shape'] == list(portfolio_shape))
        self.assertEqual((parent['rank'], parent['catalog_recursive_bound']), (parent_rank, catalog_bound))

        spec = importlib.util.spec_from_file_location('wide_rectangular_independent', VERIFIER)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        body = ''.join('R ' + ' '.join(str(int(mask, 16)) for mask in line.split()) + '\n'
                       for line in lines).encode('ascii')
        with tempfile.TemporaryDirectory(prefix='metaflip-wide-rect-cert-') as tmp:
            path = Path(tmp) / 'candidate.txt'
            path.write_bytes(body)
            record = module.Record(name, shape, rank,
                                   path.name, hashlib.sha256(body).hexdigest())
            result = module._verify_one((Path(tmp), record))
        self.assertEqual((result.exact_rank, result.terms, result.tensor_ones),
                         (rank, rank, shape[0] * shape[1] * shape[2]))

    def test_9x5x20_rank_623(self):
        self.check_certificate((9, 5, 20), 623,
                               '04deeee17b7cd975f233aa9d952d988409266d2b91d60f44252df940925f0df5',
                               (5, 9, 20), 624, 629)

    def test_12x10x20_rank_1448(self):
        self.check_certificate((12, 10, 20), 1448,
                               'ce1223857ec1c7bf2215b248a5cbeb42c4171df2c648ee7d752fd9f822741df8',
                               (10, 12, 20), 1464, 1500)

    def test_12x10x25_rank_1836(self):
        self.check_certificate((12, 10, 25), 1836,
                               '9f6e46e1cbbf99417ab2f1ae3c36a92260809ef313e6540eabcaa065baab7c58',
                               (10, 12, 25), 1836, 1860, compressed=True)

    def test_16x28x25_rank_6223(self):
        self.check_certificate((16, 28, 25), 6223,
                               '049d2676a8f0e9c560026c5ad511faadc14debd415cc5d6d6c97e3407f3e3923',
                               (16, 25, 28), 6225, 6229, compressed=True)

    def test_12x10x19_rank_1421(self):
        self.check_certificate((12, 10, 19), 1421,
                               'a184dc5aeb7a90d5e88af72a4ec4eb73f58888ea9ce0caa5159b533ed0724de5',
                               (10, 12, 20), 1464, 1500, compressed=True)

    def test_16x27x25_rank_6080(self):
        self.check_certificate((16, 27, 25), 6080,
                               '7d6bdd7c300602617ad8f9c52b3638210391699394e69c55d7b86dc12bfd2ce3',
                               (16, 25, 28), 6225, 6229, compressed=True)

    def test_16x31x25_rank_6916(self):
        self.check_certificate((16, 31, 25), 6916,
                               'a31cfc6638245c110fcba943c4ed948889915210be74ced9d2c8f12b057e4e41',
                               (16, 25, 32), 7055, 7080, compressed=True)

    def test_16x29x25_rank_6534(self):
        self.check_certificate((16, 29, 25), 6534,
                               'bb01d2f6b1516808bc22a9edfd3ca2a0b36da9ea9c440a46846a07a22c0cad78',
                               (16, 25, 32), 7055, 7080, compressed=True)

    def test_8x19x30_rank_2723(self):
        self.check_certificate((8, 19, 30), 2723,
                               '519e99587c73888bbc011a5a11c7342fcae631e79d591b077e52d3749772fc7a',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x28x15_rank_4576(self):
        self.check_certificate((19, 28, 15), 4576,
                               '20554ab7fe74e6a977ad7612274843926e79b18bbd2f3f168bf103b0cbc2ca86',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x28x14_rank_4484(self):
        self.check_certificate((20, 28, 14), 4484,
                               '10b966b8ceeb69bdf506007eb026df28df0aed4d6c118a5593e991a915ce8091',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x28x13_rank_4167(self):
        self.check_certificate((20, 28, 13), 4167,
                               'dbbcfd9d67a9c7a51927f6b0e7cdf72f2df419fb136e2a9cde04743d6749e986',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_19x28x13_rank_4068(self):
        self.check_certificate((19, 28, 13), 4068,
                               '15e461d7172163885bc5a51485d6de238e42ca783f02adc786bb9c85947c53e5',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_19x27x15_rank_4488(self):
        self.check_certificate((19, 27, 15), 4488,
                               '6547c40d267aed101dae2f3a2d91e5d3ded8198e586a5a4ea1f46af701b41feb',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_8x19x29_rank_2642(self):
        self.check_certificate((8, 19, 29), 2642,
                               'cf97d17f4b857e83df6e97541938e545f4a3ad03ce981d828a189df90099c633',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_20x27x13_rank_4092(self):
        self.check_certificate((20, 27, 13), 4092,
                               '23a9d6e38925bfaecdccf3f3dc9f400dfd68b2f66f3fb4ab8e5aa1b032e4cc3d',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x19x25_rank_5403(self):
        self.check_certificate((20, 19, 25), 5403,
                               'c11d3a775ed89031462c126f1707f63cd600c611d268878f165a838b9a8eb2a6',
                               (20, 20, 25), 5566, 5570, compressed=True)

    def test_19x27x13_rank_3969(self):
        self.check_certificate((19, 27, 13), 3969,
                               'ac2739d03b5231470050263c8677bfb25e283daebccdb5a6d9c7a180360d75d8',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x26x13_rank_3991(self):
        self.check_certificate((20, 26, 13), 3991,
                               'f115d6847bd5bd894ca59183e527a286e03f5ae4383f3dc38e24fca51ef56490',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x27x12_rank_3699(self):
        self.check_certificate((20, 27, 12), 3699,
                               '21e6b32af7808c961b33afa0357113cc019ef482e3caa8ca4d1710360ccece48',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_8x19x28_rank_2554(self):
        self.check_certificate((8, 19, 28), 2554,
                               'bb5dc75988081487d8818f0199bda6cd424022a0ce07eaad1278f93143704da5',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x26x13_rank_3874(self):
        self.check_certificate((19, 26, 13), 3874,
                               '36a042fbf9a75a2910694a46343a9ffa5b79af5aace59d9d9562365e065ca3f0',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x25x13_rank_3890(self):
        self.check_certificate((20, 25, 13), 3890,
                               '6a709719b5fe039baea4e1b97da45a2cd022c5d4a63345dec56da478dd6bcd59',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_20x27x11_rank_3545(self):
        self.check_certificate((20, 27, 11), 3545,
                               '86d8bac9048e7fd74c7a9dd9cf8dc029c555e32cba44622c7803ec3dcb96433c',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_7x19x28_rank_2384(self):
        self.check_certificate((7, 19, 28), 2384,
                               '91f691c6acbf09d16ecc819c77d1f7dce5fc8bd14cae307d17a14fbcde4d9e3a',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_8x19x27_rank_2464(self):
        self.check_certificate((8, 19, 27), 2464,
                               '0acee2a6eebe372fb9f395a6b7f91b88361dfc51efcce955b467ba8aaa2c9072',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x25x13_rank_3766(self):
        self.check_certificate((19, 25, 13), 3766,
                               '79e591467c80ba62f290c8613da4320706707a5847da568737e177de3a47b5de',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_8x19x26_rank_2366(self):
        self.check_certificate((8, 19, 26), 2366,
                               'bbade19dd1133fe2bca1ec529ce7787ab59b1f6d76360786c48aa0b81581e5d3',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_7x19x27_rank_2298(self):
        self.check_certificate((7, 19, 27), 2298,
                               '0cc954e1b7f0e5455cf29df9e20b45ab12505a3ca0dd1c3b976f5591882d18e7',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_19x26x12_rank_3493(self):
        self.check_certificate((19, 26, 12), 3493,
                               '748e38f85e567644c495f46706ba4aeb2fdc9d1d25f46fb997557e1eb8d7103a',
                               (15, 20, 28), 4700, 4740, compressed=True)

    def test_7x18x28_rank_2287(self):
        self.check_certificate((7, 18, 28), 2287,
                               '72d219a018cb0713080e7e384b1f7ca2215043537c93dccb81f5a154c21b1ebb',
                               (8, 20, 30), 2803, 2820, compressed=True)

    def test_next_rectangular_projection_chain(self):
        # These witnesses descend from the exact 8x20x30 portfolio tensor;
        # a full GF(2) expansion, not the projection recipe, is the authority.
        rows = (
            ((8, 19, 25), 2267, 'bbc407c145ef69bbe150bf85c6e6c445b182bc9907a5457af92043c200a264c1'),
            ((8, 20, 29), 2724, 'b1f26cb283b84ba01d699007abe162318569afa6e9c3fdcdb02fbf44577e0a16'),
            ((7, 20, 30), 2622, '2321df5be27cdd71032b79a94adbf7a6b7e08d9e6e99128dab599de57963b223'),
            ((7, 19, 30), 2538, '005b9d101f493eb6cd6386479099ad10c106940d682ab7c2e7d6302ff5a59d13'),
            ((7, 19, 26), 2209, 'f8528ab7ca06290912260b0a0b8001efb944fa9bd0525b8f9df3f9e157560ef4'),
            ((8, 19, 24), 2140, 'de9376f13a929162887d33fa4167b4ed8322c325c43d31816057ccf18792d758'),
            ((7, 19, 25), 2122, '408505b79f9a5dac4cfc2c05cf81491a92cf840246a6c5e81d1f5198445ce43a'),
            ((7, 19, 24), 2010, '22daa861e41e1065711bc1f131d5bc1d9985be81a0d53fe0f577378239091eda'),
            ((8, 19, 23), 2099, 'f3f4942a48d9e9a56e1f7ebdef06a13a7f4d9bf963ccd4c2e3d6bbf48985f45c'),
            ((7, 19, 23), 1980, 'd0cbe7d7c8257d13a22168325c18631180da81deddebefc2922dad926d5dcf41'),
            ((8, 18, 24), 2059, 'df40e51fc739f0414f5d5596be3c934cb51d18da3dad3ee4065166c5b394e91b'),
            ((8, 19, 22), 2034, '95e4cefd3c35ac44e7b11a115e5202e455aca43da75c9e5b0517cbb9b19b044c'),
            ((8, 17, 24), 1965, '77e095bb121886e989ad3ebab9815069d27bf41cfd39f165cb64d51ca3827951'),
            ((8, 17, 23), 1923, '0f01b41327bcb556369308e3fea771e9b707cb689c8dfa4cea8f43a82c79a47f'),
            ((7, 18, 24), 1942, 'e8c708c655e01a70f46f3058efe869d50583b5b29e3b9c20e90176278197ae4a'),
            ((8, 18, 23), 2016, '1d001c874df14a88f01e0ced8afdb2c1b20690bf2826810a6ed22d1b89c2cbae'),
            ((7, 18, 23), 1904, '8e8418b34ed6c26ad022e36850db8f9daefd376c3fd9056cb720ac0c3cccac55'),
            ((7, 17, 24), 1853, '75cbce4619a7db9e522f4878058cb972aca26ebf231d26366f4a8444a8e16ea4'),
            ((8, 17, 22), 1876, '95f4fd9516a94f5fa0e55bbf5a57969f2f8ac7ab945089061b575ca8efce6fff'),
            ((8, 16, 23), 1792, '54ef1bd730637c116c34b789b0bf0d370c2d4f94d1e99ab27a60c20c1e14f471'),
            ((7, 16, 24), 1730, 'daac3903c14908ee957e64db32457f69445e70c842aaf3027bc7f6bf64e1d917'),
        )
        for shape, rank, digest in rows:
            with self.subTest(shape=shape):
                self.check_certificate(shape, rank, digest, (8, 20, 30),
                                       2803, 2820, compressed=True)

    def test_eight_by_eighteen_projection_chain(self):
        # Independently expand each oriented MFW1 tensor from the 8x18x30 parent.
        rows = (
            ((7, 30, 18), 2374, '0645becb3abaf003bbe7fe60d3b139ff0079f7345e4367ce41accd8ac364dd76'),
            ((8, 29, 18), 2498, 'deb90236cda251a21c9576d17eebb647755f3dac5490529f2cd9899c288f9d89'),
            ((7, 29, 18), 2340, '614a99ac97e54556895bcf7aa22dae1462f9bab4a1e3c05e570a72be4fab7773'),
        )
        for shape, rank, digest in rows:
            with self.subTest(shape=shape):
                self.check_certificate(shape, rank, digest, (8, 18, 30),
                                       2526, 2538, compressed=True)

    def test_portfolio_wide_projection_records(self):
        rows = (
            ((11, 28, 25), 4518,
             'caea0fb4703ba25f9e5b45ef6dad82dbef2f22b2abfe94947de56026b6037c06',
             (12, 25, 28), 4708, 4740),
            ((16, 23, 15), 3164,
             '2ea6b00e3f5d9e7e6cb55ccff11f61ab8c5008f8fc16e9824bad41293feb688c',
             (15, 16, 24), 3225, 3240),
            ((11, 16, 30), 3105,
             'a01d95f4586ef8d0532c066ad4b36d74b1269184b866cbd592fa85da6d3e6ea9',
             (12, 16, 30), 3228, 3240),
            ((16, 23, 14), 3003,
             'aa3930d46ff5a8db62806e07c98d88b962ab7ad90775e840e18dc9ac1fad1cb4',
             (15, 16, 24), 3225, 3240),
            ((16, 22, 15), 3071,
             'ecb1db7e0192b7db2e3be600772fe5c688362094dbc89490d71b333ce8bb8034',
             (15, 16, 24), 3225, 3240),
            ((15, 23, 15), 3095,
             'd8ac3afc4e9d71d0ff5f92b563ae79b72a68d2dbe8505821503b9eb245ba7967',
             (15, 16, 24), 3225, 3240),
            ((11, 16, 29), 3034,
             '54e1d91cc371af992ba0f04495852cc429c01ab08f2b744de9addb860bed072f',
             (12, 16, 30), 3228, 3240),
            ((11, 15, 30), 3041,
             'ac78b3d3bf24c8cd4bbe3f7263b97f180b2bdd86f179e2f9dc26995269144f86',
             (12, 16, 30), 3228, 3240),
            ((11, 27, 25), 4426,
             'bd78c00de2ab4756d60a523ac4c5f9a2a4b95aa7d928e43363232854e10c15c4',
             (12, 25, 28), 4708, 4740),
            ((11, 28, 24), 4425,
             'a35380512b90f02fdafe6821e2ad8bd48462237914aac13adc90463b5fb1900d',
             (12, 25, 28), 4708, 4740),
            ((16, 23, 13), 2776,
             '67e703899b7af8c67d6da124a76b746e4476b0dd6ab665f4e86ccb26c19a18f0',
             (15, 16, 24), 3225, 3240),
            ((16, 23, 13), 2772,
             '272dd0c52242e10ce033187367b213527053743c15f06010069b9c5a8f607bbb',
             (15, 16, 24), 3225, 3240),
            ((16, 22, 14), 2922,
             'ed995b2aad9bf33c46cd1110176fbed033f731a6b9d666014ced81092e5976b4',
             (15, 16, 24), 3225, 3240),
            ((11, 16, 28), 2946,
             '8c9576c09ba2bde97e9adcdd3ef68dda81119da13fb9e9055a2a6c0b446c5c52',
             (12, 16, 30), 3228, 3240),
            ((11, 26, 25), 4327,
             'd6e1c9c2ac822f9d907c13b5c860a59cf997f738ae8f6d68b82e28f93bcd5362',
             (12, 25, 28), 4708, 4740),
            ((11, 27, 24), 4327,
             '9c0fa0f1a7efd33421753d2b8b0aa8d8401e64097554a9cd12f06d4b8b8fab82',
             (12, 25, 28), 4708, 4740),
            ((16, 23, 12), 2511,
             'f15061969a416e878364a4bae10e070fda166bcdadd30fb32dc051ade15c6fc6',
             (15, 16, 24), 3225, 3240),
            ((16, 22, 13), 2692,
             '9981b8536c0463e2c4132e5132dec1b14ecd4a156af4dc2a9f75a425911f9cd2',
             (15, 16, 24), 3225, 3240),
            ((15, 23, 13), 2718,
             '062e80865fe796172c27a31ff87989da7b6efb77f018d736be9e245ed0f78d14',
             (15, 16, 24), 3225, 3240),
            ((16, 23, 11), 2412,
             '34d0c54e36c0ed7433674d773f28c7811a247c67cf235df97b064e072d897e1a',
             (15, 16, 24), 3225, 3240),
            ((16, 21, 13), 2616,
             '348b4323c691f05065c65f13b52773c334f81958f0e3bb3f6919c85387a201f1',
             (15, 16, 24), 3225, 3240),
            ((16, 22, 12), 2444,
             'ecf3ac9a5ff7d4eddacc645354db088373fa30f6f97c5cbf419d1846014b6a62',
             (15, 16, 24), 3225, 3240),
            ((15, 23, 12), 2442,
             'bd5c8f7ba19eb728e0ab8d403ff8359873ad717020ec35a1a9f4976435c426ed',
             (15, 16, 24), 3225, 3240),
            ((11, 25, 25), 4205,
             '68bbf55cd6a76bae38802bdc56bd93bb3c0beaa9de93ddbc313e5d82b5f94698',
             (12, 25, 28), 4708, 4740),
            ((16, 22, 11), 2342,
             'c1b99f74ec4d2b678ba62cba1d6ae80fd711e55eccb963b001af5b8b8e63a1df',
             (15, 16, 24), 3225, 3240),
            ((14, 23, 12), 2323,
             '67d498c2543e671dfb8d947482f9cd00144047fd5df986770f0f40a75bf6096f',
             (15, 16, 24), 3225, 3240),
            ((15, 22, 12), 2375,
             '609101b2e7b4a2eab6614cb9293aee81e00eb5a9183db21386875a11771b93ef',
             (15, 16, 24), 3225, 3240),
            ((16, 21, 12), 2379,
             '96de2756ea2332b32d17b10bc078f6f150842dde6b56197d0e6f4c2e6d5a728a',
             (15, 16, 24), 3225, 3240),
            ((11, 16, 28), 2929,
             '7918386c8e36ff22acc3247b4770e934bd29502226b9268ada3996e1d4a23577',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 27), 2825,
             'a34362f6054a5d1b247b50c78592598f775afa8d2b4226de518debf8700a432e',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 26), 2701,
             '5d71a495555eedeb954f4c616877788f06f85b52f199ef418aac2a780b88095a',
             (12, 16, 30), 3228, 3240),
            ((19, 27, 11), 3448,
             'd2a648d53ae6800785b73e43f45f94c696d0d8c7f631d6326def1f12915b43cf',
             (15, 20, 28), 4700, 4740),
            ((11, 16, 25), 2582,
             'b26bda334fa22a69228d123adbcfc93ecbc88642b83a644231b2460e8e5ce1bb',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 24), 2437,
             '2f5f2d2f4270a4ebeeaaebdc1fdc0808b6dc86071f035a3510d25a6deb7782a4',
             (12, 16, 30), 3228, 3240),
            ((11, 15, 24), 2360,
             'e95846648003bac847ceb898be485b4b656c5099aedeb29c43c8ecb130f970de',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 23), 2386,
             '295506e7fd6bbb73efb3f6486f5feb073f8f65a93628675ccb8c69403ad41b81',
             (12, 16, 30), 3228, 3240),
            ((11, 14, 24), 2230,
             'c48c2fe496bc07d8e56594b6372a1fba8aea0e1e8c668448834b62cea4a87e18',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 22), 2302,
             '9d524723051aa2ca08d493155b86c35e1c64874f19642089a354189f2faef940',
             (12, 16, 30), 3228, 3240),
            ((11, 13, 24), 2111,
             '408840183e51a6d20e8ee516e8e2387594d29fa1302b3f2f2c044fe5debb3823',
             (12, 16, 30), 3228, 3240),
            ((11, 14, 23), 2183,
             '9ebb2298d2c5cb90b39593f4605a3258d2d456b435c8580cb7d0d90fe1088974',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 21), 2238,
             '6db608efeb7d4b4892f9e63b2bd3a8c17cda4918f7dcfcd05b039461559bf540',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 20), 2142,
             'bf3e5a111c8d37459fdf7e9aeb29efaf754962bfc499bd09364c8b646951b648',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 19), 2065,
             '2b844d0b5cf041927472c4c078c1b812b83a263a4a0b13f6ee5f41f189f8224b',
             (12, 16, 30), 3228, 3240),
            ((11, 16, 18), 1950,
             '9a1ee66ca213211de59f1e06b2d0a190e8607e7386680ea47f540e13044e959c',
             (12, 16, 30), 3228, 3240),
        )
        for shape, rank, digest, parent_shape, parent_rank, catalog_bound in rows:
            with self.subTest(shape=shape):
                self.check_certificate(shape, rank, digest, parent_shape,
                                       parent_rank, catalog_bound, compressed=True)


if __name__ == '__main__':
    unittest.main()
