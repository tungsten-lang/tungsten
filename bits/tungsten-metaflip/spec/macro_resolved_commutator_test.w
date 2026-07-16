use ../lib/metaflip/strategies/macro_resolved_commutator

-> ffrct_expect(label,condition) (String bool) i64
  if !condition
    << "FAIL resolved commutator: "+label
    exit(1)
  1

# A connected five-term fixture.  The test discovers a structural target,
# then pins deterministic replay and every semantic postcondition.
su=i64[5];sv=i64[5];sw=i64[5]
su[0]=1;sv[0]=2;sw[0]=2
su[1]=6;sv[1]=2;sw[1]=5
su[2]=1;sv[2]=7;sw[2]=2
su[3]=6;sv[3]=7;sw[3]=5
su[4]=7;sv[4]=5;sw[4]=6

found=0 ## i64
winner_u=i64[5];winner_v=i64[5];winner_w=i64[5]
winner_recipe=i64[20];winner_stats=i64[20]
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
          anchor=0 ## i64
          while anchor<5 && found==0
            if anchor != focus
              ou=i64[5];ov=i64[5];ow=i64[5]
              recipe=i64[20];stats=i64[20]
              rank=ffrc_search_target(su,sv,sw,5,focus,axis,target,anchor,400000,ou,ov,ow,recipe,stats) ## i64
              if rank==5
                found=rank
                z=ffmh_copy(ou,ov,ow,5,winner_u,winner_v,winner_w) ## i64
                i=0 ## i64
                while i<20
                  winner_recipe[i]=recipe[i]
                  winner_stats[i]=stats[i]
                  i+=1
            anchor+=1
        mode+=1
      other+=1
    axis+=1
  focus+=1

z=ffrct_expect("find target-resolved word",found==5 && winner_stats[14]==1) ## i64
z=ffrct_expect("five exact edges",winner_recipe[0]==1 && winner_recipe[1]==5 && winner_recipe[11]==5)
z=ffrct_expect("specific change retained",ffrc_target(winner_u,winner_v,winner_w,winner_recipe[7],winner_recipe[8],winner_recipe[9])==1)
z=ffrct_expect("collateral anchor restored",ffrc_term_equal(winner_u,winner_v,winner_w,winner_recipe[10],su,sv,sw,winner_recipe[10])==1)
z=ffrct_expect("changed exact endpoint",winner_recipe[12]>0 && ffmh_local_exact(su,sv,sw,5,winner_u,winner_v,winner_w,5)==1)

replay_u=i64[5];replay_v=i64[5];replay_w=i64[5];meta=i64[8]
replayed=ffrc_replay(su,sv,sw,5,winner_recipe,replay_u,replay_v,replay_w,meta) ## i64
z=ffrct_expect("deterministic replay",replayed==5 && meta[0]==1 && meta[1]==1 && meta[2]==1 && meta[3]==1)
z=ffrct_expect("same endpoint",fftc_terms_same_set(winner_u,winner_v,winner_w,5,replay_u,replay_v,replay_w,5)==1)

bad=i64[20]
i=0 ## i64
while i<20
  bad[i]=winner_recipe[i]
  i+=1
bad[9]=0
z=ffrct_expect("invalid target rejected",ffrc_replay(su,sv,sw,5,bad,replay_u,replay_v,replay_w,meta)==0)

<< "macro_resolved_commutator_test: distance="+winner_recipe[12].to_s()+" density_delta="+winner_recipe[13].to_s()+" pressure_delta="+winner_recipe[14].to_s()+" debt="+winner_recipe[16].to_s()+" cleanup_tried="+winner_stats[6].to_s()
