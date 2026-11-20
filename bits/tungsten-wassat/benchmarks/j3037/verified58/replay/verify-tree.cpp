// Replay a refutation over job-completion events. Project and price tables are
// independently reconstructed from job.mm by audit-prices.py before replay.
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
using namespace std;

constexpr int Jobs=30;
constexpr int Infinity=1000000000;
struct Mode {int length, r1, r2, a, b;};
struct Price {
  int upper[59]{}, paid[90][59]{}, start[31][3][59]{};
  vector<pair<int,int>> budget;
};
struct State {
  array<int,31> mode{}, begin{}, end{};
  int usedA=0, usedB=0;
};
struct Limit {int time, a, b;};
struct Windows {
  int begin[31]{}, end[31]{}, earliestFinish[31]{};
  bool possible=true;
};
struct Replay {
  int horizon=0;
  Mode modes[31][3]{};
  vector<int> parents[31],children[31];
  vector<Price> prices;
  array<int,31> allowed;
  unordered_map<string, vector<Limit>> known;
  ifstream proof;
  uint64_t checked=0;

  void load(const string& project,const string& costs,const string& slots) {
    ifstream input(project), c(costs), s(slots);
    for(int job=0;job<32;job++) {
      int n;input>>n;
      while(n--){int dst;input>>dst;--dst;
        if(job>0&&dst<=Jobs){parents[dst].push_back(job);children[job].push_back(dst);}}
      input>>n;
      for(int k=0;k<n;k++){Mode m;input>>m.length>>m.r1>>m.r2>>m.a>>m.b;
        if(job>=1&&job<=Jobs)modes[job][k]=m;}
    }
    int n;c>>horizon>>n;
    if(horizon!=58||!input||n<=0||n>252)throw runtime_error("bad project or price header");
    prices.resize(n);
    for(auto& p:prices) {
      string name,other;int sum,nd;c>>name>>sum>>nd;s>>other;
      if(name!=other||nd<=0)throw runtime_error("price mismatch");
      for(int i=0;i<nd;i++){int a,b;c>>a>>b;if(a<0||b<0)throw runtime_error("negative multiplier");p.budget.emplace_back(a,b);}
      for(int j=1;j<=Jobs;j++)for(int k=0;k<3;k++)
        for(int t=0;t<=horizon-modes[j][k].length;t++)c>>p.start[j][k][t];
      for(int t=0;t<horizon;t++){int u;s>>u;p.upper[t+1]=p.upper[t]+u;
        for(int z=0;z<90;z++){int w;s>>w;p.paid[z][t+1]=p.paid[z][t]+w;}}
      if(sum!=p.upper[horizon])throw runtime_error("inconsistent slot totals");
    }
    if(!c||!s)throw runtime_error("truncated price table");
  }
  Windows windows(const State& state,int now) const {
    Windows w;array<int,31> shortest{};
    for(int i=1;i<=Jobs;i++){
      int k=state.mode[i]>=0?state.mode[i]:allowed[i];
      shortest[i]=k>=0?modes[i][k].length:min({modes[i][0].length,modes[i][1].length,modes[i][2].length});
      w.begin[i]=now;
      for(int j:parents[i])w.begin[i]=max(w.begin[i],w.earliestFinish[j]);
      w.earliestFinish[i]=state.mode[i]>=0?state.end[i]:w.begin[i]+shortest[i];
    }
    for(int i=Jobs;i>=1;i--){
      w.end[i]=horizon;for(int j:children[i])w.end[i]=min(w.end[i],w.end[j]-shortest[j]);
      if(w.earliestFinish[i]>w.end[i])w.possible=false;
    }
    return w;
  }
  bool excludes(const State& s,int now,const Price& p) const {
    Windows w=windows(s,now);
    int64_t fixed=0;int cheapest[31][3]{};
    for(int i=1;i<=Jobs;i++){
      int k=s.mode[i];
      if(k>=0){
        int z=(i-1)*3+k;
        fixed+=p.start[i][k][s.begin[i]];
        fixed-=p.paid[z][min(now,s.end[i])]-p.paid[z][s.begin[i]];
      }else for(int choice=0;choice<3;choice++){
        int last=w.end[i]-modes[i][choice].length;
        cheapest[i][choice]=Infinity;
        if(w.begin[i]<=last&&(allowed[i]<0||allowed[i]==choice))
          cheapest[i][choice]=*min_element(p.start[i][choice]+w.begin[i],p.start[i][choice]+last+1);
      }
    }
    for(auto [a,b]:p.budget) {
      int64_t total=fixed-int64_t(a)*(161-s.usedA)-int64_t(b)*(128-s.usedB);
      for(int i=1;i<=Jobs;i++)if(s.mode[i]<0){
        int64_t low=numeric_limits<int64_t>::max();
        for(int k=0;k<3;k++)if(cheapest[i][k]!=Infinity){
          const auto& m=modes[i][k];low=min(low,int64_t(cheapest[i][k])+int64_t(a)*m.a+int64_t(b)*m.b);
        }
        if(low==numeric_limits<int64_t>::max())return true;
        total+=low;
      }
      if(total>p.upper[horizon]-p.upper[now])return true;
    }
    return false;
  }
  string signature(const State& s,int t) const {
    string key;key.reserve(Jobs);
    for(int i=1;i<=Jobs;i++){
      if(s.mode[i]<0)key.push_back(0);
      else if(s.end[i]<=t)key.push_back(1);
      else key.push_back(char(2+3*(s.end[i]-t)+s.mode[i]));
    }
    return key;
  }
  // Enumerate every subset and mode tuple that fits at this event.
  void subsets(const vector<int>& ready,size_t at,const State& s,int t,int room1,int room2) {
    if(at==ready.size()){
      int next=horizon+1;
      for(int i=1;i<=Jobs;i++)if(s.mode[i]>=0&&s.end[i]>t)next=min(next,s.end[i]);
      if(next<=horizon)verify(s,next);
      return;
    }
    int j=ready[at];subsets(ready,at+1,s,t,room1,room2);
    for(int k=0;k<3;k++){
      if(allowed[j]>=0&&allowed[j]!=k)continue;
      const auto& m=modes[j][k];
      if(m.r1>room1||m.r2>room2||s.usedA+m.a>161||s.usedB+m.b>128||t+m.length>horizon)continue;
      State n=s;n.mode[j]=k;n.begin[j]=t;n.end[j]=t+m.length;n.usedA+=m.a;n.usedB+=m.b;
      subsets(ready,at+1,n,t,room1-m.r1,room2-m.r2);
    }
  }
  void verify(const State& s,int t){
    ++checked;int op=proof.get();if(op<0)throw runtime_error("early end of proof");
    bool remaining=any_of(s.mode.begin()+1,s.mode.end(),[](int k){return k<0;});
    if(!remaining)throw runtime_error("a feasible schedule reached the alleged refutation");
    if(op>=3){
      if(size_t(op-3)>=prices.size()||!excludes(s,t,prices[op-3]))throw runtime_error("invalid capacity bound");
      return;
    }
    if(op==1){if(windows(s,t).possible)throw runtime_error("invalid timing bound");return;}
    string key=signature(s,t);
    if(op==2){
      auto it=known.find(key);
      if(it!=known.end())for(auto x:it->second)if(x.time<=t&&x.a<=s.usedA&&x.b<=s.usedB)return;
      throw runtime_error("no preceding refutation dominates this state");
    }
    int room1=17,room2=18;vector<int> ready;
    for(int i=1;i<=Jobs;i++){
      if(s.mode[i]>=0){if(s.end[i]>t){room1-=modes[i][s.mode[i]].r1;room2-=modes[i][s.mode[i]].r2;}}
      else if(all_of(parents[i].begin(),parents[i].end(),[&](int p){return s.mode[p]>=0&&s.end[p]<=t;}))ready.push_back(i);
    }
    subsets(ready,0,s,t,room1,room2);
    if(known.size()<600000||known.count(key)){
      auto& records=known[key];
      records.erase(remove_if(records.begin(),records.end(),[&](Limit old){
        return t<=old.time&&s.usedA<=old.a&&s.usedB<=old.b;}),records.end());
      records.push_back({t,s.usedA,s.usedB});
    }
  }
};
int main(int argc,char**argv)try{
 if(argc<5||(argc-5)%2)return 2;Replay r;r.load(argv[1],argv[2],argv[3]);r.allowed.fill(-1);
 for(int j=5;j<argc;j+=2){int i=stoi(argv[j])-1,k=stoi(argv[j+1]);if(i<1||i>Jobs||k<0||k>2||r.allowed[i]>=0)return 2;r.allowed[i]=k;}
 r.proof.open(argv[4],ios::binary);if(!r.proof)throw runtime_error("missing event proof");State s;s.mode.fill(-1);r.verify(s,0);
 if(r.proof.peek()!=EOF)throw runtime_error("unread proof suffix");
 cout<<"VERIFIED "<<r.checked<<" event-tree nodes\n";return 0;
}catch(const exception& e){cerr<<e.what()<<"\n";return 1;}
