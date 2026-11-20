// Compile against CaDiCaL 3.0.1. The caller verifies the composed DRAT proof.
#include <cadical.hpp>
#include <cstdio>
#include <fstream>

int main(int argc, char **argv) {
  if (argc != 5) return 1;
  std::ifstream clauses(argv[1]), queries(argv[2]);
  FILE *proof = std::fopen(argv[3], "w");
  if (!clauses || !queries || !proof) return 1;
  std::ofstream implications(argv[4]);
  if (!implications) return 1;
  CaDiCaL::Solver solver;
  solver.configure("plain");
  solver.set("quiet", 1);
  solver.set("binary", 0);
  if (!solver.trace_proof(proof, "sweep.drat")) return 1;
  int lit;
  while (clauses >> lit) solver.add(lit);
  if (!clauses.eof()) return 1;

  int a, b, limit, proved = 0, attempted = 0;
  bool equivalent = false;
  while (queries >> a >> b >> limit) {
    equivalent = true;
    for (int sign : {1, -1}) {
      int u = a * sign, v = -b * sign;
      solver.assume(u);
      solver.assume(v);
      solver.limit("conflicts", limit);
      if (solver.solve() != 20) {
        equivalent = false;
        break;
      }
      // The failed assumptions license this implication on the base formula.
      // Flush first so its proof antecedents precede the published clause.
      solver.flush_proof_trace();
      if (std::fprintf(proof, "%d %d 0\n", -u, -v) < 0) return 1;
      implications << -u << " " << -v << " 0\n";
      solver.add(-u);
      solver.add(-v);
      solver.add(0);
    }
    ++attempted;
    if (equivalent) ++proved;
  }
  solver.close_proof_trace();
  if (std::fclose(proof) || !queries.eof()) return 1;
  std::fprintf(stderr, "c gate miter proved %d of %d candidate pairs\n", proved, attempted);
  implications.close();
  return implications ? 0 : 1;
}
