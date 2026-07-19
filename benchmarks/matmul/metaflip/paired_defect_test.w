use paired_defect

-> pdc_test_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL paired_defect_test: " + label
    exit(1)
  1

shape = i64[3]
shape[0] = 2
shape[1] = 2
shape[2] = 2

# Two individually invalid 3->2 proposals with the same one-cell defect.
source_a = i64[9]
source_a[0]=1
source_a[1]=1
source_a[2]=2
source_a[3]=1
source_a[4]=1
source_a[5]=3
source_a[6]=1
source_a[7]=2
source_a[8]=1

target_a = i64[6]
target_a[0]=1
target_a[1]=2
target_a[2]=2
target_a[3]=1
target_a[4]=3
target_a[5]=1

source_b = i64[9]
source_b[0]=1
source_b[1]=1
source_b[2]=1
source_b[3]=1
source_b[4]=2
source_b[5]=3
source_b[6]=1
source_b[7]=3
source_b[8]=2

target_b = i64[6]
target_b[0]=2
target_b[1]=3
target_b[2]=3
target_b[3]=3
target_b[4]=3
target_b[5]=3

z = pdc_test_expect("A proposal is deliberately inexact",pdc_relation_exact(source_a,3,target_a,2,shape)==0) ## i64
z = pdc_test_expect("B proposal is deliberately inexact",pdc_relation_exact(source_b,3,target_b,2,shape)==0)

defect_a = i64[1]
defect_b = i64[1]
z = pdc_fill_defect(defect_a,source_a,target_a,0,1,shape)
z = pdc_fill_defect(defect_b,source_b,target_b,0,1,shape)
z = pdc_test_expect("A defect is nonzero",defect_a[0]!=0)
z = pdc_test_expect("explicit defects agree",defect_a[0]==defect_b[0])
z = pdc_test_expect("explicit defect is cell 3",defect_a[0]==8)

combined_source = i64[18]
i = 0 ## i64
while i < 9
  combined_source[i] = source_a[i]
  combined_source[i+9] = source_b[i]
  i += 1
combined_target = i64[12]
i = 0
while i < 6
  combined_target[i] = target_a[i]
  combined_target[i+6] = target_b[i]
  i += 1
z = pdc_test_expect("planted 6->4 relation is exact",pdc_relation_exact(combined_source,6,combined_target,4,shape)==1)

# Put the wanted pairs behind decoys so discovery depends on the join rather
# than fixed pool positions.
pool_a = i64[15]
pool_a[0]=3
pool_a[1]=1
pool_a[2]=2
pool_a[3]=1
pool_a[4]=2
pool_a[5]=2
pool_a[6]=2
pool_a[7]=1
pool_a[8]=3
pool_a[9]=1
pool_a[10]=3
pool_a[11]=1
pool_a[12]=3
pool_a[13]=2
pool_a[14]=1

pool_b = i64[15]
pool_b[0]=1
pool_b[1]=3
pool_b[2]=3
pool_b[3]=2
pool_b[4]=3
pool_b[5]=3
pool_b[6]=3
pool_b[7]=3
pool_b[8]=3
pool_b[9]=3
pool_b[10]=1
pool_b[11]=2
pool_b[12]=2
pool_b[13]=2
pool_b[14]=1

out = i64[12]
stats = i64[12]
found = pdc_join_3to2(source_a,source_b,pool_a,5,pool_b,5,shape,out,stats) ## i64
z = pdc_test_expect("hash join found a pair",found==1)
z = pdc_test_expect("join retained exact nonzero defect",stats[3]>0)
z = pdc_test_expect("join independently exact-gated 6->4",stats[4]==1)
z = pdc_test_expect("join reports net minus two",stats[5]==-2)
z = pdc_test_expect("returned relation exact",pdc_relation_exact(combined_source,6,out,4,shape)==1)

# Removing one planted target destroys the only guaranteed matching pair.
# The test does not require the decoy pool to have no unrelated relation; it
# verifies that every returned result, if any, still passes the exact gate.
bad_pool_b = i64[12]
i = 0
while i < 12
  bad_pool_b[i] = pool_b[i]
  i += 1
bad_pool_b[3]=2
bad_pool_b[4]=2
bad_pool_b[5]=3
bad_out = i64[12]
bad_stats = i64[12]
bad_found = pdc_join_3to2(source_a,source_b,pool_a,5,bad_pool_b,4,shape,bad_out,bad_stats) ## i64
if bad_found == 1
  z = pdc_test_expect("negative-pool hit remains exact",pdc_relation_exact(combined_source,6,bad_out,4,shape)==1)

<< "paired_defect_test: exact 6->4 recovered defect=0x08 proposals=" + stats[0].to_s() + "/" + stats[1].to_s() + " hash_hits=" + stats[2].to_s() + " exact_matches=" + stats[3].to_s() + " probes=" + stats[11].to_s()
