use ../lib/metaflip/strategies/macro_resolved_commutator

-> ffrc7t_expect(label,condition) (String bool) i64
  if !condition
    << "FAIL resolved commutator7: "+label
    exit(1)
  1

su=i64[6];sv=i64[6];sw=i64[6]
su[0]=1;sv[0]=2;sw[0]=2
su[1]=6;sv[1]=2;sw[1]=5
su[2]=1;sv[2]=7;sw[2]=2
su[3]=6;sv[3]=7;sw[3]=5
su[4]=7;sv[4]=5;sw[4]=6
su[5]=7;sv[5]=7;sw[5]=6

found=0 ## i64
wu=i64[6];wv=i64[6];ww=i64[6];wr=i64[24];wstats=i64[24]
focus=0 ## i64
while focus<6 && found==0
  axis=0 ## i64
  while axis<3 && found==0
    other=0 ## i64
    while other<6 && found==0
      mode=0 ## i64
      while mode<2 && found==0
        target=ffmh_axis_get(su,sv,sw,other,axis) ## i64
        if mode==1
          target=target^ffmh_axis_get(su,sv,sw,focus,axis)
        if target > 0 && target != ffmh_axis_get(su,sv,sw,focus,axis)
          anchor=0 ## i64
          while anchor<6 && found==0
            if anchor != focus
              ou=i64[6];ov=i64[6];ow=i64[6];recipe=i64[24];stats=i64[24]
              rank=ffrc7_search_target(su,sv,sw,6,focus,axis,target,anchor,1000000,ou,ov,ow,recipe,stats) ## i64
              if rank==6
                found=rank
                z=ffmh_copy(ou,ov,ow,6,wu,wv,ww) ## i64
                i=0 ## i64
                while i<24
                  wr[i]=recipe[i];wstats[i]=stats[i];i+=1
            anchor+=1
        mode+=1
      other+=1
    axis+=1
  focus+=1

z=ffrc7t_expect("find seven-edge word",found==6 && wstats[17]==1) ## i64
z=ffrc7t_expect("specific target",ffrc_target(wu,wv,ww,wr[9],wr[10],wr[11])==1)
z=ffrc7t_expect("restored anchor",ffrc_term_equal(wu,wv,ww,wr[12],su,sv,sw,wr[12])==1)
z=ffrc7t_expect("changed exact",wr[14]>0 && ffmh_local_exact(su,sv,sw,6,wu,wv,ww,6)==1)
ru=i64[6];rv=i64[6];rw=i64[6];meta=i64[8]
replayed=ffrc7_replay(su,sv,sw,6,wr,ru,rv,rw,meta) ## i64
z=ffrc7t_expect("replay",replayed==6 && meta[0]==1 && meta[2]==1 && meta[3]==1)
z=ffrc7t_expect("same endpoint",fftc_terms_same_set(wu,wv,ww,6,ru,rv,rw,6)==1)

<< "macro_resolved_commutator7_test: distance="+wr[14].to_s()+" density_delta="+wr[15].to_s()+" debt="+wr[18].to_s()+" cleanup_tried="+wstats[8].to_s()
