use ../lib/metaflip/wide/seeds

expected = i64[9]
expected[0]=329
expected[1]=486
expected[2]=651
expected[3]=873
expected[4]=1068
expected[5]=1402
expected[6]=1725
expected[7]=2006
expected[8]=2209
n=8 ## i64
while n<=16
  if ffws_reference_rank(n)!=expected[n-8]
    exit(1)
  n+=1
if ffws_reference_rank(7)!=0 || ffws_reference_rank(17)!=0
  exit(1)
<< "PASS wide reference ranks (15x15=2006)"
