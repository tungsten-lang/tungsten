#include <cadical.hpp>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
using Cube = std::vector<int>;
using Partition = std::vector<Cube>;

struct Search : CaDiCaL::Terminator {
  CaDiCaL::Solver solver;
  std::vector<Partition> partitions;
  std::chrono::steady_clock::time_point until;
  FILE *proof;
  int nodes = 0, closed = 0, unknown = 0;
  bool terminate() override { return std::chrono::steady_clock::now() >= until; }
  int probe(const Cube &cube, int limit) {
    for(int v : cube) solver.assume(v);
    solver.limit("conflicts",limit);
    int status=solver.solve();
    if(status!=20) return status;
    Cube cut;
    for(int v : cube) if(solver.failed(v)) cut.push_back(-v);
    solver.flush_proof_trace();
    for(int v : cut) fprintf(proof,"%d ",v);
    fprintf(proof,"0\n"); fflush(proof);
    for(int v : cut) solver.add(v);
    solver.add(0); closed++;
    return 20;
  }
  int visit(const Cube &cube, size_t depth) {
    if(terminate()) return 0;
    nodes++;
    if(nodes%500==0) std::cout<<"nodes "<<nodes<<" closed "<<closed<<" uncertain leaves "<<unknown<<std::endl;
    int result=probe(cube,depth==partitions.size()?35000:1000);
    if(result) return result;
    if(depth==partitions.size()){unknown++;return 0;}
    for(const auto &part : partitions[depth]){
      Cube next=cube;next.insert(next.end(),part.begin(),part.end());
      if(visit(next,depth+1)==10) return 10;
      if(terminate()) return 0;
    }
    int summary=probe(cube,12000);
    if(depth<=2){
      std::cout<<"subtree";
      for(int v:cube)std::cout<<" "<<v;
      std::cout<<" result "<<summary<<" total nodes "<<nodes<<std::endl;
    }
    return summary;
  }
};
int main(int argc,char **argv){
  if(argc!=5)return 1;
  Search s;
  s.until=std::chrono::steady_clock::now()+std::chrono::seconds(std::stoi(argv[4]));
  s.solver.configure("plain"); s.solver.set("quiet",1); s.solver.set("binary",0);
  s.proof=fopen(argv[2],"w");
  if(!s.proof||!s.solver.trace_proof(s.proof,argv[2]))return 2;
  int n=0;if(s.solver.read_dimacs(argv[1],n))return 3;
  std::ifstream data(argv[3]);std::string line;
  while(std::getline(data,line)){
    Partition group;Cube cube;std::istringstream row(line);
    for(int v;row>>v;){
      if(v){cube.push_back(v);s.solver.freeze(abs(v));}
      else{group.push_back(cube);cube.clear();}
    }
    if(group.empty()||!cube.empty())return 4;
    s.partitions.push_back(group);
  }
  s.solver.connect_terminator(&s);
  int result=s.visit({},0);
  std::cout<<"result "<<result<<" nodes "<<s.nodes<<" proven "<<s.closed<<" unknown leaves "<<s.unknown<<std::endl;
  s.solver.close_proof_trace();fclose(s.proof);return result==20?0:5;
}
