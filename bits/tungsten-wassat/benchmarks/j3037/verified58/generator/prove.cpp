#include <array>
#include <cstdio>
#include <algorithm>
#include <chrono>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <unordered_map>
#include <cstdint>
using namespace std;
using clock_type=chrono::steady_clock;
struct JobMode{int len,r1,r2,g1,g2;};
struct Prices{int prefix[65]{},area[90][65]{},work[32][3][65]{};vector<pair<int,int>> multipliers;};
struct State{array<int,32> start{},mode{};int used[2]{};};
int H,nsec,restrict_mode[32];vector<int> pred[32],succ[32];JobMode modes[32][3];vector<Prices> prices;
long long nodes=0,cut=0;auto epoch=clock_type::now();
int finish(const State& a,int i){return a.start[i]+modes[i][a.mode[i]].len;}
bool branch(const State&,int);
bool pick(const State& a,int t,int cursor,int r1,int r2,const vector<int>& ready,int next){
 if(cursor==(int)ready.size())return next<=H && branch(a,next);
 int j=ready[cursor];if(pick(a,t,cursor+1,r1,r2,ready,next))return true;
 for(int k=0;k<3;k++){if(restrict_mode[j]>=0&&restrict_mode[j]!=k)continue;
  auto m=modes[j][k];if(t+m.len>H||r1+m.r1>17||r2+m.r2>18||a.used[0]+m.g1>161||a.used[1]+m.g2>128)continue;
  State b=a;b.start[j]=t;b.mode[j]=k;b.used[0]+=m.g1;b.used[1]+=m.g2;
  if(pick(b,t,cursor+1,r1+m.r1,r2+m.r2,ready,min(next,t+m.len)))return true;
 }return false;
}
struct Dominator{int t,a,b;};
unordered_map<string,vector<Dominator>> cache;
long long hits=0;FILE* trace=nullptr;
bool branch(const State& a,int t){
 if((++nodes&8191)==0&&clock_type::now()-epoch>chrono::seconds(nsec)){cout<<"limit nodes "<<nodes<<" dominance "<<hits<<" cuts "<<cut<<endl;exit(0);}
 int first[32]{},last[32]{},remaining=0,r1=0,r2=0,next=H+1;vector<int> ready;
 for(int i=1;i<=30;i++){
  if(a.mode[i]>=0){first[i]=finish(a,i);if(first[i]>t){next=min(next,first[i]);r1+=modes[i][a.mode[i]].r1;r2+=modes[i][a.mode[i]].r2;}continue;}
  remaining++;int lo=t,md=1000;bool ok=true;
  for(int j:pred[i])if(j){lo=max(lo,first[j]);if(a.mode[j]<0||finish(a,j)>t)ok=false;}
  for(int k=0;k<3;k++)if(restrict_mode[i]<0||restrict_mode[i]==k)md=min(md,modes[i][k].len);
  first[i]=lo+md;if(ok)ready.push_back(i);
 }
 if(!remaining){cout<<"schedule\n";for(int i=1;i<=30;i++)cout<<i+1<<" "<<a.start[i]<<" "<<a.mode[i]<<"\n";return true;}
 uint32_t waiting=0;string key(4,0);
 for(int i=1;i<=30;i++){
  if(a.mode[i]<0)waiting|=1u<<i;
  else if(first[i]>t){key.push_back(char(i));key.push_back(char((first[i]-t)*3+a.mode[i]));}}
 for(int i=0;i<4;i++)key[i]=char((waiting>>(8*i))&255);
 auto it=cache.find(key);
 if(it!=cache.end())for(auto old:it->second)if(old.t<=t&&old.a<=a.used[0]&&old.b<=a.used[1]){hits++;fputc(2,trace);return false;}
 for(int i=30;i>=1;i--){last[i]=H;for(int j:succ[i])if(j!=31){int md=1000;
  if(a.mode[j]>=0)md=modes[j][a.mode[j]].len;else for(int k=0;k<3;k++)if(restrict_mode[j]<0||restrict_mode[j]==k)md=min(md,modes[j][k].len);
  last[i]=min(last[i],last[j]-md);}
  if(first[i]>last[i]){fputc(1,trace);return false;}
 }
 for(auto &p:prices){int already=0,minimum[32][3]{};
  for(int i=1;i<=30;i++)if(a.mode[i]>=0){int k=a.mode[i],s=a.start[i],z=(i-1)*3+k;
   already+=p.work[i][k][s]-p.area[z][min(t,finish(a,i))]+p.area[z][s];}
  else{int lo=t;for(int j:pred[i])if(j)lo=max(lo,first[j]);
   for(int k=0;k<3;k++){int hi=last[i]-modes[i][k].len;
    minimum[i][k]=(lo<=hi&&(restrict_mode[i]<0||restrict_mode[i]==k))?*min_element(p.work[i][k]+lo,p.work[i][k]+hi+1):100000000;}}
  for(auto [u,v]:p.multipliers){long long total=already+u*(a.used[0]-161)+v*(a.used[1]-128);
   for(int i=1;i<=30;i++)if(a.mode[i]<0){int mn=100000000;for(int k=0;k<3;k++){auto m=modes[i][k];mn=min(mn,minimum[i][k]+u*m.g1+v*m.g2);}total+=mn;}
   if(total>p.prefix[H]-p.prefix[t]){cut++;fputc(3+(&p-prices.data()),trace);return false;}
  }
 }
 fputc(0,trace);if(pick(a,t,0,r1,r2,ready,next))return true;
 if(cache.size()<600000||cache.count(key)){
  auto& list=cache[key];list.erase(remove_if(list.begin(),list.end(),[&](auto old){return old.t>=t&&old.a>=a.used[0]&&old.b>=a.used[1];}),list.end());
  list.push_back({t,a.used[0],a.used[1]});
 }
 return false;
}
int main(int argc,char**argv){
 ifstream data(argv[1]);for(int i=0;i<32;i++){int n,j;data>>n;while(n--){data>>j;succ[i].push_back(j-1);pred[j-1].push_back(i);}data>>n;for(int k=0;k<n;k++){auto &m=modes[i][k];data>>m.len>>m.r1>>m.r2>>m.g1>>m.g2;}}
 ifstream weights(argv[2]),slots(argv[3]);int count;weights>>H>>count;prices.resize(count);
 for(auto&p:prices){string a,b;int cap,n;weights>>a>>cap>>n;slots>>b;if(a!=b)return 3;
  for(int i=0;i<n;i++){int u,v;weights>>u>>v;if(u<0||v<0)return 3;p.multipliers.emplace_back(u,v);}
  for(int i=1;i<=30;i++)for(int k=0;k<3;k++)for(int t=0;t+modes[i][k].len<=H;t++)weights>>p.work[i][k][t];
  for(int t=0;t<H;t++){int c;slots>>c;p.prefix[t+1]=p.prefix[t]+c;for(int z=0;z<90;z++){int w;slots>>w;p.area[z][t+1]=p.area[z][t]+w;}}
  if(cap!=p.prefix[H])return 3;
 }
 if(!slots||!weights)return 2;fill(restrict_mode,restrict_mode+32,-1);for(int j=5;j+1<argc;j+=2)restrict_mode[atoi(argv[j])-1]=atoi(argv[j+1]);
 trace=fopen(getenv("SCHEDULE_TRACE"),"wb");if(!trace||count>252)return 3;nsec=atoi(argv[4]);State a;a.mode.fill(-1);bool s=branch(a,0);if(fclose(trace)!=0)return 4;cout<<(s?"SAT":"exhausted")<<" nodes "<<nodes<<" dominance "<<hits<<" cuts "<<cut<<"\n";
}
