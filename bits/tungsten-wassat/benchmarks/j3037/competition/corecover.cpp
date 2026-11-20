#include <algorithm>
#include <array>
#include <bitset>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
using namespace std;using I=long long;
constexpr int capacity=1024;
using Mask=bitset<capacity>;
int r[30][3],s[30][3],opts[30],orderj[30];
I dp[31][162][129];Mask match[30][3],last[30];
I visit(int pos,int a,int b,Mask active){
 if(!dp[pos][a][b]||!active.any()||pos==30)return dp[pos][a][b];
 I result=0;int j=orderj[pos];
 for(int k=0;k<3;k++)if(opts[j]&(1<<k)){
  int x=a-r[j][k],y=b-s[j][k];if(x<0||y<0||!dp[pos+1][x][y])continue;
  auto next=active&match[pos][k];if((next&last[pos]).any())continue;
  result+=visit(pos+1,x,y,next);
 }
 return result;
}
int main(int argc,char**argv){
 if(argc!=4)return 1;ifstream meta(argv[1]),units(argv[2]),rows(argv[3]);
 for(int j=0;j<30;j++){opts[j]=7;orderj[j]=j;for(int k=0;k<3;k++)meta>>r[j][k]>>s[j][k];}
 for(int v;units>>v;)opts[(v-4167)/3]=1<<((v-4167)%3);
 vector<array<int,30>> bad;int freq[30]={};
 string row;while(getline(rows,row)){istringstream in(row);int v;array<int,30> pat{};pat.fill(-1);
  while(in>>v && v){if(v>=-4166||v< -4256)return 2;int j=(-v-4167)/3,k=(-v-4167)%3;pat[j]=k;freq[j]++;}
  bad.push_back(pat);}
 if(bad.size()>capacity)return 3;
 sort(orderj,orderj+30,[&](int i,int j){return pair(opts[i]!=7,freq[i])>pair(opts[j]!=7,freq[j]);});
 Mask active;for(size_t ix=0;ix<bad.size();ix++){int end=-1;for(int p=0;p<30;p++){
  int z=bad[ix][orderj[p]];if(z>=0)end=p;for(int k=0;k<3;k++)if(z<0||z==k)match[p][k].set(ix);
 }if(end<0){cout<<"empty cut"<<endl;return 0;}last[end].set(ix);active.set(ix);}
 for(int a=0;a<=161;a++)for(int b=0;b<=128;b++)dp[30][a][b]=1;
 for(int p=29;p>=0;p--)for(int a=0;a<=161;a++)for(int b=0;b<=128;b++){
  int j=orderj[p];for(int k=0;k<3;k++)if((opts[j]&(1<<k))&&a>=r[j][k]&&b>=s[j][k])dp[p][a][b]+=dp[p+1][a-r[j][k]][b-s[j][k]];
 }
 I open=visit(0,161,128,active);cout<<"budget-feasible "<<dp[0][161][128]<<" allowed after "<<bad.size()<<" cuts "<<open<<" excluded "<<dp[0][161][128]-open<<endl;
}
