#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <charconv>
#include <algorithm>
using namespace std;
int main(int argc,char**argv){
 if(argc<4)return 1;vector<int> guard;for(int i=3;i<argc;i++)guard.push_back(atoi(argv[i]));ios::sync_with_stdio(false);cin.tie(nullptr);long long last=stoll(argv[2]);ifstream map(argv[1]);
 vector<long long> ids(2000000,0);long u;for(int i=1;i<=83276;i++)ids[i]=i;
 long id=83276;while(map>>u)ids[++id]=u;
 string l,result;vector<int> vs;bool empty=false;
 while(getline(cin,l)){const char *p=l.data(),*end=p+l.size();
  auto read=[&]()->int{while(p<end&&(*p==' '||*p=='\t'))++p;int n=0;auto x=from_chars(p,end,n);if(x.ec!=errc())throw runtime_error("invalid integer");p=x.ptr;return n;};
  if(l.empty()||l[0]=='c')continue;int seq=read();while(p<end&&*p==' ')p++;if(p<end&&*p=='d'){
   ++p;string del="deld";int v;
   while((v=read()))if(v>id&&size_t(v)<ids.size()&&ids[v]){
    del+=" ";del+=to_string(ids[v]);ids[v]=0;
   }
   if(del.size()>4)cout<<del<<";\n";
   continue;
  }
  vs.clear();int v;while((v=read()))vs.push_back(v);
  bool taut=false;
  for(int g:guard){if(find(vs.begin(),vs.end(),g)!=vs.end())taut=true;if(find(vs.begin(),vs.end(),-g)==vs.end())vs.push_back(-g);}
  if(taut){if(size_t(seq)>=ids.size())ids.resize(seq+10000,0);ids[seq]=0;continue;}
  result="rup";for(int lit:vs){result+=lit<0?" 1 ~x":" 1 x";result+=to_string(abs(lit));}result+=vs.empty()?" >= 1 :":" >= 1 : ~";
  while((v=read())){if(v<=0||size_t(v)>=ids.size())throw runtime_error("unsupported or missing LRAT hint");if(ids[v]){result+=" ";result+=to_string(ids[v]);}}
  if(size_t(seq)>=ids.size())ids.resize(seq+10000,0);ids[seq]=++last;result+=";\n";cout<<result;empty=(vs.size()==guard.size() && all_of(vs.begin(),vs.end(),[&](int x){return find(guard.begin(),guard.end(),-x)!=guard.end();}));
 }
 if(!empty)return 1;cerr<<last<<"\n";return 0;
}
