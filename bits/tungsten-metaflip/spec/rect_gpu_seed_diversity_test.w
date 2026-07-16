use ../lib/metaflip/rect/campaign

-> expect(actual, expected, label) (i64 i64 String)
  if actual != expected
    << "FAIL rectangular GPU seed diversity " + label + " got=" + actual.to_s() + " expected=" + expected.to_s()
    exit(1)

# Even epochs always grind the fleet best.
z = expect(ffrc_gpu_seed_lane(0,7,1,1),0-1,"one-lane even")
z = expect(ffrc_gpu_seed_lane(2,7,5,1),0-1,"multi-lane even")

# A one-lane portfolio child is itself scheduled across leader + side doors,
# so its exact seed supplies every odd GPU epoch. Standalone replay is stable.
z = expect(ffrc_gpu_seed_lane(1,7,1,1),0,"one-lane portfolio odd")
z = expect(ffrc_gpu_seed_lane(3,7,1,1),0,"one-lane portfolio later")
z = expect(ffrc_gpu_seed_lane(1,7,1,0),0-1,"one-lane standalone")

# Multi-island campaigns cover every available nonleader lane, including
# durable side doors beyond the built-in frontier count.
expected = [1,2,3,4]
i = 0 ## i64
while i < expected.size()
  z = expect(ffrc_gpu_seed_lane(1+i*2,7,5,1),expected[i],"multi-lane rotation " + i.to_s())
  i += 1
z = expect(ffrc_gpu_seed_lane(9,7,5,1),1,"multi-lane wrap")

# Door count, rather than walker count, caps the rotation.
z = expect(ffrc_gpu_seed_lane(1,2,8,1),1,"door cap first")
z = expect(ffrc_gpu_seed_lane(3,2,8,1),1,"door cap wrap")
z = expect(ffrc_gpu_seed_lane(1,1,8,1),0-1,"leader only")

<< "PASS rectangular GPU seed diversity"
