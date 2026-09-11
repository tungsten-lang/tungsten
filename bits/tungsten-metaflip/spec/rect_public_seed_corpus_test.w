# Public-corpus rectangular doors imported in 2026-09 (see THIRD_PARTY.md).
# This regression proves that every registered door of the enlarged profiles
# remains an exact decomposition inside the R..R+2 band, that each profile
# exposes the intended strata, that no door aliases another term set, that
# every imported door is neither a coordinate relabeling (structural
# signature) nor a few-flip neighbour (symmetric difference below ceil(R/4))
# of any other door of its profile, and that every imported file is
# packaged, manifested, and checksummed.

use ../lib/metaflip/rect/doors

-> ffrpsc_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

root = __DIR__ + "/../lib/metaflip/" ## String
manifest = read_file(root + "manifests/seeds.tsv")
sums = read_file(root + "SHA256SUMS")
z = ffrpsc_expect("seed manifest is packaged", manifest != nil)
z = ffrpsc_expect("SHA256SUMS is packaged", sums != nil)

imported = ["matmul_2x5x6_rank47_d763_perminov_2026_serendipitous_5ec0a82ac7_gf2.txt","matmul_2x5x6_rank47_d892_perminov_2026_serendipitous_66ab3aeb9f_gf2.txt","matmul_3x3x5_rank36_d265_alphatensor_2022_z_gf2.txt","matmul_3x3x5_rank36_d317_alphatensor_2022_f2_gf2.txt","matmul_3x3x5_rank36_d392_perminov_2026_serendipitous_dcc0b5ad07_gf2.txt","matmul_3x3x5_rank38_d328_perminov_2026_serendipitous_8438674c82_gf2.txt","matmul_3x4x6_rank56_d489_perminov_2025_zt_gf2.txt","matmul_3x4x7_rank64_d603_perminov_2025_zt_gf2.txt","matmul_3x5x5_rank58_d482_perminov_2025_naive_c351_gf2.txt","matmul_3x5x5_rank58_d500_alphatensor_2022_z_gf2.txt","matmul_3x5x5_rank58_d544_alphatensor_2022_f2_gf2.txt","matmul_3x5x5_rank58_d613_perminov_2026_serendipitous_506f8f6eb3_gf2.txt","matmul_3x5x5_rank58_d634_perminov_2026_serendipitous_e3fdc8efb8_gf2.txt","matmul_3x5x5_rank60_d1011_perminov_2026_serendipitous_73950dde67_gf2.txt","matmul_3x5x6_rank68_d677_perminov_2026_serendipitous_e2edca7153_gf2.txt","matmul_3x5x6_rank70_d719_perminov_2025_addred_cr265_gf2.txt","matmul_3x5x7_rank79_d796_perminov_2026_serendipitous_6fdc4c9f06_gf2.txt","matmul_3x5x7_rank79_d797_perminov_2026_serendipitous_cdc7d44ac6_gf2.txt","matmul_3x5x7_rank79_d924_perminov_2026_serendipitous_943c9b5305_gf2.txt","matmul_3x5x7_rank79_d1630_perminov_2026_serendipitous_92252b0e1a_gf2.txt","matmul_3x5x7_rank79_d1690_perminov_2026_z_gf2.txt","matmul_3x5x7_rank80_d831_alphaevolve_2025_gf2.txt","matmul_3x5x7_rank81_d895_perminov_2026_zt_gf2.txt","matmul_4x4x6_rank73_d735_perminov_2025_zt_gf2.txt","matmul_4x4x6_rank73_d1406_perminov_2026_serendipitous_fb4e63f7bf_gf2.txt","matmul_4x5x7_rank104_d1222_perminov_2025_serendipitous_c41080c5e5_gf2.txt","matmul_4x5x7_rank104_d1247_perminov_2025_serendipitous_63dd14617f_gf2.txt","matmul_4x5x7_rank104_d1252_perminov_2025_serendipitous_43d850ea60_gf2.txt","matmul_4x5x7_rank104_d1377_perminov_2026_serendipitous_444e8a9ac8_gf2.txt","matmul_4x5x7_rank104_d1391_perminov_2026_serendipitous_0b3b2fc9c4_gf2.txt","matmul_4x5x7_rank104_d1394_perminov_2026_serendipitous_a71031bd4e_gf2.txt","matmul_4x5x8_rank118_d1789_perminov_2025_zt_gf2.txt","matmul_4x5x8_rank118_d1810_perminov_2026_serendipitous_b428f55b8f_gf2.txt","matmul_4x6x6_rank105_d1198_perminov_2026_serendipitous_6c1e220825_gf2.txt","matmul_4x6x7_rank123_d1930_perminov_2025_serendipitous_1c38c2b939_gf2.txt"]
imported_sha = ["b24e8c97ce7f3e542d404878e6d26160bc061599b50c9f503689314a456b1828","a95743b7958d417efd914b8c7967f0de2319d741ce25c76613c64e3a3f57946c","dbf5e9e98d0bbbb86f5ef3c2df390def99197786c9fbf6742ebc4cf4f80d5f6e","f7264d5014854ac2f02f0a7e595c5f8d6ed12a234fd6a92ad0869983a3f0cfa7","8d3c4c4e1cabcd6b13a1cbf73c00abd0e8756924a9f3d177898bd63d52236fe3","8d77e11626b09930411147a75615e2f20db3da5e3fc844f476e3b328c074f2e3","587cb6456c207c4d84d591965f74e3150f13f2d6dd397b437ef19f1b5365d53f","7226f317feab4389f2a92b7d5c24af1fd802c1d2f5c64302d07b66c8ddaab8f5","cf441567cf30efd8efd53001215da5baecb0aef3346928ec2abba85c809cfec0","77a1435ffc32f1ccf0992f81aa36fc7e7fcdc4e0599c292df7cb870e9f1781a1","a098d128cb68f109b8e18cf4189068c78e07556cd6b31656cb5dd22ceda02900","44c2a007495c84509628d54db9c6f500b2e0edfaa90e245797508f0c378175eb","dee7044d44e14aac685177b472fb8cfa21a7e424acfe88b8e473aa77cbc4ce0d","837b37cc58d9cdd824c492bca6a3867bf2140d6a59e7aa0747512590e8db4bfd","b1cacb086d57cde98ccc13852f3043f164d13f54ade2290800b7bd33b44d99e5","102f3a8f250e998e447e1e9ab4a3e73ddf0e1b3472e89088aca56d2acaf5ff38","20af50792f845bc65b9ce37263bb9c626d7c10de37e17b90a1f8fad76a80ffaa","29230bd412def3337888cf000804a6d254c3edf5d87ad4c0f378cfe913169e0b","8cc8fffc31aac48c10d7ddd87d20225446464d22fb272d82bfafff6d68bb1f39","90e921a491633530eb9ad405711788ca11f27980e9eba52ff04e3f43d46275c8","018825af836d2d9731c6fd3b5b844f5d360c9e2ec7f3b47b724a4caa6ddac7af","db5c69391c260ed72e78bd4aca009119b8c101c8ba17eb6610d9308b27c577b9","b8ae0ac179f896ee766b25543e558571dd81bd92ad82d9fad386ddb544732beb","85881a14f5aa22af9db2eef7f3f7f15331d35b5ce30bfc96327bc867c41ef42f","6c5cf62332a45af15b157188ba99651cd07558f3b417b61d8eafae5be778a863","0e68435f323799ee29f433f9ecad79759bde48d177900cf3eac01ee9b9663b6d","c2f503d301a89db9eaa5b2d84d8b6b64cc18f17fe0cac6c0b7205b04f98663ca","380b6a936a79ba6f3f28d9535bcd113d73231747c34477a4bd4b1211993ddda2","38b9460d638936975bd1a6096cfb882e55bd51285b7373dfd46764b3829afdec","b051b195a9fc1bdbf853b0b63be7a6b5880a6927b0d0daf9bdd62dfc362eb202","f406f7456635be81aeb7321a8162845c2cc7fe4e7421cd1f86baf6c9da762499","d30f6246aa66b95faafcda905ad379d2848f77dafb140f6cc7a3e5b3f99ae655","a40937ae113571c39228238527c9b738dd251afcec75c8ac2ecb80495cb6afc8","2430981a18f2d9ac6e260e73d6fbe0b49e8cbf9cc2c0618af6b14f3d5be531d4","4eb2b73c1b5c9f02d9001bc934ab5fa20b373aa495950e5f562ff9ac99e9def6"]
i = 0 ## i64
while i < imported.size()
  z = ffrpsc_expect(imported[i] + " is packaged", read_file(root + "seeds/gf2/" + imported[i]) != nil)
  z = ffrpsc_expect(imported[i] + " is manifested", manifest.include?("lib/metaflip/seeds/gf2/" + imported[i] + "\t" + imported_sha[i] + "\t"))
  z = ffrpsc_expect(imported[i] + " is checksummed", sums.include?(imported_sha[i] + "  lib/metaflip/seeds/gf2/" + imported[i]))
  i += 1

labels = ["2x5x6","3x3x5","3x4x6","3x4x7","3x5x5","3x5x6","3x5x7","4x4x6","4x5x7","4x5x8","4x6x6","4x6x7","4x6x8"]
ns = [2,3,3,3,3,3,3,4,4,4,4,4,4]
ms = [5,3,4,4,5,5,5,4,5,5,6,6,6]
ps = [6,5,6,7,5,6,7,6,7,8,6,7,8]
expected_doors = [4,5,3,3,7,3,8,4,8,4,2,3,2]
# Doors registered before the public import; later slots are the imports.
prior_doors = [2,1,2,2,1,1,1,2,2,2,1,2,2]
expected_r = [4,4,2,3,6,2,6,4,8,4,2,3,2]
expected_r1 = [0,0,0,0,0,0,1,0,0,0,0,0,0]
expected_r2 = [0,1,1,0,1,1,1,0,0,0,0,0,0]

total = 0 ## i64
shape = 0 ## i64
while shape < labels.size()
  n = ns[shape] ## i64
  m = ms[shape] ## i64
  p = ps[shape] ## i64
  leader_rank = ffrp_record_rank(n,m,p) ## i64
  minimum_distance = (leader_rank + 3) / 4 ## i64
  count = ffrp_frontier_seed_count(n,m,p) ## i64
  z = ffrpsc_expect(labels[shape]+" door count",count == expected_doors[shape])
  z = ffrpsc_expect(labels[shape]+" slot zero is the profile leader",ffrp_frontier_seed_rel(n,m,p,0) == ffrp_seed_rel(n,m,p))
  capacity = ffr_default_capacity(n,m,p) ## i64
  doors = []
  signatures = i64[count]
  strata = i64[3]
  slot = 0 ## i64
  while slot < count
    rel = ffrp_frontier_seed_rel(n,m,p,slot)
    z = ffrpsc_expect(labels[shape]+" slot "+slot.to_s()+" path",rel != "")
    z = ffrpsc_expect(labels[shape]+" slot "+slot.to_s()+" file",read_file(root+rel) != nil)
    state = i64[ffr_state_size(capacity)]
    rank = ffr_load_scheme_cap(state,root+rel,n,m,p,capacity,79001+shape*1009+slot*17,4,4,1000,250) ## i64
    z = ffrpsc_expect(labels[shape]+" slot "+slot.to_s()+" rank band",rank >= leader_rank && rank <= leader_rank+2)
    z = ffrpsc_expect(labels[shape]+" slot "+slot.to_s()+" exact best",ffr_verify_best_exact(state,n,m,p) == 1)
    z = ffrpsc_expect(labels[shape]+" slot "+slot.to_s()+" exact current",ffr_verify_current_exact(state,n,m,p) == 1)
    strata[rank-leader_rank] += 1
    signatures[slot] = ffrda_structural_signature(state)

    prior = 0 ## i64
    while prior < doors.size()
      z = ffrpsc_expect(labels[shape]+" unique slots "+prior.to_s()+"/"+slot.to_s(),ffrda_same_best(doors[prior],state) == 0)
      if slot >= prior_doors[shape]
        z = ffrpsc_expect(labels[shape]+" import "+slot.to_s()+" is not a relabeling of "+prior.to_s(),signatures[prior] != signatures[slot])
        distance = ffrda_best_distance(doors[prior],state) ## i64
        z = ffrpsc_expect(labels[shape]+" import "+slot.to_s()+" is far from "+prior.to_s(),distance >= minimum_distance)
      prior += 1
    doors.push(state)
    total += 1
    slot += 1

  z = ffrpsc_expect(labels[shape]+" rank-R count",strata[0] == expected_r[shape])
  z = ffrpsc_expect(labels[shape]+" rank-R+1 count",strata[1] == expected_r1[shape])
  z = ffrpsc_expect(labels[shape]+" rank-R+2 count",strata[2] == expected_r2[shape])
  shape += 1

z = ffrpsc_expect("total registered public-corpus doors",total == 56)
<< "PASS rectangular public-corpus doors exact=56 shapes=13 imported=35 strata=R/R+1/R+2 uniqueness=full relabeling=rejected distance=ceil(R/4)"
