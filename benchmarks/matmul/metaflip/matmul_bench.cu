// matmul flip-graph energy-walk throughput benchmark (GPU vs CPU)
#include <cstdio>
#include <cstdint>
#include <chrono>
#include <cuda_runtime.h>
#define R0 93
#define MAXR 160
static const uint64_t H_SU[93] = {4225028ULL,524804ULL,68450ULL,10ULL,26240025ULL,832ULL,4194308ULL,16404ULL,1024ULL,864ULL,10485760ULL,524824ULL,262400ULL,64ULL,327680ULL,885610ULL,29388828ULL,524288ULL,27033600ULL,16777552ULL,65607ULL,161796ULL,656000ULL,67650ULL,131204ULL,68546ULL,26624ULL,27033600ULL,16793616ULL,65601ULL,17ULL,5248005ULL,16777216ULL,27033600ULL,16793936ULL,7ULL,75850ULL,159748ULL,656320ULL,4ULL,844825ULL,4198404ULL,30277632ULL,16384ULL,70722ULL,11371360ULL,16777240ULL,524289ULL,65602ULL,5406720ULL,541184ULL,168965ULL,11338560ULL,8ULL,525120ULL,65610ULL,26406940ULL,10250ULL,159876ULL,960ULL,2162688ULL,10ULL,169125ULL,524800ULL,800ULL,31488030ULL,10551360ULL,524312ULL,557920ULL,524292ULL,895850ULL,4222980ULL,2163552ULL,16777242ULL,524801ULL,131076ULL,994250ULL,24576ULL,557600ULL,2162752ULL,524314ULL,16394ULL,136324ULL,2163648ULL,16777220ULL,16401ULL,4199428ULL,136196ULL,11469760ULL,16392ULL,16777217ULL,262208ULL,4096ULL};
static const uint64_t H_SV[93] = {68450ULL,4225028ULL,524804ULL,832ULL,10ULL,26240025ULL,1024ULL,4194308ULL,16404ULL,524824ULL,864ULL,10485760ULL,327680ULL,262400ULL,64ULL,524288ULL,885610ULL,29388828ULL,65607ULL,27033600ULL,16777552ULL,67650ULL,161796ULL,656000ULL,26624ULL,131204ULL,68546ULL,65601ULL,27033600ULL,16793616ULL,16777216ULL,17ULL,5248005ULL,7ULL,27033600ULL,16793936ULL,656320ULL,75850ULL,159748ULL,4198404ULL,4ULL,844825ULL,70722ULL,30277632ULL,16384ULL,524289ULL,11371360ULL,16777240ULL,541184ULL,65602ULL,5406720ULL,8ULL,168965ULL,11338560ULL,26406940ULL,525120ULL,65610ULL,960ULL,10250ULL,159876ULL,169125ULL,2162688ULL,10ULL,31488030ULL,524800ULL,800ULL,557920ULL,10551360ULL,524312ULL,4222980ULL,524292ULL,895850ULL,524801ULL,2163552ULL,16777242ULL,24576ULL,131076ULL,994250ULL,524314ULL,557600ULL,2162752ULL,2163648ULL,16394ULL,136324ULL,4199428ULL,16777220ULL,16401ULL,16392ULL,136196ULL,11469760ULL,16777217ULL,262208ULL,4096ULL};
static const uint64_t H_SW[93] = {10486784ULL,2163170ULL,4347008ULL,22708245ULL,2162752ULL,32800ULL,5243904ULL,4ULL,17408ULL,524800ULL,11567104ULL,2162754ULL,64ULL,262400ULL,327680ULL,22729728ULL,8388608ULL,10846570ULL,17891392ULL,1377ULL,25952280ULL,10496000ULL,480ULL,4338816ULL,2165216ULL,4325504ULL,11264ULL,22020096ULL,321ULL,25952280ULL,21525ULL,16777216ULL,1048577ULL,22085696ULL,1057ULL,25952280ULL,4338688ULL,10561600ULL,164320ULL,14057485ULL,21504ULL,1024ULL,4194304ULL,4452ULL,25976832ULL,17858560ULL,8388609ULL,11338570ULL,24600ULL,14680064ULL,352ULL,11338560ULL,32768ULL,13325ULL,33120ULL,22721560ULL,10551360ULL,4340736ULL,2164800ULL,164000ULL,32800ULL,15375ULL,768ULL,2162690ULL,22730400ULL,10485760ULL,9469952ULL,10551370ULL,525120ULL,10977770ULL,4346880ULL,8389632ULL,17858592ULL,10485761ULL,2163522ULL,10988000ULL,4325376ULL,9216ULL,832ULL,9469984ULL,10485770ULL,15364ULL,2165568ULL,4227104ULL,5242881ULL,21508ULL,16778240ULL,11348800ULL,4227072ULL,13316ULL,16777217ULL,262208ULL,4096ULL};
__host__ __device__ inline int xins(uint64_t*us,uint64_t*vs,uint64_t*ws,int rank,uint64_t u,uint64_t v,uint64_t w){
  if(u==0||v==0||w==0)return rank;
  int f=-1;
  for(int k=0;k<rank;k++) if(us[k]==u&&vs[k]==v&&ws[k]==w){f=k;break;}
  if(f<0){us[rank]=u;vs[rank]=v;ws[rank]=w;return rank+1;}
  us[f]=us[rank-1];vs[f]=vs[rank-1];ws[f]=ws[rank-1];return rank-1;
}
__host__ __device__ inline int pres(const uint64_t*us,const uint64_t*vs,const uint64_t*ws,int rank,uint64_t u,uint64_t v,uint64_t w){
  int c=0;
  for(int k=0;k<rank;k++){int m=(us[k]==u)+(vs[k]==v)+(ws[k]==w);if(m==2)c++;}
  return c;
}
__host__ __device__ inline int walk(uint64_t*us,uint64_t*vs,uint64_t*ws,int rank,uint64_t rng,int K){
  int best=rank,th=6;
  for(int mv=0;mv<K;mv++){
    rng=rng*1103515245ULL+12345ULL; int ti=(int)((rng>>16)%(uint64_t)rank);
    uint64_t ui=us[ti],vi=vs[ti],wi=ws[ti];
    rng=rng*1103515245ULL+12345ULL; int axis=(int)((rng>>22)%3); int st=(int)((rng>>11)%(uint64_t)rank);
    int p=-1;
    for(int s=0;s<rank;s++){int jj=st+s;if(jj>=rank)jj-=rank;if(jj!=ti){bool sh=false;if(axis==0)sh=us[jj]==ui;else if(axis==1)sh=vs[jj]==vi;else sh=ws[jj]==wi;if(sh){p=jj;break;}}}
    if(p>=0){
      uint64_t uj=us[p],vj=vs[p],wj=ws[p];
      uint64_t au=ui,av=vi,aw=wi,bu=ui,bv=vi,bw=wj;
      if(axis==0){aw=wi^wj;bv=vi^vj;} else if(axis==1){aw=wi^wj;bu=ui^uj;} else {av=vi^vj;aw=wi;bu=ui^uj;bv=vj;bw=wi;}
      int po=pres(us,vs,ws,rank,ui,vi,wi)+pres(us,vs,ws,rank,uj,vj,wj); int rb=rank;
      rank=xins(us,vs,ws,rank,ui,vi,wi);rank=xins(us,vs,ws,rank,uj,vj,wj);rank=xins(us,vs,ws,rank,au,av,aw);rank=xins(us,vs,ws,rank,bu,bv,bw);
      int pn=pres(us,vs,ws,rank,au,av,aw)+pres(us,vs,ws,rank,bu,bv,bw);
      bool acc=(rank<rb)||(pn+th>=po);
      if(!acc){rank=xins(us,vs,ws,rank,ui,vi,wi);rank=xins(us,vs,ws,rank,uj,vj,wj);rank=xins(us,vs,ws,rank,au,av,aw);rank=xins(us,vs,ws,rank,bu,bv,bw);}
    }
    th=6-((mv/300000)%7); if(rank<best)best=rank;
  }
  return best;
}
__global__ void kbench(const uint64_t*su,const uint64_t*sv,const uint64_t*sw,int K,int*ob){
  int tid=blockIdx.x*blockDim.x+threadIdx.x;
  uint64_t us[MAXR],vs[MAXR],ws[MAXR];
  for(int i=0;i<R0;i++){us[i]=su[i];vs[i]=sv[i];ws[i]=sw[i];}
  ob[tid]=walk(us,vs,ws,R0,(uint64_t)tid*1009ULL+12345ULL,K);
}
int main(int argc,char**argv){
  int blocks=argc>1?atoi(argv[1]):1024, threads=argc>2?atoi(argv[2]):128, K=argc>3?atoi(argv[3]):200000;
  long long N=(long long)blocks*threads;
  uint64_t*dsu,*dsv,*dsw;int*dob;
  cudaMalloc(&dsu,R0*8);cudaMalloc(&dsv,R0*8);cudaMalloc(&dsw,R0*8);cudaMalloc(&dob,N*4);
  cudaMemcpy(dsu,H_SU,R0*8,cudaMemcpyHostToDevice);cudaMemcpy(dsv,H_SV,R0*8,cudaMemcpyHostToDevice);cudaMemcpy(dsw,H_SW,R0*8,cudaMemcpyHostToDevice);
  cudaEvent_t s,e;cudaEventCreate(&s);cudaEventCreate(&e);
  kbench<<<blocks,threads>>>(dsu,dsv,dsw,K,dob);cudaDeviceSynchronize();      // warmup
  cudaEventRecord(s); kbench<<<blocks,threads>>>(dsu,dsv,dsw,K,dob); cudaEventRecord(e); cudaEventSynchronize(e);
  cudaError_t err=cudaGetLastError(); if(err){printf("CUDA error: %s\n",cudaGetErrorString(err));return 1;}
  float ms;cudaEventElapsedTime(&ms,s,e);
  double gm=(double)N*K, gr=gm/(ms/1000.0);
  printf("GPU: %lld threads x %d moves = %.2e moves in %.1f ms = %.3f G moves/s\n",N,K,gm,ms,gr/1e9);
  uint64_t cu_[MAXR],cv_[MAXR],cw_[MAXR];for(int i=0;i<R0;i++){cu_[i]=H_SU[i];cv_[i]=H_SV[i];cw_[i]=H_SW[i];}
  int CK=2000000; auto t0=std::chrono::high_resolution_clock::now();
  volatile int cb=walk(cu_,cv_,cw_,R0,12345ULL,CK); (void)cb;
  auto t1=std::chrono::high_resolution_clock::now();
  double cs=std::chrono::duration<double>(t1-t0).count(), crate=CK/cs;
  printf("CPU(1 thread): %d moves in %.1f ms = %.3f M moves/s\n",CK,cs*1000,crate/1e6);
  printf("---\nGPU %.3f G/s  vs  1 CPU thread %.3f M/s  =  %.0fx\n",gr/1e9,crate/1e6,gr/crate);
  printf("vs our Mac fleet (~108M moves/s, 18 walkers): %.1fx\n",gr/108e6);
  return 0;
}
