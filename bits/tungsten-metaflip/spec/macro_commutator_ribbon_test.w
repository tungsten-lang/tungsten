use ../lib/metaflip/strategies/macro_commutator

-> ffccrt_expect(label,condition) (String bool) i64
  if !condition
    << "FAIL macro commutator ribbon: "+label
    exit(1)
  1

su=i64[5];sv=i64[5];sw=i64[5]
su[0]=1;sv[0]=2;sw[0]=2
su[1]=6;sv[1]=2;sw[1]=5
su[2]=1;sv[2]=7;sw[2]=2
su[3]=6;sv[3]=7;sw[3]=5
su[4]=7;sv[4]=5;sw[4]=6

found=0 ## i64
wu=i64[5];wv=i64[5];ww=i64[5];wr=i64[18];wstats=i64[14]
focus=0 ## i64
while focus<5 && found==0
  axis=0 ## i64
  while axis<3 && found==0
    other=0 ## i64
    while other<5 && found==0
      mode=0 ## i64
      while mode<2 && found==0
        target=ffmh_axis_get(su,sv,sw,other,axis) ## i64
        if mode==1
          target=target^ffmh_axis_get(su,sv,sw,focus,axis)
        if target > 0 && target != ffmh_axis_get(su,sv,sw,focus,axis)
          ou=i64[5];ov=i64[5];ow=i64[5];recipe=i64[18];stats=i64[14]
          rank=ffcc3_search_target(su,sv,sw,5,focus,axis,target,2000000,ou,ov,ow,recipe,stats) ## i64
          if rank==5
            found=rank
            z=ffmh_copy(ou,ov,ow,5,wu,wv,ww) ## i64
            i=0 ## i64
            while i<18
              wr[i]=recipe[i]
              i+=1
            i=0
            while i<14
              wstats[i]=stats[i]
              i+=1
        mode+=1
      other+=1
    axis+=1
  focus+=1

z=ffccrt_expect("find setup ribbon",found==5 && wstats[11]==1) ## i64
z=ffccrt_expect("conjugate or commutator length",wr[0]==7 || wr[0]==8)
z=ffccrt_expect("target retained",ffcc_target_hit(wu,wv,ww,wr[5],wr[6],wr[7])==1)
z=ffccrt_expect("changed exact endpoint",wr[9]>0 && ffmh_local_exact(su,sv,sw,5,wu,wv,ww,5)==1)
ru=i64[5];rv=i64[5];rw=i64[5];meta=i64[6]
replayed=ffcc3_replay(su,sv,sw,5,wr,ru,rv,rw,meta) ## i64
z=ffccrt_expect("deterministic replay",replayed==5 && meta[0]==1 && meta[1]==1 && meta[2]==1)
z=ffccrt_expect("same endpoint",fftc_terms_same_set(wu,wv,ww,5,ru,rv,rw,5)==1)

<< "macro_commutator_ribbon_test: length="+wr[0].to_s()+" distance="+wr[9].to_s()+" density_delta="+wr[10].to_s()+" inverse_closes="+wstats[5].to_s()
