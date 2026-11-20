#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
using namespace std;
int main(int argc,char** argv){
 if(argc<3)return 2;
 ifstream f(argv[1]);string word;int nv,nc;if(!(f>>word)||word!="p"||!(f>>word>>nv>>nc)||word!="cnf")return 2;
 vector<vector<int>> clauses,occ(2*nv+2);vector<int> units;
 auto put=[&](vector<int> c){int ci=clauses.size();for(int l:c)occ[2*abs(l)+(l<0)].push_back(ci);if(c.size()==1)units.push_back(c[0]);clauses.push_back(c);};
 auto read=[&](istream& in,vector<int>&c){int x;c.clear();while(in>>x){if(!x)return true;if(abs(x)>nv)exit(3);c.push_back(x);}if(!c.empty())exit(3);return false;};
 vector<int> c;while(read(f,c))put(c);if((int)clauses.size()!=nc)return 3;
 for(int a=2;a<argc;a++){ifstream in(argv[a]);if(!in)return 3;int checked=0;
  while(read(in,c)){vector<int> q=units;vector<signed char> val(nv+1);for(int l:c)q.push_back(-l);bool conflict=false;
   for(size_t j=0;j<q.size()&&!conflict;j++){int l=q[j],v=abs(l),sg=l>0?1:-1;if(val[v]){if(val[v]!=sg)conflict=true;continue;}val[v]=sg;
    for(int ci:occ[2*v+(l>0)]){int left=0,unit=0;for(int p:clauses[ci]){if(val[abs(p)]==(p>0?1:-1)){left=2;break;}if(!val[abs(p)]){unit=p;if(++left==2)break;}}
     if(left==0){conflict=true;break;}if(left==1)q.push_back(unit);}
   }if(!conflict){cerr<<"failed "<<argv[a]<<" row "<<checked+1<<"\n";return 1;}checked++;put(c);
  }cout<<argv[a]<<" "<<checked<<" checked RUP clauses\n";
 }
}
