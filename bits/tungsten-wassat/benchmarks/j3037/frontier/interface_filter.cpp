#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
using namespace std;
struct Mode {int d,r,s,u,v;uint64_t starts;};
using Domains=array<array<uint64_t,3>,32>;
Mode ms[32][3];vector<int> edges[32];int slot;
uint64_t below(int t){return t<=0?0:(uint64_t(1)<<t)-1;}
int low(uint64_t x){return __builtin_ctzll(x);}
int high(uint64_t x){return 63-__builtin_clzll(x);}
bool precedence(Domains& dom){
 for(int j=2;j<=31;j++){int end=100;
  for(int k=0;k<3;k++)if(dom[j][k])end=min(end,low(dom[j][k])+ms[j][k].d);
  if(end==100)return false;
  for(int s:edges[j])if(s<=31)for(auto& v:dom[s])v&=~below(end);
 }
 for(int j=31;j>=2;j--){int end=58;
  for(int s:edges[j])if(s<=31){int t=-1;for(auto v:dom[s])if(v)t=max(t,high(v));end=min(end,t);}
  bool any=false;for(int k=0;k<3;k++){dom[j][k]&=below(end-ms[j][k].d+1);any|=bool(dom[j][k]);}if(!any)return false;
 }return true;
}
// Time-table propagation recomputes a guaranteed renewable load across all remaining modes.
bool tighten(Domains& dom){
 for(;;){auto old=dom;if(!precedence(dom))return false;
  int total[58][2]={},own[32][58][2]={};
  for(int j=2;j<=31;j++)for(int t=0;t<58;t++){
   int r=100,s=100;for(int k=0;k<3;k++)if(dom[j][k]){
    auto m=ms[j][k];if(high(dom[j][k])>t||low(dom[j][k])+m.d<=t){r=s=0;break;}
    r=min(r,m.r);s=min(s,m.s);
   }
   total[t][0]+=own[j][t][0]=r;total[t][1]+=own[j][t][1]=s;
  }
  for(int j=2;j<=31;j++)for(int k=0;k<3;k++)if(dom[j][k]){auto m=ms[j][k];
   for(int t=0;t<58;t++)if(total[t][0]-own[j][t][0]+m.r>17||total[t][1]-own[j][t][1]+m.s>18)
    dom[j][k]&=~(below(t+1)&~below(t-m.d+1));
  }
  if(old==dom)return true;
 }
}
bool budgets(const Domains& d){
 array<int,162> a,b;a.fill(999);a[0]=0;
 for(int j=2;j<=31;j++){b.fill(999);for(int k=0;k<3;k++)if(d[j][k]){auto m=ms[j][k];
  for(int x=m.u;x<=161;x++)b[x]=min(b[x],a[x-m.u]+m.v);
 }a=b;}return *min_element(a.begin(),a.end())<=128;
}
int main(int argc,char** argv){
 if(argc!=4)return 2;slot=stoi(argv[3]);ifstream in(argv[1]),st(argv[2]);
 for(int j=2;j<=31;j++){int n;in>>n;while(n--){int s;in>>s;edges[j].push_back(s);}
  for(auto& m:ms[j]){in>>m.d>>m.r>>m.s>>m.u>>m.v>>n;while(n--){int t;in>>t;m.starts|=uint64_t(1)<<t;}}
 }
 string row;int total=0,surv=0,tt=0,prec=0;
 while(getline(st,row)){total++;istringstream is(row);uint64_t before;is>>before;
  int active[32];fill(active,active+32,-1);for(int z;is>>z;)active[z/3+2]=z%3;
  Domains dom{};for(int j=2;j<=31;j++)for(int k=0;k<3;k++){auto m=ms[j][k];
   uint64_t mask=(before>>j&1)?below(slot-m.d+1):~below(slot+1);
   if(active[j]>=0)mask=active[j]==k?(below(slot+1)&~below(slot-m.d+1)):0;
   dom[j][k]=m.starts&mask;
  }
  if(!precedence(dom))continue;prec++;if(!tighten(dom))continue;tt++;
  if(budgets(dom)){surv++;cout<<row<<'\n';}
 }
 cerr<<"total "<<total<<" precedence "<<prec<<" timetable "<<tt<<" budget "<<surv<<'\n';
}
