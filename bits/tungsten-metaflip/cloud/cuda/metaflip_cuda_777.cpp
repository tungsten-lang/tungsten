// Thin, fail-closed CUDA relay for Metaflip's cooperative 7x7 GF(2) walker.
//
// The build script emits simdgroup_777_kernel.cu from the canonical Tungsten
// source and places it on the include path.  This file supplies only the
// NVIDIA host protocol, warp-reduction shims, exhaustive tensor gate, and
// atomic result/status persistence.

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <climits>
#include <csignal>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <random>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <vector>

#include <fcntl.h>
#include <unistd.h>

#ifndef METAFLIP_HOST_ONLY_TEST
#include <cuda_runtime.h>

static_assert(sizeof(long) == sizeof(int64_t),
              "Tungsten's emitted CUDA i64 ABI requires an LP64 host");

// Tungsten's portable CUDA emitter currently leaves the three SIMD reduction
// spellings intact.  A Metaflip cooperative group is exactly one CUDA warp,
// so these are direct, deterministic translations of the Metal SIMDgroup
// operations.  Every call site is reached uniformly by all 32 lanes.
__device__ __forceinline__ int simd_broadcast_first(int value) {
  const unsigned mask = __activemask();
  return __shfl_sync(mask, value, 0);
}

__device__ __forceinline__ int simd_min(int value) {
  const unsigned mask = __activemask();
  for (int offset = 16; offset > 0; offset >>= 1) {
    const int other = __shfl_down_sync(mask, value, offset);
    value = value < other ? value : other;
  }
  return __shfl_sync(mask, value, 0);
}

__device__ __forceinline__ int simd_sum(int value) {
  const unsigned mask = __activemask();
  for (int offset = 16; offset > 0; offset >>= 1) {
    value += __shfl_down_sync(mask, value, offset);
  }
  return __shfl_sync(mask, value, 0);
}

#include "simdgroup_777_scan_kernel.cu"
#include "simdgroup_777_hash_kernel.cu"
#endif

namespace {

constexpr int kN = 7;
constexpr int kFactorBits = kN * kN;
constexpr int kCap = 360;
constexpr int kMaxHarvestTopK = 8;
constexpr int kDefaultHarvestTopK = kMaxHarvestTopK;
constexpr size_t kGroupStateWords = 8;
constexpr size_t kGroupStateCompletedOffset = 7;
static_assert(kGroupStateCompletedOffset + 1 == kGroupStateWords,
              "group completion sentinel must end its state record");
constexpr uint64_t kFactorMask = (uint64_t{1} << kFactorBits) - 1;
constexpr int kScanSharedBytes = 3 * kCap * static_cast<int>(sizeof(int64_t)) +
                                 6 * static_cast<int>(sizeof(int64_t));
constexpr int kHashSharedBytes = kScanSharedBytes + 1536 * static_cast<int>(sizeof(int32_t)) +
                                 1080 * static_cast<int>(sizeof(int32_t));
static_assert(kScanSharedBytes == 8688, "unexpected scan shared-memory geometry");
static_assert(kHashSharedBytes == 19152, "unexpected hash shared-memory geometry");

struct Term {
  uint64_t u = 0;
  uint64_t v = 0;
  uint64_t w = 0;

  bool operator<(const Term& other) const {
    return std::tie(u, v, w) < std::tie(other.u, other.v, other.w);
  }

  bool operator==(const Term& other) const {
    return u == other.u && v == other.v && w == other.w;
  }
};

struct Scheme {
  std::vector<Term> terms;
  std::string source;
};

struct VerifyResult {
  bool exact = false;
  std::string reason;
};

std::string trim(const std::string& text) {
  const auto first = text.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) return "";
  const auto last = text.find_last_not_of(" \t\r\n");
  return text.substr(first, last - first + 1);
}

std::vector<std::string> fields(const std::string& line) {
  std::istringstream in(line);
  std::vector<std::string> out;
  std::string field;
  while (in >> field) out.push_back(field);
  return out;
}

uint64_t parse_u64(const std::string& text, const std::string& context) {
  if (text.empty() || text[0] == '-') {
    throw std::runtime_error(context + ": expected a nonnegative integer");
  }
  size_t used = 0;
  unsigned long long value = 0;
  try {
    value = std::stoull(text, &used, 10);
  } catch (const std::exception&) {
    throw std::runtime_error(context + ": invalid integer `" + text + "`");
  }
  if (used != text.size()) {
    throw std::runtime_error(context + ": trailing characters in `" + text + "`");
  }
  return static_cast<uint64_t>(value);
}

long long parse_i64(const std::string& text, const std::string& context) {
  size_t used = 0;
  long long value = 0;
  try {
    value = std::stoll(text, &used, 10);
  } catch (const std::exception&) {
    throw std::runtime_error(context + ": invalid integer `" + text + "`");
  }
  if (used != text.size()) {
    throw std::runtime_error(context + ": trailing characters in `" + text + "`");
  }
  return value;
}

int parse_int(const std::string& text, const std::string& context) {
  const long long value = parse_i64(text, context);
  if (value < INT_MIN || value > INT_MAX) {
    throw std::runtime_error(context + ": integer is outside the i32 range");
  }
  return static_cast<int>(value);
}

Scheme load_scheme(const std::string& path) {
  std::ifstream input(path);
  if (!input) throw std::runtime_error("cannot open seed `" + path + "`");

  std::vector<std::vector<std::string>> rows;
  std::string line;
  while (std::getline(input, line)) {
    const std::string clean = trim(line);
    if (clean.empty() || clean[0] == '#') continue;
    auto row = fields(clean);
    if (row.empty()) continue;
    rows.push_back(std::move(row));
  }
  if (rows.empty()) throw std::runtime_error("empty seed `" + path + "`");

  Scheme scheme;
  scheme.source = path;
  size_t first_term = 0;
  size_t expected = 0;
  bool tagged = rows[0][0] == "R";
  if (!tagged) {
    expected = static_cast<size_t>(parse_u64(rows[0][0], path + ": rank header"));
    first_term = 1;
  }

  for (size_t i = first_term; i < rows.size(); ++i) {
    const auto& row = rows[i];
    const size_t base = row[0] == "R" ? 1 : 0;
    if (row.size() < base + 3) {
      throw std::runtime_error(path + ": malformed term row " + std::to_string(i + 1));
    }
    Term term;
    term.u = parse_u64(row[base], path + ": U factor");
    term.v = parse_u64(row[base + 1], path + ": V factor");
    term.w = parse_u64(row[base + 2], path + ": W factor");
    scheme.terms.push_back(term);
  }

  if (!tagged && scheme.terms.size() != expected) {
    throw std::runtime_error(path + ": header rank " + std::to_string(expected) +
                             " does not match " + std::to_string(scheme.terms.size()) +
                             " term rows");
  }
  if (scheme.terms.empty() || scheme.terms.size() > static_cast<size_t>(kCap)) {
    throw std::runtime_error(path + ": rank is outside CUDA relay capacity 1.." +
                             std::to_string(kCap));
  }
  return scheme;
}

int density(const Scheme& scheme) {
  int total = 0;
  for (const auto& term : scheme.terms) {
    total += __builtin_popcountll(term.u);
    total += __builtin_popcountll(term.v);
    total += __builtin_popcountll(term.w);
  }
  return total;
}

std::string canonical_key(const Scheme& scheme) {
  std::vector<Term> sorted = scheme.terms;
  std::sort(sorted.begin(), sorted.end());
  std::ostringstream out;
  out << std::hex;
  for (const auto& term : sorted) {
    out << term.u << ':' << term.v << ':' << term.w << ';';
  }
  return out.str();
}

[[maybe_unused]] uint64_t key_digest(const std::string& key) {
  uint64_t hash = 1469598103934665603ULL;
  for (const unsigned char byte : key) {
    hash ^= byte;
    hash *= 1099511628211ULL;
  }
  return hash;
}

VerifyResult verify_exact(const Scheme& scheme) {
  if (scheme.terms.empty() || scheme.terms.size() > static_cast<size_t>(kCap)) {
    return {false, "rank outside relay capacity"};
  }

  std::vector<Term> sorted = scheme.terms;
  for (size_t i = 0; i < scheme.terms.size(); ++i) {
    const auto& term = scheme.terms[i];
    if (term.u == 0 || term.v == 0 || term.w == 0) {
      return {false, "zero factor at term " + std::to_string(i)};
    }
    if ((term.u & kFactorMask) != term.u || (term.v & kFactorMask) != term.v ||
        (term.w & kFactorMask) != term.w) {
      return {false, "out-of-range factor at term " + std::to_string(i)};
    }
  }
  std::sort(sorted.begin(), sorted.end());
  for (size_t i = 1; i < sorted.size(); ++i) {
    if (sorted[i] == sorted[i - 1]) return {false, "duplicate GF(2) term pair"};
  }

  constexpr int plane = kFactorBits;
  constexpr size_t cells = static_cast<size_t>(plane) * plane * plane;
  std::vector<uint8_t> parity(cells, 0);
  for (const auto& term : scheme.terms) {
    uint64_t ubits = term.u;
    while (ubits != 0) {
      const int a = __builtin_ctzll(ubits);
      ubits &= ubits - 1;
      uint64_t vbits = term.v;
      while (vbits != 0) {
        const int b = __builtin_ctzll(vbits);
        vbits &= vbits - 1;
        uint64_t wbits = term.w;
        while (wbits != 0) {
          const int c = __builtin_ctzll(wbits);
          wbits &= wbits - 1;
          const size_t cell = (static_cast<size_t>(a) * plane + b) * plane + c;
          parity[cell] ^= 1;
        }
      }
    }
  }

  for (int i = 0; i < kN; ++i) {
    for (int j = 0; j < kN; ++j) {
      for (int k = 0; k < kN; ++k) {
        const int a = i * kN + j;
        const int b = j * kN + k;
        const int c = i * kN + k;
        const size_t cell = (static_cast<size_t>(a) * plane + b) * plane + c;
        parity[cell] ^= 1;
      }
    }
  }

  for (size_t cell = 0; cell < parity.size(); ++cell) {
    if (parity[cell] != 0) {
      return {false, "tensor mismatch at flattened coefficient " + std::to_string(cell)};
    }
  }
  return {true, "exact"};
}

VerifyResult verify_device_candidate(const Scheme& scheme, int published_rank,
                                     int published_density) {
  if (published_rank <= 0 || published_rank > kCap ||
      scheme.terms.size() != static_cast<size_t>(published_rank)) {
    return {false, "device/host rank disagreement"};
  }
  const VerifyResult verified = verify_exact(scheme);
  if (!verified.exact) return verified;
  if (density(scheme) != published_density) {
    return {false, "device/host density disagreement"};
  }
  return {true, "exact"};
}

void ensure_parent(const std::string& path) {
  const std::filesystem::path parent = std::filesystem::path(path).parent_path();
  if (!parent.empty()) std::filesystem::create_directories(parent);
}

void write_text_atomic(const std::string& path, const std::string& body) {
  if (path.empty()) return;
  ensure_parent(path);
  const std::string temp = path + ".tmp." + std::to_string(static_cast<long long>(getpid()));
  const int fd = open(temp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) throw std::runtime_error("open `" + temp + "`: " + std::strerror(errno));
  size_t offset = 0;
  while (offset < body.size()) {
    const ssize_t wrote = write(fd, body.data() + offset, body.size() - offset);
    if (wrote < 0) {
      const int saved = errno;
      close(fd);
      unlink(temp.c_str());
      throw std::runtime_error("write `" + temp + "`: " + std::strerror(saved));
    }
    offset += static_cast<size_t>(wrote);
  }
  if (fsync(fd) != 0) {
    const int saved = errno;
    close(fd);
    unlink(temp.c_str());
    throw std::runtime_error("fsync `" + temp + "`: " + std::strerror(saved));
  }
  if (close(fd) != 0) {
    const int saved = errno;
    unlink(temp.c_str());
    throw std::runtime_error("close `" + temp + "`: " + std::strerror(saved));
  }
  if (rename(temp.c_str(), path.c_str()) != 0) {
    const int saved = errno;
    unlink(temp.c_str());
    throw std::runtime_error("rename `" + temp + "`: " + std::strerror(saved));
  }
}

std::string serialize_scheme(const Scheme& scheme) {
  std::ostringstream out;
  out << scheme.terms.size() << '\n';
  for (const auto& term : scheme.terms) {
    out << term.u << ' ' << term.v << ' ' << term.w << '\n';
  }
  return out.str();
}

void write_scheme_atomic(const std::string& path, const Scheme& scheme) {
  const VerifyResult verified = verify_exact(scheme);
  if (!verified.exact) {
    throw std::runtime_error("refusing to checkpoint inexact scheme: " + verified.reason);
  }
  write_text_atomic(path, serialize_scheme(scheme));
}

[[maybe_unused]] Scheme permute_scheme(const Scheme& source, uint64_t salt) {
  Scheme shuffled = source;
  std::mt19937_64 rng(salt);
  std::shuffle(shuffled.terms.begin(), shuffled.terms.end(), rng);
  return shuffled;
}

[[maybe_unused]] bool objective_better(const Scheme& left, const Scheme& right) {
  if (left.terms.size() != right.terms.size()) return left.terms.size() < right.terms.size();
  return density(left) < density(right);
}

void improve_objective(Scheme& incumbent, const std::vector<Scheme>& candidates) {
  for (const auto& candidate : candidates) {
    if (objective_better(candidate, incumbent)) incumbent = candidate;
  }
}

// Raw term-support distance is the fleet archive's authoritative diversity
// metric.  All schemes reaching this path have already passed duplicate-term
// validation, so a sorted set intersection gives the exact symmetric
// difference without relying on a digest.
int support_distance(const Scheme& left, const Scheme& right) {
  std::vector<Term> left_terms = left.terms;
  std::vector<Term> right_terms = right.terms;
  std::sort(left_terms.begin(), left_terms.end());
  std::sort(right_terms.begin(), right_terms.end());
  size_t li = 0;
  size_t ri = 0;
  int common = 0;
  while (li < left_terms.size() && ri < right_terms.size()) {
    if (left_terms[li] < right_terms[ri]) {
      ++li;
    } else if (right_terms[ri] < left_terms[li]) {
      ++ri;
    } else {
      ++common;
      ++li;
      ++ri;
    }
  }
  return static_cast<int>(left_terms.size() + right_terms.size()) - 2 * common;
}

enum class LaunchRole : int { kLeader = 0, kOriginal = 1, kDescendant = 2 };

[[maybe_unused]] const char* launch_role_name(LaunchRole role) {
  if (role == LaunchRole::kLeader) return "leader";
  if (role == LaunchRole::kOriginal) return "original";
  return "descendant";
}

struct LaunchChoice {
  const Scheme* scheme = nullptr;
  LaunchRole role = LaunchRole::kLeader;
  size_t source_index = 0;
};

struct OriginalSourceStats {
  unsigned long long epochs = 0;
  unsigned long long exact_novel = 0;
  unsigned long long fleet_best = 0;
  unsigned long long last_slot = 0;
  bool visited = false;
};

constexpr unsigned long long kOriginalExploreEvery = 4;
constexpr unsigned long long kRoleExploreEvery = 4;

struct RoleStats {
  unsigned long long epochs = 0;
  unsigned long long exact_novel = 0;
  unsigned long long fleet_best = 0;
  unsigned long long last_adaptive_slot = 0;
  bool adaptive_visited = false;
};

unsigned long long reward_points(unsigned long long exact_novel,
                                 unsigned long long fleet_best) {
  // A rank/density improvement to the fleet leader is the primary objective;
  // a distinct exact door is still useful because it can found a fertile
  // descendant chain.  Both signals are counted only after the host gate.
  return exact_novel + 8ULL * fleet_best;
}

unsigned long long original_reward_points(const OriginalSourceStats& stats) {
  return reward_points(stats.exact_novel, stats.fleet_best);
}

unsigned long long role_reward_points(const RoleStats& stats) {
  return reward_points(stats.exact_novel, stats.fleet_best);
}

std::string original_source_stats_text(const std::vector<OriginalSourceStats>& stats) {
  std::ostringstream out;
  for (size_t i = 0; i < stats.size(); ++i) {
    if (i != 0) out << ';';
    out << i << ":v" << stats[i].epochs << ",n" << stats[i].exact_novel
        << ",b" << stats[i].fleet_best << ",p"
        << original_reward_points(stats[i]) << ",last";
    if (stats[i].visited) {
      out << stats[i].last_slot;
    } else {
      out << '-';
    }
  }
  return out.str();
}

std::string role_stats_text(const std::array<RoleStats, 3>& stats) {
  std::ostringstream out;
  for (size_t i = 0; i < stats.size(); ++i) {
    if (i != 0) out << ';';
    out << launch_role_name(static_cast<LaunchRole>(i)) << ":v" << stats[i].epochs
        << ",n" << stats[i].exact_novel << ",b" << stats[i].fleet_best
        << ",p" << role_reward_points(stats[i]) << ",lastA";
    if (stats[i].adaptive_visited) {
      out << stats[i].last_adaptive_slot;
    } else {
      out << '-';
    }
  }
  return out.str();
}

// Epoch zero in every four is an unconditional fleet-leader launch.  The
// other three slots adapt across all currently available roles.  Initial and
// one-in-four oldest-first exploration bound starvation; reward slots compare
// exact-gated useful yield per total role visit.  This retains a 25% leader
// floor while allowing productive original or descendant basins to consume
// the 75% that the old fixed 50/25/25 schedule could not reallocate.
struct LaunchScheduler {
  size_t descendant_cursor = 0;
  std::vector<unsigned long long> descendant_visits;
  unsigned long long original_slots = 0;
  unsigned long long adaptive_role_slots = 0;
  std::array<RoleStats, 3> role_stats{};
  std::vector<OriginalSourceStats> original_stats;

  std::vector<size_t> eligible_originals(const std::vector<Scheme>& original_roots,
                                         const Scheme& global_best) const {
    const std::string leader_key = canonical_key(global_best);
    std::vector<size_t> eligible;
    for (size_t i = 0; i < original_roots.size(); ++i) {
      if (canonical_key(original_roots[i]) != leader_key) eligible.push_back(i);
    }
    return eligible;
  }

  size_t choose_original(const std::vector<size_t>& eligible) {
    for (const size_t index : eligible) {
      if (!original_stats[index].visited) return index;
    }

    // Reserve one in every four original-role slots for oldest-first
    // exploration.  With E eligible roots, this bounds the gap between visits
    // to any continuously eligible root by 4E original slots.  Reward slots
    // use exact-gated yield per visit; oldest-first and then source index make
    // every tie deterministic and retain round-robin behavior when all yields
    // are neutral.
    const bool explore = (original_slots % kOriginalExploreEvery) == 0;
    size_t best = eligible.front();
    for (size_t position = 1; position < eligible.size(); ++position) {
      const size_t candidate = eligible[position];
      bool take = false;
      if (explore) {
        take = original_stats[candidate].last_slot < original_stats[best].last_slot;
      } else {
        const unsigned __int128 candidate_reward =
            static_cast<unsigned __int128>(original_reward_points(original_stats[candidate])) *
            original_stats[best].epochs;
        const unsigned __int128 best_reward =
            static_cast<unsigned __int128>(original_reward_points(original_stats[best])) *
            original_stats[candidate].epochs;
        if (candidate_reward != best_reward) {
          take = candidate_reward > best_reward;
        } else {
          take = original_stats[candidate].last_slot < original_stats[best].last_slot;
        }
      }
      if (!take && original_stats[candidate].last_slot == original_stats[best].last_slot) {
        take = candidate < best;
      }
      if (take) best = candidate;
    }
    return best;
  }

  LaunchChoice select_original(size_t index, const std::vector<Scheme>& original_roots) {
    OriginalSourceStats& stats = original_stats[index];
    stats.visited = true;
    stats.last_slot = original_slots;
    ++stats.epochs;
    ++original_slots;
    return {&original_roots[index], LaunchRole::kOriginal, index};
  }

  LaunchRole choose_adaptive_role(const std::vector<LaunchRole>& eligible) const {
    for (const LaunchRole role : eligible) {
      // The leader already receives an unconditional one-in-four visit. Spend
      // adaptive exploration on roles that otherwise have no floor.
      if (role != LaunchRole::kLeader &&
          !role_stats[static_cast<size_t>(role)].adaptive_visited) {
        return role;
      }
    }

    // Exploration is measured in adaptive slots, not wall epochs. With E
    // continuously eligible nonleader roles, oldest-first selection bounds
    // their gap to kRoleExploreEvery*E adaptive slots; the leader has its
    // independent fixed floor. Reward comparisons use cross products,
    // avoiding floating-point drift in deterministic replay.
    const bool explore = (adaptive_role_slots % kRoleExploreEvery) == 0;
    std::vector<LaunchRole> candidates;
    if (explore) {
      for (const LaunchRole role : eligible) {
        if (role != LaunchRole::kLeader) candidates.push_back(role);
      }
    }
    if (candidates.empty()) candidates = eligible;
    LaunchRole best = candidates.front();
    for (size_t position = 1; position < candidates.size(); ++position) {
      const LaunchRole candidate = candidates[position];
      const RoleStats& candidate_stats = role_stats[static_cast<size_t>(candidate)];
      const RoleStats& best_stats = role_stats[static_cast<size_t>(best)];
      bool take = false;
      if (explore) {
        take = candidate_stats.last_adaptive_slot < best_stats.last_adaptive_slot;
      } else {
        const unsigned __int128 candidate_reward =
            static_cast<unsigned __int128>(role_reward_points(candidate_stats)) *
            best_stats.epochs;
        const unsigned __int128 best_reward =
            static_cast<unsigned __int128>(role_reward_points(best_stats)) *
            candidate_stats.epochs;
        if (candidate_reward != best_reward) {
          take = candidate_reward > best_reward;
        } else {
          take = candidate_stats.last_adaptive_slot < best_stats.last_adaptive_slot;
        }
      }
      if (!take && candidate_stats.last_adaptive_slot == best_stats.last_adaptive_slot) {
        take = static_cast<int>(candidate) < static_cast<int>(best);
      }
      if (take) best = candidate;
    }
    return best;
  }

  LaunchChoice select_role(LaunchRole role, bool adaptive,
                           const std::vector<Scheme>& original_roots,
                           const std::vector<Scheme>& descendants,
                           const Scheme& global_best,
                           const std::vector<size_t>& originals) {
    LaunchChoice choice;
    if (role == LaunchRole::kLeader) {
      choice = {&global_best, role, 0};
    } else if (role == LaunchRole::kOriginal) {
      if (originals.empty()) throw std::runtime_error("selected unavailable original role");
      choice = select_original(choose_original(originals), original_roots);
    } else {
      if (descendants.empty()) throw std::runtime_error("selected unavailable descendant role");
      if (descendant_visits.size() < descendants.size()) {
        descendant_visits.resize(descendants.size());
      }
      const size_t index = descendant_cursor % descendants.size();
      ++descendant_cursor;
      ++descendant_visits[index];
      choice = {&descendants[index], role, index};
    }

    RoleStats& stats = role_stats[static_cast<size_t>(role)];
    ++stats.epochs;
    if (adaptive) {
      stats.adaptive_visited = true;
      stats.last_adaptive_slot = adaptive_role_slots;
      ++adaptive_role_slots;
    }
    return choice;
  }

  LaunchChoice choose(long long epoch, const std::vector<Scheme>& original_roots,
                      const std::vector<Scheme>& descendants,
                      const Scheme& global_best) {
    if (original_stats.size() < original_roots.size()) {
      original_stats.resize(original_roots.size());
    }
    const std::vector<size_t> originals = eligible_originals(original_roots, global_best);
    const int phase = static_cast<int>(epoch & 3LL);
    if (phase == 0) {
      return select_role(LaunchRole::kLeader, false, original_roots, descendants,
                         global_best, originals);
    }

    std::vector<LaunchRole> eligible = {LaunchRole::kLeader};
    if (!originals.empty()) eligible.push_back(LaunchRole::kOriginal);
    if (!descendants.empty()) eligible.push_back(LaunchRole::kDescendant);
    const LaunchRole role = choose_adaptive_role(eligible);
    return select_role(role, true, original_roots, descendants, global_best, originals);
  }

  void observe(const LaunchChoice& choice, bool exact_novel, bool fleet_best) {
    RoleStats& role = role_stats[static_cast<size_t>(choice.role)];
    if (role.epochs == 0) throw std::runtime_error("role outcome has no scheduled visit");
    if (exact_novel) ++role.exact_novel;
    if (fleet_best) ++role.fleet_best;

    if (choice.role == LaunchRole::kOriginal) {
      if (choice.source_index >= original_stats.size() ||
          !original_stats[choice.source_index].visited) {
        throw std::runtime_error("original-source outcome has no scheduled visit");
      }
      OriginalSourceStats& stats = original_stats[choice.source_index];
      if (exact_novel) ++stats.exact_novel;
      if (fleet_best) ++stats.fleet_best;
    }
  }
};

// Alternate within each role's own visit sequence so adaptive role selection
// cannot couple a productive role permanently to scan or hash mode.
int scheduled_partner_mode(long long, const LaunchChoice& choice,
                           const LaunchScheduler& scheduler) {
  if (choice.role == LaunchRole::kOriginal) {
    if (choice.source_index >= scheduler.original_stats.size() ||
        scheduler.original_stats[choice.source_index].epochs == 0) {
      throw std::runtime_error("original source has no visit parity");
    }
    // The first original visit uses hash, then every source alternates
    // independently. Source reward cadence cannot alias its kernel choice.
    return static_cast<int>(scheduler.original_stats[choice.source_index].epochs & 1ULL);
  }
  if (choice.role == LaunchRole::kDescendant) {
    if (choice.source_index >= scheduler.descendant_visits.size() ||
        scheduler.descendant_visits[choice.source_index] == 0) {
      throw std::runtime_error("descendant source has no visit parity");
    }
    return static_cast<int>((scheduler.descendant_visits[choice.source_index] - 1ULL) &
                            1ULL);
  }
  const RoleStats& role = scheduler.role_stats[static_cast<size_t>(choice.role)];
  if (role.epochs == 0) throw std::runtime_error("role has no visit parity");
  return static_cast<int>((role.epochs - 1ULL) & 1ULL);
}

// Score only the replaceable portion of the door bank.  Root/root distances
// are immutable and therefore must not prevent a descendant replacement from
// improving every distance that the policy can actually change.
int descendant_bank_score(const std::vector<Scheme>& roots,
                          const std::vector<Scheme>& descendants,
                          int replace = -1, const Scheme* replacement = nullptr) {
  if (descendants.empty()) return INT_MAX;
  int score = INT_MAX;
  auto descendant_at = [&](size_t index) -> const Scheme& {
    if (static_cast<int>(index) == replace) return *replacement;
    return descendants[index];
  };
  for (size_t i = 0; i < descendants.size(); ++i) {
    const Scheme& left = descendant_at(i);
    for (const auto& root : roots) score = std::min(score, support_distance(left, root));
    for (size_t j = i + 1; j < descendants.size(); ++j) {
      score = std::min(score, support_distance(left, descendant_at(j)));
    }
  }
  return score;
}

struct DoorAdmission {
  // 0 rejects, 1 appends, and 2+ replaces descendant slot action-2.
  int action = 0;
  int score = -1;
  // True only when an objectively better child replaced its own launch slot
  // after normal max-min admission rejected it.
  bool source_replacement = false;
};

DoorAdmission admit_descendant(const std::vector<Scheme>& roots,
                               std::vector<Scheme>& descendants,
                               const Scheme& candidate, size_t capacity,
                               int min_distance) {
  if (capacity == 0) return {};

  int candidate_min = INT_MAX;
  for (const auto& root : roots) {
    candidate_min = std::min(candidate_min, support_distance(candidate, root));
  }
  if (descendants.size() < capacity) {
    for (const auto& door : descendants) {
      candidate_min = std::min(candidate_min, support_distance(candidate, door));
    }
    if (candidate_min < min_distance) return {};
    descendants.push_back(candidate);
    return {1, descendant_bank_score(roots, descendants)};
  }

  const int current_score = descendant_bank_score(roots, descendants);
  int best_score = current_score;
  int best_slot = -1;
  for (size_t slot = 0; slot < descendants.size(); ++slot) {
    const int trial = descendant_bank_score(roots, descendants,
                                            static_cast<int>(slot), &candidate);
    // Strict improvement and ascending slot order make replay deterministic.
    if (trial >= min_distance && trial > best_score) {
      best_score = trial;
      best_slot = static_cast<int>(slot);
    }
  }
  if (best_slot < 0) return {0, current_score};
  descendants[static_cast<size_t>(best_slot)] = candidate;
  return {best_slot + 2, best_score};
}

DoorAdmission admit_descendant_from_source(const std::vector<Scheme>& roots,
                                           std::vector<Scheme>& descendants,
                                           const Scheme& candidate, size_t capacity,
                                           int min_distance, LaunchRole launch_role,
                                           size_t source_index) {
  DoorAdmission admission =
      admit_descendant(roots, descendants, candidate, capacity, min_distance);
  if (admission.action != 0 || launch_role != LaunchRole::kDescendant ||
      source_index >= descendants.size() || capacity == 0) {
    return admission;
  }

  // A density/rank improvement can be close to the descendant that produced
  // it by construction.  Permit that one edge in the chain, but never waive
  // distance to an immutable root or any other live descendant.
  if (!objective_better(candidate, descendants[source_index])) return admission;
  for (const auto& root : roots) {
    if (support_distance(candidate, root) < min_distance) return admission;
  }
  for (size_t i = 0; i < descendants.size(); ++i) {
    if (i != source_index && support_distance(candidate, descendants[i]) < min_distance) {
      return admission;
    }
  }

  descendants[source_index] = candidate;
  return {static_cast<int>(source_index) + 2,
          descendant_bank_score(roots, descendants), true};
}

// The absolute endpoint retains the source-aware density-chain exception.
// Additional top-K endpoints did not launch from the selected descendant, so
// they may enter only through the ordinary all-door distance gate. Duplicate
// archive artifacts cannot provide a new live basin and are skipped here.
DoorAdmission admit_harvested_descendant(
    const std::vector<Scheme>& roots, std::vector<Scheme>& descendants,
    const Scheme& candidate, size_t capacity, int min_distance,
    bool absolute_winner, bool exact_novel, LaunchRole launch_role,
    size_t source_index) {
  if (!exact_novel) return {};
  if (absolute_winner) {
    return admit_descendant_from_source(roots, descendants, candidate, capacity,
                                        min_distance, launch_role, source_index);
  }
  return admit_descendant(roots, descendants, candidate, capacity, min_distance);
}

// Restart replay is a structural farthest-first rebuild, not lexicographic
// first-come admission.  Canonical keys break equal-distance ties only after
// exact support distance has chosen the most novel remaining artifact.
void rebuild_descendants_diverse(const std::vector<Scheme>& roots,
                                 std::vector<Scheme> candidates,
                                 std::vector<Scheme>& descendants,
                                 size_t capacity, int min_distance) {
  std::vector<Scheme> chain_candidates = candidates;
  descendants.clear();
  std::sort(candidates.begin(), candidates.end(),
            [](const Scheme& left, const Scheme& right) {
              return canonical_key(left) < canonical_key(right);
            });
  while (descendants.size() < capacity && !candidates.empty()) {
    size_t best_index = 0;
    int best_distance = -1;
    for (size_t i = 0; i < candidates.size(); ++i) {
      int distance = INT_MAX;
      for (const auto& root : roots) {
        distance = std::min(distance, support_distance(candidates[i], root));
      }
      for (const auto& door : descendants) {
        distance = std::min(distance, support_distance(candidates[i], door));
      }
      if (distance > best_distance) {
        best_distance = distance;
        best_index = i;
      }
    }
    if (best_distance < min_distance) break;
    descendants.push_back(std::move(candidates[best_index]));
    candidates.erase(candidates.begin() + static_cast<std::ptrdiff_t>(best_index));
  }

  // A full farthest-first bank can still admit a later artifact if replacing
  // one selected slot strictly raises the exact max-min score.
  if (descendants.size() == capacity) {
    for (const auto& candidate : candidates) {
      (void)admit_descendant(roots, descendants, candidate, capacity, min_distance);
    }
  }

  // Max-min replay intentionally prefers far support, which can otherwise
  // resurrect a worse parent over its archived density/rank-chain child. Run a
  // deterministic objective-best pass after the normal rebuild. A candidate
  // may replace exactly one live door inside the floor (its inferred parent),
  // and must retain the floor to every root and every other descendant.
  std::sort(chain_candidates.begin(), chain_candidates.end(),
            [](const Scheme& left, const Scheme& right) {
              if (objective_better(left, right)) return true;
              if (objective_better(right, left)) return false;
              return canonical_key(left) < canonical_key(right);
            });
  for (const auto& candidate : chain_candidates) {
    bool root_ok = true;
    for (const auto& root : roots) {
      if (support_distance(candidate, root) < min_distance) {
        root_ok = false;
        break;
      }
    }
    if (!root_ok) continue;

    size_t below_slot = descendants.size();
    int below_count = 0;
    for (size_t slot = 0; slot < descendants.size(); ++slot) {
      if (support_distance(candidate, descendants[slot]) < min_distance) {
        below_slot = slot;
        ++below_count;
      }
    }
    if (below_count != 1 || !objective_better(candidate, descendants[below_slot])) continue;
    descendants[below_slot] = candidate;
  }
}

[[maybe_unused]] size_t scheduled_door_count(const std::vector<Scheme>& roots,
                                             const std::vector<Scheme>& descendants,
                                             const Scheme& global_best) {
  const std::string leader_key = canonical_key(global_best);
  for (const auto& root : roots) {
    if (canonical_key(root) == leader_key) return roots.size() + descendants.size();
  }
  for (const auto& door : descendants) {
    if (canonical_key(door) == leader_key) return roots.size() + descendants.size();
  }
  return roots.size() + descendants.size() + 1;
}

int self_test(const std::string& seed_path) {
  Scheme seed = load_scheme(seed_path);
  const VerifyResult seed_result = verify_exact(seed);
  if (!seed_result.exact) {
    std::cerr << "CUDA777_SELF_TEST seed rejected: " << seed_result.reason << '\n';
    return 1;
  }
  if (seed.terms.size() != 247 || density(seed) <= 0) {
    std::cerr << "CUDA777_SELF_TEST unexpected seed objective\n";
    return 1;
  }
  if (!verify_device_candidate(seed, 247, density(seed)).exact ||
      verify_device_candidate(seed, 246, density(seed)).exact ||
      verify_device_candidate(seed, 247, density(seed) + 1).exact) {
    std::cerr << "CUDA777_SELF_TEST device-candidate metadata gate failed\n";
    return 1;
  }

  Scheme corrupt = seed;
  corrupt.terms[0].u ^= 1;
  if (verify_exact(corrupt).exact ||
      verify_device_candidate(corrupt, 247, density(corrupt)).exact) {
    std::cerr << "CUDA777_SELF_TEST controlled corruption was accepted\n";
    return 1;
  }

  const std::string roundtrip = "/tmp/metaflip_cuda_777_selftest_" +
                                std::to_string(static_cast<long long>(getpid())) + ".txt";
  write_scheme_atomic(roundtrip, seed);
  Scheme loaded = load_scheme(roundtrip);
  unlink(roundtrip.c_str());
  if (!verify_exact(loaded).exact || canonical_key(seed) != canonical_key(loaded)) {
    std::cerr << "CUDA777_SELF_TEST atomic round trip failed\n";
    return 1;
  }

  std::cout << "CUDA777_SELF_TEST ok rank=" << seed.terms.size()
            << " density=" << density(seed) << '\n';
  return 0;
}

Scheme policy_test_scheme(std::initializer_list<uint64_t> values) {
  Scheme scheme;
  for (const uint64_t value : values) scheme.terms.push_back({value, 1, 1});
  return scheme;
}

int policy_self_test(const std::vector<std::string>& recipe_paths) {
  const Scheme root0 = policy_test_scheme({1, 2, 3});
  const Scheme root1 = policy_test_scheme({11, 12, 13});
  const Scheme root2 = policy_test_scheme({21, 22, 23});
  const Scheme root3 = policy_test_scheme({31, 32, 33});
  const Scheme root4 = policy_test_scheme({41, 42, 43});
  const std::vector<Scheme> roots = {root0, root1, root2, root3, root4};
  const std::vector<Scheme> scheduled_descendants = {
      policy_test_scheme({51, 52, 53}), policy_test_scheme({61, 62, 63}),
      policy_test_scheme({71, 72, 73})};

  // Start from the last (and deliberately denser) root so this also exercises
  // the objective promotion used by a real campaign.  The five-root recipe
  // supplies d3094 first, followed by four structurally different shoulders.
  Scheme synthetic_best = roots.back();
  improve_objective(synthetic_best, roots);
  if (canonical_key(synthetic_best) != canonical_key(root0)) {
    throw std::runtime_error("five-root objective selection did not promote the leader");
  }

  std::array<int, 3> role_counts{};
  std::array<std::array<int, 2>, 3> role_modes{};
  std::array<int, 5> root_counts{};
  std::vector<std::pair<int, size_t>> trace;
  std::vector<int> mode_trace;
  std::vector<size_t> initial_originals;
  LaunchScheduler scheduler;
  for (long long epoch = 0; epoch < 67; ++epoch) {
    const LaunchChoice choice = scheduler.choose(epoch, roots, scheduled_descendants, root0);
    if (choice.scheme == nullptr) throw std::runtime_error("policy selected a null scheme");
    const int partner_mode = scheduled_partner_mode(epoch, choice, scheduler);
    ++role_counts[static_cast<size_t>(choice.role)];
    ++role_modes[static_cast<size_t>(choice.role)]
                [static_cast<size_t>(partner_mode)];
    if (choice.role == LaunchRole::kOriginal) {
      ++root_counts[choice.source_index];
      if (initial_originals.size() < 4) initial_originals.push_back(choice.source_index);
    }
    trace.push_back({static_cast<int>(choice.role), choice.source_index});
    mode_trace.push_back(partner_mode);
  }
  if (role_counts[0] + role_counts[1] + role_counts[2] != 67 ||
      role_counts[0] * 4 < 67 || role_counts[1] < 1 || role_counts[2] < 1 ||
      root_counts[0] != 0) {
    throw std::runtime_error("67-epoch neutral role schedule regression");
  }
  if (initial_originals != std::vector<size_t>({1, 2, 3, 4})) {
    throw std::runtime_error("adaptive originals skipped initial exploration");
  }
  for (size_t role = 0; role < role_modes.size(); ++role) {
    const auto& modes = role_modes[role];
    if (modes[0] == 0 || modes[1] == 0 ||
        (role != static_cast<size_t>(LaunchRole::kOriginal) &&
         std::abs(modes[0] - modes[1]) > 1)) {
      throw std::runtime_error("role became coupled to one partner mode");
    }
  }
  if (mode_trace[0] != 0 || mode_trace[1] != 1) {
    throw std::runtime_error("two-epoch smoke no longer covers scan and hash");
  }

  LaunchScheduler replay;
  for (long long epoch = 0; epoch < 67; ++epoch) {
    const LaunchChoice choice = replay.choose(epoch, roots, scheduled_descendants, root0);
    if (trace[static_cast<size_t>(epoch)] !=
        std::make_pair(static_cast<int>(choice.role), choice.source_index)) {
      throw std::runtime_error("role schedule is not deterministic");
    }
    if (mode_trace[static_cast<size_t>(epoch)] !=
        scheduled_partner_mode(epoch, choice, replay)) {
      throw std::runtime_error("partner-mode schedule is not deterministic");
    }
  }

  // A missing descendant pool is removed from adaptive eligibility without
  // weakening the unconditional leader floor.
  LaunchScheduler fallback;
  int fallback_leader = 0;
  for (long long epoch = 0; epoch < 67; ++epoch) {
    const LaunchChoice choice = fallback.choose(epoch, roots, {}, root0);
    if (choice.role == LaunchRole::kLeader) ++fallback_leader;
  }
  if (fallback_leader * 4 < 67) throw std::runtime_error("fallback lost leader floor");

  LaunchScheduler leader_only;
  std::array<int, 2> leader_only_modes{};
  for (long long epoch = 0; epoch < 17; ++epoch) {
    const LaunchChoice choice = leader_only.choose(epoch, {root0}, {}, root0);
    if (choice.role != LaunchRole::kLeader || choice.scheme == nullptr) {
      throw std::runtime_error("leader-only fallback selected an unavailable role");
    }
    ++leader_only_modes[static_cast<size_t>(
        scheduled_partner_mode(epoch, choice, leader_only))];
  }
  if (std::abs(leader_only_modes[0] - leader_only_modes[1]) > 1) {
    throw std::runtime_error("leader-only fallback lost partner-mode balance");
  }

  LaunchScheduler late_descendant;
  for (long long epoch = 0; epoch < 8; ++epoch) {
    const LaunchChoice choice = late_descendant.choose(epoch, roots, {}, root0);
    late_descendant.observe(choice, false, false);
  }
  bool late_descendant_seen = false;
  for (long long epoch = 8; epoch < 12; ++epoch) {
    const LaunchChoice choice =
        late_descendant.choose(epoch, roots, scheduled_descendants, root0);
    if (choice.role == LaunchRole::kDescendant) late_descendant_seen = true;
    late_descendant.observe(choice, false, false);
  }
  if (!late_descendant_seen) {
    throw std::runtime_error("newly available descendant role was not explored promptly");
  }

  // Aggregate role parity aliases with round-robin source selection when the
  // bank size is even. Each descendant slot must therefore own its parity.
  LaunchScheduler two_descendants;
  const std::vector<Scheme> even_descendants = {
      scheduled_descendants[0], scheduled_descendants[1]};
  std::array<std::array<int, 2>, 2> descendant_modes{};
  for (long long epoch = 0; epoch < 80; ++epoch) {
    const LaunchChoice choice =
        two_descendants.choose(epoch, {root0}, even_descendants, root0);
    const int partner_mode = scheduled_partner_mode(epoch, choice, two_descendants);
    if (choice.role == LaunchRole::kDescendant) {
      ++descendant_modes[choice.source_index][static_cast<size_t>(partner_mode)];
    }
    two_descendants.observe(choice, false, false);
  }
  for (const auto& modes : descendant_modes) {
    if (modes[0] == 0 || modes[1] == 0 || std::abs(modes[0] - modes[1]) > 1) {
      throw std::runtime_error("even descendant bank pinned a source to one partner mode");
    }
  }

  LaunchScheduler long_run;
  std::array<int, 3> long_roles{};
  std::array<int, 5> long_roots{};
  for (long long epoch = 0; epoch < 1003; ++epoch) {
    const LaunchChoice choice = long_run.choose(epoch, roots, scheduled_descendants, root0);
    ++long_roles[static_cast<size_t>(choice.role)];
    if (choice.role == LaunchRole::kOriginal) ++long_roots[choice.source_index];
    if (long_roles[0] * 4 < epoch + 1) {
      throw std::runtime_error("leader quota failed at a schedule prefix");
    }
  }
  const int root_min =
      std::min({long_roots[1], long_roots[2], long_roots[3], long_roots[4]});
  const int root_max =
      std::max({long_roots[1], long_roots[2], long_roots[3], long_roots[4]});
  if (root_max - root_min > 1) throw std::runtime_error("original roots were not fair");

  // Reproduce the observed campaign shape: source 3 emits three exact-novel
  // artifacts (including one fleet best), while every other original stays
  // neutral.  The productive source must win exploitation slots, but the
  // fixed exploration cadence must bound every neutral source's visit gap.
  constexpr long long kAdaptiveEpochs = 4099;
  constexpr unsigned long long kEligibleOriginals = 4;
  constexpr unsigned long long kMaxOriginalGap =
      kOriginalExploreEvery * kEligibleOriginals;
  constexpr unsigned long long kEligibleNonleaderRoles = 2;
  constexpr unsigned long long kMaxRoleGap =
      kRoleExploreEvery * kEligibleNonleaderRoles;
  LaunchScheduler adaptive;
  std::array<unsigned long long, 5> adaptive_counts{};
  std::array<unsigned long long, 5> last_visit{};
  std::array<bool, 5> seen_visit{};
  std::array<std::array<unsigned long long, 2>, 5> adaptive_modes{};
  std::array<unsigned long long, 3> adaptive_role_counts{};
  std::array<unsigned long long, 3> adaptive_role_last{};
  std::array<bool, 3> adaptive_role_seen{};
  std::vector<std::pair<int, size_t>> adaptive_trace;
  std::vector<int> adaptive_mode_trace;
  for (long long adaptive_epoch = 0; adaptive_epoch < kAdaptiveEpochs; ++adaptive_epoch) {
    const LaunchChoice choice =
        adaptive.choose(adaptive_epoch, roots, scheduled_descendants, root0);
    adaptive_trace.push_back({static_cast<int>(choice.role), choice.source_index});
    const int partner_mode = scheduled_partner_mode(adaptive_epoch, choice, adaptive);
    adaptive_mode_trace.push_back(partner_mode);
    ++adaptive_role_counts[static_cast<size_t>(choice.role)];
    if ((adaptive_epoch & 3LL) != 0) {
      const size_t role_index = static_cast<size_t>(choice.role);
      const unsigned long long role_slot = adaptive.adaptive_role_slots - 1;
      if (adaptive_role_seen[role_index] &&
          role_slot - adaptive_role_last[role_index] > kMaxRoleGap) {
        throw std::runtime_error("adaptive role exploration starved a role");
      }
      adaptive_role_seen[role_index] = true;
      adaptive_role_last[role_index] = role_slot;
    }
    if (choice.role != LaunchRole::kOriginal) continue;
    const unsigned long long slot = adaptive.original_slots - 1;
    if (seen_visit[choice.source_index] &&
        slot - last_visit[choice.source_index] > kMaxOriginalGap) {
      throw std::runtime_error("adaptive original exploration starved a source");
    }
    seen_visit[choice.source_index] = true;
    last_visit[choice.source_index] = slot;
    ++adaptive_counts[choice.source_index];
    ++adaptive_modes[choice.source_index][static_cast<size_t>(partner_mode)];
    // Source 3 is deliberately fertile only in scan mode. Its independent
    // visit parity must still expose that mode even after reward exploitation
    // changes the global epoch cadence.
    const bool exact_novel =
        choice.source_index == 3 && partner_mode == 0 &&
        adaptive.original_stats[3].exact_novel < 3;
    const bool fleet_best = exact_novel && adaptive.original_stats[3].exact_novel == 1;
    adaptive.observe(choice, exact_novel, fleet_best);
  }
  for (size_t source = 1; source < roots.size(); ++source) {
    if (!seen_visit[source] ||
        (adaptive.original_slots - 1) - last_visit[source] > kMaxOriginalGap) {
      throw std::runtime_error("adaptive original exploration has an unbounded tail");
    }
    if (adaptive_modes[source][0] == 0 || adaptive_modes[source][1] == 0 ||
        std::abs(static_cast<long long>(adaptive_modes[source][0]) -
                 static_cast<long long>(adaptive_modes[source][1])) > 1) {
      throw std::runtime_error("adaptive source became coupled to one partner mode");
    }
  }
  for (size_t role = 1; role < adaptive_role_seen.size(); ++role) {
    if (!adaptive_role_seen[role] ||
        (adaptive.adaptive_role_slots - 1) - adaptive_role_last[role] > kMaxRoleGap) {
      throw std::runtime_error("adaptive role exploration has an unbounded tail");
    }
  }
  if (adaptive_role_counts[0] * 4 < kAdaptiveEpochs ||
      adaptive_role_counts[1] <= adaptive_role_counts[0] ||
      adaptive_role_counts[1] <= adaptive_role_counts[2]) {
    throw std::runtime_error("productive original role did not earn surplus slots");
  }
  if (adaptive_counts[3] <= 2 * std::max({adaptive_counts[1], adaptive_counts[2],
                                          adaptive_counts[4]}) ||
      adaptive.original_stats[3].exact_novel != 3 ||
      adaptive.original_stats[3].fleet_best != 1) {
    throw std::runtime_error("productive original did not earn preferential scheduling");
  }

  LaunchScheduler adaptive_replay;
  for (long long adaptive_epoch = 0; adaptive_epoch < kAdaptiveEpochs; ++adaptive_epoch) {
    const LaunchChoice choice =
        adaptive_replay.choose(adaptive_epoch, roots, scheduled_descendants, root0);
    if (adaptive_trace[static_cast<size_t>(adaptive_epoch)] !=
        std::make_pair(static_cast<int>(choice.role), choice.source_index)) {
      throw std::runtime_error("adaptive reward schedule is not deterministic");
    }
    const int partner_mode =
        scheduled_partner_mode(adaptive_epoch, choice, adaptive_replay);
    if (adaptive_mode_trace[static_cast<size_t>(adaptive_epoch)] != partner_mode) {
      throw std::runtime_error("adaptive partner-mode replay is not deterministic");
    }
    if (choice.role == LaunchRole::kOriginal) {
      const bool exact_novel =
          choice.source_index == 3 && partner_mode == 0 &&
          adaptive_replay.original_stats[3].exact_novel < 3;
      adaptive_replay.observe(
          choice, exact_novel,
          exact_novel && adaptive_replay.original_stats[3].exact_novel == 1);
    }
  }

  // Descendant yield dominates the harvested 7x7 campaign. Model an exact
  // novel descendant on every such visit and prove that the reallocatable
  // slots move there while the leader floor and role exploration survive.
  LaunchScheduler descendant_adaptive;
  std::array<unsigned long long, 3> descendant_role_counts{};
  std::array<unsigned long long, 3> descendant_last{};
  std::array<bool, 3> descendant_seen{};
  for (long long adaptive_epoch = 0; adaptive_epoch < kAdaptiveEpochs;
       ++adaptive_epoch) {
    const LaunchChoice choice = descendant_adaptive.choose(
        adaptive_epoch, roots, scheduled_descendants, root0);
    ++descendant_role_counts[static_cast<size_t>(choice.role)];
    if (descendant_role_counts[0] * 4 <
        static_cast<unsigned long long>(adaptive_epoch + 1)) {
      throw std::runtime_error("adaptive role policy violated leader floor");
    }
    if ((adaptive_epoch & 3LL) != 0) {
      const size_t role = static_cast<size_t>(choice.role);
      const unsigned long long slot = descendant_adaptive.adaptive_role_slots - 1;
      if (descendant_seen[role] &&
          slot - descendant_last[role] > kMaxRoleGap) {
        throw std::runtime_error("productive-role policy starved exploration");
      }
      descendant_seen[role] = true;
      descendant_last[role] = slot;
    }
    descendant_adaptive.observe(choice, choice.role == LaunchRole::kDescendant, false);
  }
  for (size_t role = 1; role < descendant_seen.size(); ++role) {
    if (!descendant_seen[role] ||
        (descendant_adaptive.adaptive_role_slots - 1) - descendant_last[role] >
            kMaxRoleGap) {
      throw std::runtime_error("productive-role policy has an unbounded tail");
    }
  }
  if (descendant_role_counts[2] <= descendant_role_counts[0] ||
      descendant_role_counts[2] <= descendant_role_counts[1] ||
      descendant_adaptive.role_stats[2].exact_novel != descendant_role_counts[2]) {
    throw std::runtime_error("productive descendant role did not earn surplus slots");
  }

  const Scheme bank_root0 = policy_test_scheme({1, 2, 3, 4, 5, 6, 7, 8, 9, 10});
  const Scheme bank_root1 =
      policy_test_scheme({101, 102, 103, 104, 105, 106, 107, 108, 109, 110});
  const Scheme child_a =
      policy_test_scheme({201, 202, 203, 204, 205, 206, 207, 208, 209, 210});
  const Scheme near_a =
      policy_test_scheme({201, 202, 203, 204, 205, 206, 207, 208, 501, 502});
  const Scheme child_b =
      policy_test_scheme({201, 202, 203, 204, 301, 302, 303, 304, 305, 306});
  const Scheme child_c =
      policy_test_scheme({401, 402, 403, 404, 405, 406, 407, 408, 409, 410});
  const std::vector<Scheme> bank_roots = {bank_root0, bank_root1};
  std::vector<Scheme> bank;
  DoorAdmission admission = admit_descendant(bank_roots, bank, child_a, 2, 12);
  if (admission.action != 1 || bank.size() != 1) {
    throw std::runtime_error("max-min policy failed to append a distant child");
  }
  admission = admit_descendant(bank_roots, bank, near_a, 2, 12);
  if (admission.action != 0 || bank.size() != 1 || support_distance(child_a, near_a) != 4) {
    throw std::runtime_error("max-min policy admitted a near-duplicate child");
  }
  admission = admit_descendant(bank_roots, bank, child_b, 2, 12);
  if (admission.action != 1 || admission.score != 12 || bank.size() != 2) {
    throw std::runtime_error("max-min policy boundary admission failed");
  }
  admission = admit_descendant_from_source(bank_roots, bank, child_c, 2, 12,
                                            LaunchRole::kDescendant, 0);
  if (admission.action != 2 || admission.score != 20 || admission.source_replacement ||
      bank[0].terms != child_c.terms) {
    throw std::runtime_error("max-min policy failed deterministic diversity eviction");
  }

  const Scheme chain_parent =
      policy_test_scheme({601, 602, 603, 604, 605, 606, 607, 608, 609, 610});
  const Scheme chain_other =
      policy_test_scheme({701, 702, 703, 704, 705, 706, 707, 708, 709, 710});
  const Scheme chain_child =
      policy_test_scheme({601, 602, 603, 604, 605, 606, 607, 608, 609});
  std::vector<Scheme> chain_bank = {chain_parent, chain_other};
  admission = admit_descendant_from_source(bank_roots, chain_bank, chain_child, 2, 12,
                                            LaunchRole::kDescendant, 0);
  if (admission.action != 2 || !admission.source_replacement || admission.score != 19 ||
      chain_bank[0].terms != chain_child.terms) {
    throw std::runtime_error("source-aware density chain did not replace its parent");
  }

  const Scheme too_close_to_other =
      policy_test_scheme({701, 702, 703, 704, 705, 706, 707, 708, 709});
  chain_bank = {chain_parent, chain_other};
  admission = admit_descendant_from_source(bank_roots, chain_bank, too_close_to_other, 2, 12,
                                            LaunchRole::kDescendant, 0);
  if (admission.action != 0 || admission.source_replacement ||
      chain_bank[0].terms != chain_parent.terms) {
    throw std::runtime_error("source-aware replacement waived another-door distance");
  }

  chain_bank = {chain_parent, chain_other};
  admission = admit_descendant_from_source(bank_roots, chain_bank, chain_parent, 2, 12,
                                            LaunchRole::kDescendant, 0);
  if (admission.action != 0 || admission.source_replacement) {
    throw std::runtime_error("source-aware replacement accepted a non-improvement");
  }

  const Scheme too_close_to_root =
      policy_test_scheme({1, 2, 3, 4, 5, 6, 7, 8, 9});
  chain_bank = {chain_parent, chain_other};
  admission = admit_descendant_from_source(bank_roots, chain_bank, too_close_to_root, 2, 12,
                                            LaunchRole::kDescendant, 0);
  if (admission.action != 0 || admission.source_replacement) {
    throw std::runtime_error("source-aware replacement waived a root distance");
  }

  chain_bank = {chain_parent, chain_other};
  admission = admit_descendant_from_source(bank_roots, chain_bank, chain_child, 2, 12,
                                            LaunchRole::kOriginal, 0);
  if (admission.action != 0 || admission.source_replacement) {
    throw std::runtime_error("source-aware replacement escaped its descendant role");
  }

  // Top-K auxiliary artifacts are useful only when they are exact-novel and
  // independently satisfy the normal diversity floor. They must not inherit
  // the absolute winner's one-parent density-chain exception.
  chain_bank = {chain_parent, chain_other};
  DoorAdmission harvested_admission = admit_harvested_descendant(
      bank_roots, chain_bank, chain_child, 2, 12, true, true,
      LaunchRole::kDescendant, 0);
  if (harvested_admission.action != 2 ||
      !harvested_admission.source_replacement ||
      chain_bank[0].terms != chain_child.terms) {
    throw std::runtime_error("absolute harvest lost source-aware replacement");
  }

  std::vector<Scheme> harvested_bank;
  harvested_admission = admit_harvested_descendant(
      bank_roots, harvested_bank, child_a, 2, 12, false, true,
      LaunchRole::kDescendant, 0);
  if (harvested_admission.action != 1 || harvested_bank.size() != 1 ||
      harvested_admission.source_replacement) {
    throw std::runtime_error("novel auxiliary harvest did not enter the door bank");
  }
  harvested_admission = admit_harvested_descendant(
      bank_roots, harvested_bank, child_a, 2, 12, false, false,
      LaunchRole::kDescendant, 0);
  if (harvested_admission.action != 0 || harvested_bank.size() != 1) {
    throw std::runtime_error("duplicate auxiliary harvest changed the door bank");
  }
  harvested_admission = admit_harvested_descendant(
      bank_roots, harvested_bank, near_a, 2, 12, false, true,
      LaunchRole::kDescendant, 0);
  if (harvested_admission.action != 0 || harvested_bank.size() != 1 ||
      harvested_admission.source_replacement) {
    throw std::runtime_error("auxiliary harvest bypassed the normal distance floor");
  }

  std::vector<Scheme> replay_forward;
  std::vector<Scheme> replay_reverse;
  rebuild_descendants_diverse(bank_roots, {child_a, near_a, child_b, child_c},
                              replay_forward, 2, 12);
  rebuild_descendants_diverse(bank_roots, {child_c, child_b, near_a, child_a},
                              replay_reverse, 2, 12);
  std::set<std::string> forward_keys;
  std::set<std::string> reverse_keys;
  for (const auto& item : replay_forward) forward_keys.insert(canonical_key(item));
  for (const auto& item : replay_reverse) reverse_keys.insert(canonical_key(item));
  if (replay_forward.size() != 2 || forward_keys != reverse_keys ||
      descendant_bank_score(bank_roots, replay_forward) != 20) {
    throw std::runtime_error("archive replay was path-order-dependent or non-diverse");
  }

  std::vector<Scheme> chain_replay_forward;
  std::vector<Scheme> chain_replay_reverse;
  rebuild_descendants_diverse(bank_roots, {chain_parent, chain_child, chain_other},
                              chain_replay_forward, 2, 12);
  rebuild_descendants_diverse(bank_roots, {chain_other, chain_child, chain_parent},
                              chain_replay_reverse, 2, 12);
  std::set<std::string> chain_forward_keys;
  std::set<std::string> chain_reverse_keys;
  for (const auto& item : chain_replay_forward) {
    chain_forward_keys.insert(canonical_key(item));
  }
  for (const auto& item : chain_replay_reverse) {
    chain_reverse_keys.insert(canonical_key(item));
  }
  const std::set<std::string> expected_chain_keys = {
      canonical_key(chain_child), canonical_key(chain_other)};
  if (chain_forward_keys != expected_chain_keys ||
      chain_reverse_keys != expected_chain_keys ||
      descendant_bank_score(bank_roots, chain_replay_forward) != 19) {
    throw std::runtime_error("archive replay resurrected a density-chain parent");
  }

  const Scheme close_to_parent_and_other =
      policy_test_scheme({601, 602, 603, 604, 701, 702, 703, 704, 705});
  std::vector<Scheme> guarded_replay;
  rebuild_descendants_diverse(
      bank_roots, {chain_parent, chain_other, close_to_parent_and_other},
      guarded_replay, 2, 12);
  std::set<std::string> guarded_keys;
  for (const auto& item : guarded_replay) guarded_keys.insert(canonical_key(item));
  const std::set<std::string> expected_parent_keys = {
      canonical_key(chain_parent), canonical_key(chain_other)};
  if (guarded_keys != expected_parent_keys) {
    throw std::runtime_error("archive chain advancement waived a second-door distance");
  }

  rebuild_descendants_diverse(bank_roots, {chain_parent, chain_other, too_close_to_root},
                              guarded_replay, 2, 12);
  guarded_keys.clear();
  for (const auto& item : guarded_replay) guarded_keys.insert(canonical_key(item));
  if (guarded_keys != expected_parent_keys) {
    throw std::runtime_error("archive chain advancement waived a root distance");
  }

  if (!recipe_paths.empty()) {
    std::vector<Scheme> recipe_roots;
    std::set<std::string> recipe_keys;
    for (const auto& path : recipe_paths) {
      Scheme root = load_scheme(path);
      const VerifyResult verified = verify_exact(root);
      if (!verified.exact) {
        throw std::runtime_error(path + ": inexact policy recipe root: " + verified.reason);
      }
      if (recipe_keys.insert(canonical_key(root)).second) {
        recipe_roots.push_back(std::move(root));
      }
    }
    if (recipe_roots.empty()) {
      throw std::runtime_error("policy recipe did not contain a distinct exact root");
    }

    // Begin at the final root to catch accidental first-seed assumptions. The
    // shell regression asserts that the current five-root recipe selects the
    // first supplied d3094 certificate after objective comparison.
    Scheme recipe_best = recipe_roots.back();
    improve_objective(recipe_best, recipe_roots);
    size_t best_source = recipe_roots.size();
    const std::string best_key = canonical_key(recipe_best);
    for (size_t i = 0; i < recipe_roots.size(); ++i) {
      if (canonical_key(recipe_roots[i]) == best_key) {
        best_source = i;
        break;
      }
    }
    if (best_source == recipe_roots.size()) {
      throw std::runtime_error("policy recipe objective is not one of its roots");
    }
    std::cout << "CUDA777_POLICY_RECIPE_SELF_TEST ok roots=" << recipe_roots.size()
              << " best_source=" << best_source
              << " rank=" << recipe_best.terms.size()
              << " density=" << density(recipe_best) << '\n';
  }

  std::cout << "CUDA777_POLICY_SELF_TEST ok epochs=67 leader=" << role_counts[0]
            << " originals=" << role_counts[1] << " descendants=" << role_counts[2]
            << " root_counts=" << root_counts[1] << ',' << root_counts[2] << ','
            << root_counts[3] << ',' << root_counts[4]
            << " adaptive_counts=" << adaptive_counts[1] << ',' << adaptive_counts[2]
            << ',' << adaptive_counts[3] << ',' << adaptive_counts[4]
            << " adaptive_reward=" << original_reward_points(adaptive.original_stats[3])
            << " adaptive_roles=" << adaptive_role_counts[0] << ','
            << adaptive_role_counts[1] << ',' << adaptive_role_counts[2]
            << " descendant_roles=" << descendant_role_counts[0] << ','
            << descendant_role_counts[1] << ',' << descendant_role_counts[2]
            << " max_gap=" << kMaxOriginalGap << " role_gap=" << kMaxRoleGap
            << " source_replace=1"
            << " min_distance=12 eviction_score=" << admission.score << '\n';
  return 0;
}

void usage(const char* program) {
  std::cout
      << "Usage:\n"
      << "  " << program << " --self-test SEED\n"
      << "  " << program << " --policy-self-test [SEED ...]\n"
      << "  " << program << " --seed PATH [--seed PATH ...] --out PATH [options]\n\n"
      << "Options:\n"
      << "  --status PATH          atomic heartbeat/status file (default OUT.status)\n"
      << "  --archive-dir PATH     exact novel-door archive (default OUT.archive)\n"
      << "  --seconds N            campaign wall limit, checked at epoch boundaries (7200)\n"
      << "  --epochs N             optional finite epoch limit (0 = wall limit only)\n"
      << "  --groups N             one-warp cooperative schemes (8192)\n"
      << "  --steps N              steps per dispatch (20000)\n"
      << "  --dispatches N         dispatches per seed epoch (5)\n"
      << "  --margin N             rank-debt margin (4)\n"
      << "  --mode scan|hash|alternate  cooperative partner mode (scan)\n"
      << "  --max-doors N          in-memory restart-door cap (32)\n"
      << "  --door-min-distance N  descendant support-distance floor (12)\n"
      << "  --harvest-top-k N      gate/archive/admit top improving groups, 1..8 (8)\n"
      << "  --stop-rank N          stop after an exact rank at most N (246)\n"
      << "  --run-seed N           reproducible host diversification seed (random)\n"
      << "  --device N             CUDA device index (0)\n";
}

struct Config {
  std::vector<std::string> seed_paths;
  std::string out_path;
  std::string status_path;
  std::string archive_dir;
  long long seconds = 7200;
  long long epochs = 0;
  int groups = 8192;
  int steps = 20000;
  int dispatches = 5;
  int margin = 4;
  int max_doors = 32;
  int door_min_distance = 12;
  int harvest_top_k = kDefaultHarvestTopK;
  int stop_rank = 246;
  int device = 0;
  uint64_t run_seed = 0;
  bool run_seed_set = false;
  std::string mode = "scan";
};

std::filesystem::path path_identity(const std::string& text) {
  std::error_code error;
  std::filesystem::path absolute = std::filesystem::absolute(text, error);
  if (error) return std::filesystem::path(text).lexically_normal();
  std::filesystem::path canonical = std::filesystem::weakly_canonical(absolute, error);
  if (!error) return canonical;
  return absolute.lexically_normal();
}

bool same_path(const std::string& left, const std::string& right) {
  std::error_code error;
  if (std::filesystem::equivalent(left, right, error) && !error) return true;
  return path_identity(left) == path_identity(right);
}

Config parse_config(int argc, char** argv) {
  Config config;
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    auto value = [&](const std::string& option) -> std::string {
      if (i + 1 >= argc) throw std::runtime_error(option + " requires a value");
      return argv[++i];
    };
    if (arg == "--seed") config.seed_paths.push_back(value(arg));
    else if (arg == "--out") config.out_path = value(arg);
    else if (arg == "--status") config.status_path = value(arg);
    else if (arg == "--archive-dir") config.archive_dir = value(arg);
    else if (arg == "--seconds") config.seconds = parse_i64(value(arg), arg);
    else if (arg == "--epochs") config.epochs = parse_i64(value(arg), arg);
    else if (arg == "--groups") config.groups = parse_int(value(arg), arg);
    else if (arg == "--steps") config.steps = parse_int(value(arg), arg);
    else if (arg == "--dispatches") config.dispatches = parse_int(value(arg), arg);
    else if (arg == "--margin") config.margin = parse_int(value(arg), arg);
    else if (arg == "--max-doors") config.max_doors = parse_int(value(arg), arg);
    else if (arg == "--door-min-distance") config.door_min_distance = parse_int(value(arg), arg);
    else if (arg == "--harvest-top-k") config.harvest_top_k = parse_int(value(arg), arg);
    else if (arg == "--stop-rank") config.stop_rank = parse_int(value(arg), arg);
    else if (arg == "--run-seed") {
      config.run_seed = parse_u64(value(arg), arg);
      config.run_seed_set = true;
    }
    else if (arg == "--device") config.device = parse_int(value(arg), arg);
    else if (arg == "--mode") config.mode = value(arg);
    else if (arg == "--help" || arg == "-h") {
      usage(argv[0]);
      std::exit(0);
    } else {
      throw std::runtime_error("unknown option `" + arg + "`");
    }
  }

  if (config.seed_paths.empty()) throw std::runtime_error("at least one --seed is required");
  if (config.out_path.empty()) throw std::runtime_error("--out is required");
  if (config.status_path.empty()) config.status_path = config.out_path + ".status";
  if (config.archive_dir.empty()) config.archive_dir = config.out_path + ".archive";
  if (same_path(config.out_path, config.status_path)) {
    throw std::runtime_error("--out and --status must name different paths");
  }
  if (same_path(config.out_path, config.archive_dir) ||
      same_path(config.status_path, config.archive_dir)) {
    throw std::runtime_error("--archive-dir must differ from --out and --status");
  }
  if (config.seconds <= 0 && config.epochs <= 0) {
    throw std::runtime_error("--seconds or --epochs must be positive");
  }
  if (config.seconds > LLONG_MAX / 1000) {
    throw std::runtime_error("--seconds is too large");
  }
  if (config.harvest_top_k < 1 || config.harvest_top_k > kMaxHarvestTopK) {
    throw std::runtime_error("--harvest-top-k must be between 1 and 8");
  }
  if (config.epochs < 0 || config.groups < 1 || config.groups > 262144 ||
      config.steps < 1 || config.dispatches < 1 || config.margin < 0 ||
      config.max_doors < 1 || config.door_min_distance < 0 || config.device < 0) {
    throw std::runtime_error("invalid nonpositive or out-of-range campaign option");
  }
  if (config.steps > 100000000 || config.dispatches > 1000 ||
      static_cast<long long>(config.steps) * config.dispatches > INT_MAX) {
    throw std::runtime_error("steps x dispatches exceeds the i32 worker-counter limit");
  }
  if (config.mode != "alternate" && config.mode != "scan" && config.mode != "hash") {
    throw std::runtime_error("--mode must be alternate, scan, or hash");
  }
  return config;
}

volatile sig_atomic_t stop_requested = 0;

[[maybe_unused]] void request_stop(int) { stop_requested = 1; }

struct GroupHarvestSummary {
  unsigned long long completed_groups = 0;
  unsigned long long improved_groups = 0;
  unsigned long long capture_groups = 0;
  unsigned long long capture_sum = 0;
};

struct GroupHarvestEndpoint {
  int group = -1;
  int rank = 0;
  int density = 0;
};

struct GroupHarvestSelection {
  bool has_absolute = false;
  GroupHarvestEndpoint absolute;
  std::vector<GroupHarvestEndpoint> selected;
};

struct CandidateHarvestSummary {
  unsigned long long selected_groups = 0;
  unsigned long long downloaded_schemes = 0;
  unsigned long long exact_schemes = 0;
  unsigned long long novel_schemes = 0;
  unsigned long long auxiliary_door_admissions = 0;
  unsigned long long transfer_bytes = 0;
};

void require_group_state_buffer(const std::vector<int32_t>& states, int groups) {
  if (groups < 0 ||
      states.size() < static_cast<size_t>(groups) * kGroupStateWords) {
    throw std::invalid_argument("group harvest state buffer is too short");
  }
}

bool group_harvest_endpoint_better(const GroupHarvestEndpoint& left,
                                   const GroupHarvestEndpoint& right) {
  return std::tie(left.rank, left.density, left.group) <
         std::tie(right.rank, right.density, right.group);
}

// Select a bounded sorted prefix in one pass over the downloaded fixed-size
// state records. Group ID is the final tie break, matching the old ascending
// winner scan exactly. The host retains at most eight endpoints rather than
// sorting or allocating in proportion to --groups. Scheme identity is checked
// later, after these selected slots are downloaded and canonicalized; the
// compact state record intentionally has no fingerprint.
GroupHarvestSelection select_group_harvest_endpoints(
    const std::vector<int32_t>& states, int groups, int launch_rank,
    int launch_density, int top_k) {
  if (top_k < 1 || top_k > kMaxHarvestTopK) {
    throw std::invalid_argument("group harvest top-K is outside 1..8");
  }
  require_group_state_buffer(states, groups);
  GroupHarvestSelection selection;
  selection.selected.reserve(static_cast<size_t>(top_k));
  for (int group = 0; group < groups; ++group) {
    const size_t base = static_cast<size_t>(group) * kGroupStateWords;
    if (states.at(base + kGroupStateCompletedOffset) != 1) continue;
    const GroupHarvestEndpoint endpoint{group, states[base + 1], states[base + 3]};
    if (endpoint.rank <= 0 || endpoint.rank > kCap) continue;
    if (!selection.has_absolute ||
        group_harvest_endpoint_better(endpoint, selection.absolute)) {
      selection.has_absolute = true;
      selection.absolute = endpoint;
    }
    const bool improves = endpoint.rank < launch_rank ||
                          (endpoint.rank == launch_rank &&
                           endpoint.density < launch_density);
    if (!improves) continue;
    const auto position = std::lower_bound(
        selection.selected.begin(), selection.selected.end(), endpoint,
        group_harvest_endpoint_better);
    selection.selected.insert(position, endpoint);
    if (selection.selected.size() > static_cast<size_t>(top_k)) {
      selection.selected.pop_back();
    }
  }
  return selection;
}

unsigned long long group_endpoint_transfer_bytes(
    const GroupHarvestEndpoint& endpoint) {
  if (endpoint.rank <= 0 || endpoint.rank > kCap) {
    throw std::invalid_argument("group harvest endpoint rank is outside capacity");
  }
  return 3ULL * static_cast<unsigned long long>(endpoint.rank) * sizeof(int64_t);
}

// Summarize the fixed eight-i32 record published by every cooperative group.
// These counts are telemetry only; select_group_harvest_endpoints owns the
// deterministic candidate ordering, and the exhaustive host gate remains the
// authority for archive and admission.
GroupHarvestSummary summarize_group_harvest(const std::vector<int32_t>& states,
                                            int groups, int launch_rank,
                                            int launch_density) {
  require_group_state_buffer(states, groups);

  GroupHarvestSummary summary;
  for (int group = 0; group < groups; ++group) {
    const size_t base = static_cast<size_t>(group) * kGroupStateWords;
    // Keep the record-boundary read checked even though the aggregate buffer
    // guard above is authoritative. This makes a future host/kernel layout
    // mismatch fail closed and avoids GCC treating the deliberate short-buffer
    // self-test as a reachable unchecked read.
    if (states.at(base + kGroupStateCompletedOffset) != 1) continue;
    ++summary.completed_groups;

    const int rank = states[base + 1];
    const int den = states[base + 3];
    if (rank > 0 && rank <= kCap &&
        (rank < launch_rank || (rank == launch_rank && den < launch_density))) {
      ++summary.improved_groups;
    }

    const int captures = states[base + 6];
    if (captures > 0) {
      ++summary.capture_groups;
      summary.capture_sum += static_cast<unsigned int>(captures);
    }
  }
  return summary;
}

void accumulate_group_harvest(GroupHarvestSummary& total,
                              const GroupHarvestSummary& epoch) {
  total.completed_groups += epoch.completed_groups;
  total.improved_groups += epoch.improved_groups;
  total.capture_groups += epoch.capture_groups;
  total.capture_sum += epoch.capture_sum;
}

void accumulate_candidate_harvest(CandidateHarvestSummary& total,
                                  const CandidateHarvestSummary& epoch) {
  total.selected_groups += epoch.selected_groups;
  total.downloaded_schemes += epoch.downloaded_schemes;
  total.exact_schemes += epoch.exact_schemes;
  total.novel_schemes += epoch.novel_schemes;
  total.auxiliary_door_admissions += epoch.auxiliary_door_admissions;
  total.transfer_bytes += epoch.transfer_bytes;
}

struct PolicyTelemetry {
  std::array<unsigned long long, 3> role_epochs{};
  unsigned long long adaptive_role_slots = 0;
  std::array<RoleStats, 3> role_stats{};
  unsigned long long original_slots = 0;
  std::vector<OriginalSourceStats> original_stats;
  LaunchRole selected_role = LaunchRole::kLeader;
  size_t selected_source = 0;
  int selected_mode = -1;
  int epoch_door_action = 0;
  int epoch_door_score = -1;
  bool epoch_door_source_replacement = false;
  bool has_selection = false;
  int harvest_top_k = kDefaultHarvestTopK;
  GroupHarvestSummary harvest_epoch;
  GroupHarvestSummary harvest_total;
  CandidateHarvestSummary candidate_harvest_epoch;
  CandidateHarvestSummary candidate_harvest_total;
};

void begin_group_harvest_epoch(PolicyTelemetry& policy) {
  policy.harvest_epoch = {};
  policy.candidate_harvest_epoch = {};
}

void complete_group_harvest_epoch(PolicyTelemetry& policy,
                                  const std::vector<int32_t>& states, int groups,
                                  int launch_rank, int launch_density) {
  policy.harvest_epoch =
      summarize_group_harvest(states, groups, launch_rank, launch_density);
  accumulate_group_harvest(policy.harvest_total, policy.harvest_epoch);
}

void complete_candidate_harvest_epoch(PolicyTelemetry& policy,
                                      const CandidateHarvestSummary& epoch) {
  policy.candidate_harvest_epoch = epoch;
  accumulate_candidate_harvest(policy.candidate_harvest_total, epoch);
}

[[maybe_unused]] void sync_policy_telemetry(PolicyTelemetry& policy,
                                            const LaunchScheduler& scheduler) {
  for (size_t i = 0; i < policy.role_epochs.size(); ++i) {
    policy.role_epochs[i] = scheduler.role_stats[i].epochs;
  }
  policy.adaptive_role_slots = scheduler.adaptive_role_slots;
  policy.role_stats = scheduler.role_stats;
  policy.original_slots = scheduler.original_slots;
  policy.original_stats = scheduler.original_stats;
}

[[maybe_unused]] std::string status_body(const std::string& phase, long long epoch,
                                         int dispatch, long long elapsed_ms,
                                         const Scheme& best, size_t doors, uint64_t run_seed,
                                         unsigned long long attempts,
                                         unsigned long long partners,
                                         long long candidates, long long exact_rejects,
                                         const std::string& detail = "",
                                         const PolicyTelemetry* policy = nullptr) {
  std::ostringstream out;
  out << "schema=1\nengine=cuda-simdgroup-777\nphase=" << phase
      << "\nepoch=" << epoch << "\ndispatch=" << dispatch
      << "\nelapsed_ms=" << elapsed_ms << "\nrank=" << best.terms.size()
      << "\ndensity=" << density(best) << "\ndoors=" << doors
      << "\nrun_seed=" << run_seed
      << "\nattempts=" << attempts << "\npartners=" << partners
      << "\ncandidates=" << candidates << "\nexact_rejects=" << exact_rejects << '\n';
  if (policy != nullptr) {
    out << "policy_leader_epochs=" << policy->role_epochs[0]
        << "\npolicy_original_epochs=" << policy->role_epochs[1]
        << "\npolicy_descendant_epochs=" << policy->role_epochs[2]
        << "\npolicy_adaptive_role_slots=" << policy->adaptive_role_slots
        << "\npolicy_role_explore_every=" << kRoleExploreEvery
        << "\nrole_stats=" << role_stats_text(policy->role_stats)
        << "\npolicy_original_slots=" << policy->original_slots
        << "\npolicy_original_explore_every=" << kOriginalExploreEvery
        << "\noriginal_source_stats=" << original_source_stats_text(policy->original_stats)
        << "\nselected_role="
        << (policy->has_selection ? launch_role_name(policy->selected_role) : "none")
        << "\nselected_source=";
    if (policy->has_selection) {
      out << policy->selected_source;
    } else {
      out << -1;
    }
    out << "\nselected_kernel=";
    if (policy->selected_mode == 0) {
      out << "scan";
    } else if (policy->selected_mode == 1) {
      out << "hash";
    } else {
      out << "none";
    }
    out << "\nepoch_door_action=" << policy->epoch_door_action
        << "\nepoch_door_score=" << policy->epoch_door_score
        << "\nepoch_door_source_replacement="
        << (policy->epoch_door_source_replacement ? 1 : 0)
        << "\nharvest_top_k=" << policy->harvest_top_k
        << "\nharvest_epoch_completed_groups="
        << policy->harvest_epoch.completed_groups
        << "\nharvest_epoch_improved_groups="
        << policy->harvest_epoch.improved_groups
        << "\nharvest_epoch_capture_groups="
        << policy->harvest_epoch.capture_groups
        << "\nharvest_epoch_capture_sum=" << policy->harvest_epoch.capture_sum
        << "\nharvest_total_completed_groups="
        << policy->harvest_total.completed_groups
        << "\nharvest_total_improved_groups="
        << policy->harvest_total.improved_groups
        << "\nharvest_total_capture_groups="
        << policy->harvest_total.capture_groups
        << "\nharvest_total_capture_sum=" << policy->harvest_total.capture_sum
        << "\nharvest_epoch_selected_groups="
        << policy->candidate_harvest_epoch.selected_groups
        << "\nharvest_epoch_downloaded_schemes="
        << policy->candidate_harvest_epoch.downloaded_schemes
        << "\nharvest_epoch_exact_schemes="
        << policy->candidate_harvest_epoch.exact_schemes
        << "\nharvest_epoch_novel_schemes="
        << policy->candidate_harvest_epoch.novel_schemes
        << "\nharvest_epoch_auxiliary_door_admissions="
        << policy->candidate_harvest_epoch.auxiliary_door_admissions
        << "\nharvest_epoch_transfer_bytes="
        << policy->candidate_harvest_epoch.transfer_bytes
        << "\nharvest_total_selected_groups="
        << policy->candidate_harvest_total.selected_groups
        << "\nharvest_total_downloaded_schemes="
        << policy->candidate_harvest_total.downloaded_schemes
        << "\nharvest_total_exact_schemes="
        << policy->candidate_harvest_total.exact_schemes
        << "\nharvest_total_novel_schemes="
        << policy->candidate_harvest_total.novel_schemes
        << "\nharvest_total_auxiliary_door_admissions="
        << policy->candidate_harvest_total.auxiliary_door_admissions
        << "\nharvest_total_transfer_bytes="
        << policy->candidate_harvest_total.transfer_bytes << '\n';
  }
  if (!detail.empty()) out << "detail=" << detail << '\n';
  return out.str();
}

int policy_status_self_test() {
  const Scheme best = policy_test_scheme({1, 2, 3});
  PolicyTelemetry policy;
  policy.role_epochs = {18, 31, 18};
  policy.adaptive_role_slots = 50;
  policy.role_stats[0] = {18, 0, 0, 45, true};
  policy.role_stats[1] = {31, 3, 1, 49, true};
  policy.role_stats[2] = {18, 2, 0, 47, true};
  policy.original_slots = 17;
  policy.original_stats.resize(3);
  policy.original_stats[1] = {4, 0, 0, 12, true};
  policy.original_stats[2] = {13, 3, 1, 16, true};
  policy.selected_role = LaunchRole::kDescendant;
  policy.selected_source = 7;
  policy.selected_mode = 1;
  policy.epoch_door_action = 4;
  policy.epoch_door_score = 19;
  policy.epoch_door_source_replacement = true;
  policy.has_selection = true;
  policy.harvest_top_k = 8;
  policy.harvest_epoch = {8, 3, 4, 11};
  policy.harvest_total = {4096, 37, 41, 123};
  policy.candidate_harvest_epoch = {8, 8, 8, 5, 3, 47424};
  policy.candidate_harvest_total = {64, 64, 64, 17, 9, 379392};
  const std::string body = status_body("epoch", 66, 5, 1234, best, 16, 99, 100, 10,
                                       4, 0, "exact-novel", &policy);
  const std::array<std::string, 36> required = {
      "policy_leader_epochs=18\n", "policy_original_epochs=31\n",
      "policy_descendant_epochs=18\n", "policy_adaptive_role_slots=50\n",
      "policy_role_explore_every=4\n",
      "role_stats=leader:v18,n0,b0,p0,lastA45;"
      "original:v31,n3,b1,p11,lastA49;descendant:v18,n2,b0,p2,lastA47\n",
      "selected_role=descendant\n",
      "policy_original_slots=17\n", "policy_original_explore_every=4\n",
      "original_source_stats=0:v0,n0,b0,p0,last-;1:v4,n0,b0,p0,last12;"
      "2:v13,n3,b1,p11,last16\n",
      "selected_source=7\n", "selected_kernel=hash\n", "epoch_door_action=4\n",
      "epoch_door_score=19\n", "epoch_door_source_replacement=1\n",
      "harvest_top_k=8\n",
      "harvest_epoch_completed_groups=8\n",
      "harvest_epoch_improved_groups=3\n",
      "harvest_epoch_capture_groups=4\n", "harvest_epoch_capture_sum=11\n",
      "harvest_total_completed_groups=4096\n",
      "harvest_total_improved_groups=37\n",
      "harvest_total_capture_groups=41\n", "harvest_total_capture_sum=123\n",
      "harvest_epoch_selected_groups=8\n",
      "harvest_epoch_downloaded_schemes=8\n",
      "harvest_epoch_exact_schemes=8\n", "harvest_epoch_novel_schemes=5\n",
      "harvest_epoch_auxiliary_door_admissions=3\n",
      "harvest_epoch_transfer_bytes=47424\n",
      "harvest_total_selected_groups=64\n",
      "harvest_total_downloaded_schemes=64\n",
      "harvest_total_exact_schemes=64\n", "harvest_total_novel_schemes=17\n",
      "harvest_total_auxiliary_door_admissions=9\n",
      "harvest_total_transfer_bytes=379392\n"};
  for (const auto& field : required) {
    if (body.find(field) == std::string::npos) {
      throw std::runtime_error("policy status telemetry field is missing");
    }
  }
  return 0;
}

int group_harvest_self_test() {
  if (Config{}.harvest_top_k != kDefaultHarvestTopK ||
      kDefaultHarvestTopK != kMaxHarvestTopK) {
    throw std::runtime_error("group harvest evidence-backed default is not top-K=8");
  }

  std::vector<int32_t> states(6 * kGroupStateWords, 0);
  auto publish = [&](int group, int rank, int den, int captures, int completed) {
    const size_t base = static_cast<size_t>(group) * kGroupStateWords;
    states[base + 1] = rank;
    states[base + 3] = den;
    states[base + 6] = captures;
    states[base + kGroupStateCompletedOffset] = completed;
  };
  publish(0, 247, 3094, 0, 1);  // Completed, but tied and never captured.
  publish(1, 247, 3093, 2, 1);  // Same-rank density improvement.
  publish(2, 246, 4000, 1, 1);  // Rank improvement dominates density.
  publish(3, 245, 1000, 7, 0);  // Incomplete records never contribute.
  publish(4, 248, 3000, 3, 1);  // Capture telemetry is independent of objective.
  publish(5, 0, 0, 4, 1);      // Invalid ranks cannot claim improvement.

  const GroupHarvestSummary epoch = summarize_group_harvest(states, 6, 247, 3094);
  if (epoch.completed_groups != 5 || epoch.improved_groups != 2 ||
      epoch.capture_groups != 4 || epoch.capture_sum != 10) {
    throw std::runtime_error("group harvest summary miscounted synthetic records");
  }

  const GroupHarvestSelection ranked =
      select_group_harvest_endpoints(states, 6, kCap, INT_MAX, 8);
  if (!ranked.has_absolute || ranked.absolute.group != 2 ||
      ranked.selected.size() != 4 || ranked.selected[0].group != 2 ||
      ranked.selected[0].rank != 246 || ranked.selected[0].density != 4000 ||
      ranked.selected[1].group != 1 || ranked.selected[2].group != 0 ||
      ranked.selected[3].group != 4) {
    throw std::runtime_error("group harvest objective ordering is wrong");
  }
  const GroupHarvestSelection selected_one =
      select_group_harvest_endpoints(states, 6, 247, 3094, 1);
  const GroupHarvestSelection selected_eight =
      select_group_harvest_endpoints(states, 6, 247, 3094, 8);
  if (!selected_one.has_absolute || selected_one.absolute.group != 2 ||
      selected_one.selected.size() != 1 || selected_one.selected[0].group != 2 ||
      selected_eight.selected.size() != 2 || selected_eight.selected[0].group != 2 ||
      selected_eight.selected[1].group != 1) {
    throw std::runtime_error("group harvest top-K prefix changed the absolute winner");
  }

  // Equal objectives retain ascending group order. Incomplete and invalid-rank
  // records cannot displace a valid endpoint, and neutral endpoints are not
  // transferred merely because K has spare capacity.
  std::vector<int32_t> tie_states(7 * kGroupStateWords, 0);
  auto publish_tie = [&](int group, int rank, int den, int completed) {
    const size_t base = static_cast<size_t>(group) * kGroupStateWords;
    tie_states[base + 1] = rank;
    tie_states[base + 3] = den;
    tie_states[base + kGroupStateCompletedOffset] = completed;
  };
  publish_tie(0, 247, 3093, 1);
  publish_tie(1, 246, 4000, 1);
  publish_tie(2, 246, 3999, 1);
  publish_tie(3, 246, 4000, 1);
  publish_tie(4, 245, 1, 0);
  publish_tie(5, 0, -1, 1);
  publish_tie(6, 247, 3094, 1);
  const GroupHarvestSelection tie_selected =
      select_group_harvest_endpoints(tie_states, 7, 247, 3094, 8);
  const std::array<int, 4> expected_groups = {2, 1, 3, 0};
  if (!tie_selected.has_absolute || tie_selected.absolute.group != 2 ||
      tie_selected.selected.size() != expected_groups.size()) {
    throw std::runtime_error("group harvest selected the wrong top-K size");
  }
  for (size_t i = 0; i < expected_groups.size(); ++i) {
    if (tie_selected.selected[i].group != expected_groups[i]) {
      throw std::runtime_error("group harvest tie break is not deterministic");
    }
  }
  if (group_endpoint_transfer_bytes({0, kCap, 0}) * kMaxHarvestTopK != 69120ULL) {
    throw std::runtime_error("group harvest transfer bound changed unexpectedly");
  }
  for (const int invalid_top_k : {0, kMaxHarvestTopK + 1}) {
    bool rejected = false;
    try {
      (void)select_group_harvest_endpoints(states, 6, 247, 3094, invalid_top_k);
    } catch (const std::invalid_argument&) {
      rejected = true;
    }
    if (!rejected) throw std::runtime_error("group harvest accepted invalid top-K");
  }

  auto require_status_value = [](const std::string& body, const std::string& field,
                                 unsigned long long expected) {
    const std::string needle = field + "=" + std::to_string(expected) + "\n";
    if (body.find(needle) == std::string::npos) {
      throw std::runtime_error("group harvest lifecycle status field is wrong: " + field);
    }
  };
  auto require_status_summary = [&](const std::string& body,
                                    const GroupHarvestSummary& expected_epoch,
                                    const GroupHarvestSummary& expected_total) {
    require_status_value(body, "harvest_epoch_completed_groups",
                         expected_epoch.completed_groups);
    require_status_value(body, "harvest_epoch_improved_groups",
                         expected_epoch.improved_groups);
    require_status_value(body, "harvest_epoch_capture_groups",
                         expected_epoch.capture_groups);
    require_status_value(body, "harvest_epoch_capture_sum", expected_epoch.capture_sum);
    require_status_value(body, "harvest_total_completed_groups",
                         expected_total.completed_groups);
    require_status_value(body, "harvest_total_improved_groups",
                         expected_total.improved_groups);
    require_status_value(body, "harvest_total_capture_groups",
                         expected_total.capture_groups);
    require_status_value(body, "harvest_total_capture_sum", expected_total.capture_sum);
  };
  auto require_candidate_summary = [&](const std::string& body,
                                       const CandidateHarvestSummary& expected_epoch,
                                       const CandidateHarvestSummary& expected_total) {
    require_status_value(body, "harvest_epoch_selected_groups",
                         expected_epoch.selected_groups);
    require_status_value(body, "harvest_epoch_downloaded_schemes",
                         expected_epoch.downloaded_schemes);
    require_status_value(body, "harvest_epoch_exact_schemes",
                         expected_epoch.exact_schemes);
    require_status_value(body, "harvest_epoch_novel_schemes",
                         expected_epoch.novel_schemes);
    require_status_value(body, "harvest_epoch_auxiliary_door_admissions",
                         expected_epoch.auxiliary_door_admissions);
    require_status_value(body, "harvest_epoch_transfer_bytes",
                         expected_epoch.transfer_bytes);
    require_status_value(body, "harvest_total_selected_groups",
                         expected_total.selected_groups);
    require_status_value(body, "harvest_total_downloaded_schemes",
                         expected_total.downloaded_schemes);
    require_status_value(body, "harvest_total_exact_schemes",
                         expected_total.exact_schemes);
    require_status_value(body, "harvest_total_novel_schemes",
                         expected_total.novel_schemes);
    require_status_value(body, "harvest_total_auxiliary_door_admissions",
                         expected_total.auxiliary_door_admissions);
    require_status_value(body, "harvest_total_transfer_bytes",
                         expected_total.transfer_bytes);
  };

  PolicyTelemetry lifecycle;
  Scheme best;
  const GroupHarvestSummary zero;
  const CandidateHarvestSummary candidate_zero;
  const CandidateHarvestSummary candidate_epoch{2, 2, 2, 1, 1, 11832};
  const std::string ready =
      status_body("ready", 0, 0, 0, best, 1, 7, 0, 0, 0, 0, "", &lifecycle);
  require_status_summary(ready, zero, zero);
  require_candidate_summary(ready, candidate_zero, candidate_zero);

  complete_group_harvest_epoch(lifecycle, states, 6, 247, 3094);
  complete_candidate_harvest_epoch(lifecycle, candidate_epoch);
  const std::string first_epoch =
      status_body("epoch", 0, 1, 1, best, 1, 7, 0, 0, 0, 0, "", &lifecycle);
  require_status_summary(first_epoch, epoch, epoch);
  require_candidate_summary(first_epoch, candidate_epoch, candidate_epoch);

  begin_group_harvest_epoch(lifecycle);
  const std::string next_dispatch =
      status_body("dispatch", 1, 0, 2, best, 1, 7, 0, 0, 0, 0, "", &lifecycle);
  require_status_summary(next_dispatch, zero, epoch);
  require_candidate_summary(next_dispatch, candidate_zero, candidate_epoch);
  if (next_dispatch.find("phase=dispatch\n") == std::string::npos ||
      next_dispatch.find("dispatch=0\n") == std::string::npos) {
    throw std::runtime_error("group harvest lifecycle did not publish dispatch zero");
  }

  complete_group_harvest_epoch(lifecycle, states, 6, 247, 3094);
  complete_candidate_harvest_epoch(lifecycle, candidate_epoch);
  const GroupHarvestSummary twice{10, 4, 8, 20};
  const CandidateHarvestSummary candidate_twice{4, 4, 4, 2, 2, 23664};
  const std::string done =
      status_body("done", 2, 0, 3, best, 1, 7, 0, 0, 0, 0, "", &lifecycle);
  require_status_summary(done, epoch, twice);
  require_candidate_summary(done, candidate_epoch, candidate_twice);
  if (lifecycle.harvest_total.completed_groups != twice.completed_groups ||
      lifecycle.harvest_total.improved_groups != twice.improved_groups ||
      lifecycle.harvest_total.capture_groups != twice.capture_groups ||
      lifecycle.harvest_total.capture_sum != twice.capture_sum) {
    throw std::runtime_error("group harvest cumulative summary did not add once per epoch");
  }
  if (lifecycle.candidate_harvest_total.selected_groups !=
          candidate_twice.selected_groups ||
      lifecycle.candidate_harvest_total.downloaded_schemes !=
          candidate_twice.downloaded_schemes ||
      lifecycle.candidate_harvest_total.exact_schemes !=
          candidate_twice.exact_schemes ||
      lifecycle.candidate_harvest_total.novel_schemes !=
          candidate_twice.novel_schemes ||
      lifecycle.candidate_harvest_total.auxiliary_door_admissions !=
          candidate_twice.auxiliary_door_admissions ||
      lifecycle.candidate_harvest_total.transfer_bytes !=
          candidate_twice.transfer_bytes) {
    throw std::runtime_error("candidate harvest cumulative summary did not add once per epoch");
  }

  bool short_buffer_rejected = false;
  try {
    (void)summarize_group_harvest(
        std::vector<int32_t>(kGroupStateWords - 1, 0), 1, 247, 3094);
  } catch (const std::invalid_argument&) {
    short_buffer_rejected = true;
  }
  if (!short_buffer_rejected) {
    throw std::runtime_error("group harvest summary accepted a short state buffer");
  }

  std::vector<int32_t> boundary_state(kGroupStateWords, 0);
  boundary_state[1] = 247;
  boundary_state[3] = 3094;
  boundary_state[kGroupStateCompletedOffset] = 1;
  const GroupHarvestSummary boundary =
      summarize_group_harvest(boundary_state, 1, 247, 3094);
  if (boundary.completed_groups != 1 || boundary.improved_groups != 0) {
    throw std::runtime_error("group harvest rejected one complete state record");
  }

  std::cout << "CUDA777_HARVEST_SELF_TEST ok completed=" << epoch.completed_groups
            << " improved=" << epoch.improved_groups
            << " capture_groups=" << epoch.capture_groups
            << " capture_sum=" << epoch.capture_sum << '\n';
  return 0;
}

#ifndef METAFLIP_HOST_ONLY_TEST

void cuda_check(cudaError_t result, const char* operation) {
  if (result == cudaSuccess) return;
  std::string prefix = result == cudaErrorMemoryAllocation ? "CUDA_OOM " : "CUDA_ERROR ";
  throw std::runtime_error(prefix + operation + ": " + cudaGetErrorString(result));
}

struct DeviceBuffers {
  int64_t* work_u = nullptr;
  int64_t* work_v = nullptr;
  int64_t* work_w = nullptr;
  int64_t* best_u = nullptr;
  int64_t* best_v = nullptr;
  int64_t* best_w = nullptr;
  int32_t* state = nullptr;
  int64_t* seed_u = nullptr;
  int64_t* seed_v = nullptr;
  int64_t* seed_w = nullptr;
  int32_t* params = nullptr;

  ~DeviceBuffers() {
    cudaFree(work_u);
    cudaFree(work_v);
    cudaFree(work_w);
    cudaFree(best_u);
    cudaFree(best_v);
    cudaFree(best_w);
    cudaFree(state);
    cudaFree(seed_u);
    cudaFree(seed_v);
    cudaFree(seed_w);
    cudaFree(params);
  }
};

void allocate(void** pointer, size_t bytes, const char* label) {
  const cudaError_t result = cudaMalloc(pointer, bytes);
  cuda_check(result, label);
}

int run_campaign(const Config& config) {
  std::vector<Scheme> original_roots;
  std::vector<Scheme> descendants;
  std::set<std::string> known;
  Scheme resumed_checkpoint;
  bool has_resumed_checkpoint = false;
  for (const auto& path : config.seed_paths) {
    Scheme seed = load_scheme(path);
    const VerifyResult verified = verify_exact(seed);
    if (!verified.exact) throw std::runtime_error(path + ": inexact seed: " + verified.reason);
    const std::string key = canonical_key(seed);
    if (known.insert(key).second) original_roots.push_back(std::move(seed));
  }
  if (original_roots.empty()) throw std::runtime_error("all supplied seeds were duplicates");
  if (static_cast<int>(original_roots.size()) > config.max_doors) {
    throw std::runtime_error("--max-doors is smaller than the supplied distinct seed count");
  }
  const size_t descendant_capacity =
      static_cast<size_t>(config.max_doors) - original_roots.size();

  // A restart must never replace a previously found lower-rank checkpoint
  // with its command-line seed.  It is the scheduled leader regardless of
  // whether max-min admission would retain it as a descendant door.
  if (std::filesystem::exists(config.out_path)) {
    Scheme resumed = load_scheme(config.out_path);
    const VerifyResult verified = verify_exact(resumed);
    if (!verified.exact) {
      throw std::runtime_error(config.out_path + ": refusing to overwrite inexact checkpoint: " +
                               verified.reason);
    }
    resumed_checkpoint = resumed;
    has_resumed_checkpoint = true;
    const std::string key = canonical_key(resumed);
    known.insert(key);
  }

  // Preserve an exact checkpoint on objective ties.  A restart may replace it
  // only with a strictly better seed or later device result.
  Scheme global_best = has_resumed_checkpoint ? resumed_checkpoint : original_roots[0];
  improve_objective(global_best, original_roots);

  // Recover every exact artifact banked before a spot interruption, but admit
  // only max-min-diverse descendants as live restart doors.  Structural
  // farthest-first selection dominates path order; canonical tie breaks and
  // deterministic ascending-slot eviction preserve --run-seed replay.
  std::vector<Scheme> replay_candidates;
  if (std::filesystem::exists(config.archive_dir)) {
    std::vector<std::filesystem::path> archived_paths;
    for (const auto& entry : std::filesystem::directory_iterator(config.archive_dir)) {
      if (entry.is_regular_file() && entry.path().extension() == ".txt") {
        archived_paths.push_back(entry.path());
      }
    }
    std::sort(archived_paths.begin(), archived_paths.end());
    for (const auto& path : archived_paths) {
      Scheme archived = load_scheme(path.string());
      const VerifyResult verified = verify_exact(archived);
      if (!verified.exact) {
        throw std::runtime_error(path.string() + ": inexact restart archive: " +
                                 verified.reason);
      }
      const std::string key = canonical_key(archived);
      if (known.insert(key).second) {
        if (objective_better(archived, global_best)) global_best = archived;
        replay_candidates.push_back(std::move(archived));
      }
    }
  }
  rebuild_descendants_diverse(original_roots, std::move(replay_candidates), descendants,
                              descendant_capacity, config.door_min_distance);
  write_scheme_atomic(config.out_path, global_best);
  std::filesystem::create_directories(config.archive_dir);

  cuda_check(cudaSetDevice(config.device), "cudaSetDevice");
  cudaDeviceProp properties{};
  cuda_check(cudaGetDeviceProperties(&properties, config.device), "cudaGetDeviceProperties");
  cudaFuncAttributes scan_attributes{};
  cudaFuncAttributes hash_attributes{};
  cuda_check(cudaFuncGetAttributes(&scan_attributes, flipwalk_simd_scan),
             "cudaFuncGetAttributes scan");
  cuda_check(cudaFuncGetAttributes(&hash_attributes, flipwalk_simd_hash),
             "cudaFuncGetAttributes hash");
  if (properties.warpSize != 32 || scan_attributes.maxThreadsPerBlock < 32 ||
      hash_attributes.maxThreadsPerBlock < 32) {
    throw std::runtime_error("CUDA device cannot run the relay's fixed 32-lane groups");
  }
  if (scan_attributes.sharedSizeBytes != kScanSharedBytes ||
      hash_attributes.sharedSizeBytes != kHashSharedBytes) {
    throw std::runtime_error(
        "CUDA specialization resource mismatch: expected scan/hash shared bytes " +
        std::to_string(kScanSharedBytes) + "/" + std::to_string(kHashSharedBytes) +
        ", got " + std::to_string(scan_attributes.sharedSizeBytes) + "/" +
        std::to_string(hash_attributes.sharedSizeBytes));
  }
  if (scan_attributes.sharedSizeBytes > properties.sharedMemPerBlock ||
      hash_attributes.sharedSizeBytes > properties.sharedMemPerBlock) {
    throw std::runtime_error("CUDA kernel static shared memory exceeds the device block limit");
  }
  int scan_active_blocks_per_sm = 0;
  int hash_active_blocks_per_sm = 0;
  cuda_check(cudaOccupancyMaxActiveBlocksPerMultiprocessor(
                 &scan_active_blocks_per_sm, flipwalk_simd_scan, 32, 0),
             "cudaOccupancyMaxActiveBlocksPerMultiprocessor scan");
  cuda_check(cudaOccupancyMaxActiveBlocksPerMultiprocessor(
                 &hash_active_blocks_per_sm, flipwalk_simd_hash, 32, 0),
             "cudaOccupancyMaxActiveBlocksPerMultiprocessor hash");
  if (scan_active_blocks_per_sm < 1 || hash_active_blocks_per_sm < 1) {
    throw std::runtime_error("CUDA occupancy calculation found no resident relay groups");
  }
  const int max_warps_per_sm = properties.maxThreadsPerMultiProcessor / properties.warpSize;
  const int scan_resident_groups = scan_active_blocks_per_sm * properties.multiProcessorCount;
  const int hash_resident_groups = hash_active_blocks_per_sm * properties.multiProcessorCount;
  const int scan_backlog_waves =
      (config.groups + scan_resident_groups - 1) / scan_resident_groups;
  const int hash_backlog_waves =
      (config.groups + hash_resident_groups - 1) / hash_resident_groups;

  const size_t scheme_values = static_cast<size_t>(config.groups) * kCap;
  const size_t scheme_bytes = scheme_values * sizeof(int64_t);
  const size_t state_values =
      static_cast<size_t>(config.groups) * kGroupStateWords;
  const size_t state_bytes = state_values * sizeof(int32_t);
  const size_t seed_bytes = static_cast<size_t>(kCap) * sizeof(int64_t);
  const size_t required = 6 * scheme_bytes + state_bytes + 3 * seed_bytes + 7 * sizeof(int32_t);
  size_t free_bytes = 0;
  size_t total_bytes = 0;
  cuda_check(cudaMemGetInfo(&free_bytes, &total_bytes), "cudaMemGetInfo");
  if (required > free_bytes - free_bytes / 5) {
    throw std::runtime_error("CUDA_OOM requested buffers need " + std::to_string(required) +
                             " bytes, above the 80% free-memory safety limit");
  }

  DeviceBuffers device;
  allocate(reinterpret_cast<void**>(&device.work_u), scheme_bytes, "cudaMalloc work_u");
  allocate(reinterpret_cast<void**>(&device.work_v), scheme_bytes, "cudaMalloc work_v");
  allocate(reinterpret_cast<void**>(&device.work_w), scheme_bytes, "cudaMalloc work_w");
  allocate(reinterpret_cast<void**>(&device.best_u), scheme_bytes, "cudaMalloc best_u");
  allocate(reinterpret_cast<void**>(&device.best_v), scheme_bytes, "cudaMalloc best_v");
  allocate(reinterpret_cast<void**>(&device.best_w), scheme_bytes, "cudaMalloc best_w");
  allocate(reinterpret_cast<void**>(&device.state), state_bytes, "cudaMalloc state");
  allocate(reinterpret_cast<void**>(&device.seed_u), seed_bytes, "cudaMalloc seed_u");
  allocate(reinterpret_cast<void**>(&device.seed_v), seed_bytes, "cudaMalloc seed_v");
  allocate(reinterpret_cast<void**>(&device.seed_w), seed_bytes, "cudaMalloc seed_w");
  allocate(reinterpret_cast<void**>(&device.params), 7 * sizeof(int32_t), "cudaMalloc params");

  uint64_t run_seed = config.run_seed;
  if (!config.run_seed_set) {
    const uint64_t clock_bits = static_cast<uint64_t>(
        std::chrono::high_resolution_clock::now().time_since_epoch().count());
    std::random_device random;
    run_seed = clock_bits ^ (static_cast<uint64_t>(getpid()) << 32) ^
               (static_cast<uint64_t>(random()) << 32) ^ random();
  }

  std::cout << "CUDA777_CONFIG device=" << properties.name << " groups=" << config.groups
            << " steps=" << config.steps << " dispatches=" << config.dispatches
            << " shared_bytes=" << hash_attributes.sharedSizeBytes
            << " registers_per_thread=" << hash_attributes.numRegs
            << " local_bytes_per_thread=" << hash_attributes.localSizeBytes
            << " active_warps_per_sm=" << hash_active_blocks_per_sm
            << " max_warps_per_sm=" << max_warps_per_sm
            << " resident_groups=" << hash_resident_groups
            << " backlog_waves=" << hash_backlog_waves
            << " scan_shared_bytes=" << scan_attributes.sharedSizeBytes
            << " scan_registers_per_thread=" << scan_attributes.numRegs
            << " scan_local_bytes_per_thread=" << scan_attributes.localSizeBytes
            << " scan_active_warps_per_sm=" << scan_active_blocks_per_sm
            << " scan_resident_groups=" << scan_resident_groups
            << " scan_backlog_waves=" << scan_backlog_waves
            << " hash_shared_bytes=" << hash_attributes.sharedSizeBytes
            << " hash_registers_per_thread=" << hash_attributes.numRegs
            << " hash_local_bytes_per_thread=" << hash_attributes.localSizeBytes
            << " hash_active_warps_per_sm=" << hash_active_blocks_per_sm
            << " hash_resident_groups=" << hash_resident_groups
            << " hash_backlog_waves=" << hash_backlog_waves
            << " buffer_bytes=" << required
            << " seeds=" << scheduled_door_count(original_roots, descendants, global_best)
            << " roots=" << original_roots.size()
            << " descendants=" << descendants.size()
            << " door_min_distance=" << config.door_min_distance
            << " harvest_top_k=" << config.harvest_top_k
            << " harvest_transfer_bound_bytes="
            << (3ULL * static_cast<unsigned long long>(kCap) * sizeof(int64_t) *
                static_cast<unsigned long long>(config.harvest_top_k))
            << " run_seed=" << run_seed << std::endl;

  std::signal(SIGINT, request_stop);
  std::signal(SIGTERM, request_stop);
  const auto started = std::chrono::steady_clock::now();
  long long epoch = 0;
  long long candidates = 0;
  long long exact_rejects = 0;
  unsigned long long aggregate_attempts = 0;
  unsigned long long aggregate_partners = 0;
  LaunchScheduler scheduler;
  PolicyTelemetry policy;
  policy.harvest_top_k = config.harvest_top_k;
  scheduler.original_stats.resize(original_roots.size());
  sync_policy_telemetry(policy, scheduler);

  write_text_atomic(config.status_path,
                    status_body("ready", 0, 0, 0, global_best,
                                scheduled_door_count(original_roots, descendants, global_best),
                                run_seed,
                                aggregate_attempts, aggregate_partners, candidates,
                                exact_rejects, properties.name, &policy));

  while (!stop_requested) {
    const long long elapsed_before = std::chrono::duration_cast<std::chrono::milliseconds>(
                                         std::chrono::steady_clock::now() - started)
                                         .count();
    if (config.epochs > 0 && epoch >= config.epochs) break;
    if (config.seconds > 0 && epoch > 0 && elapsed_before >= config.seconds * 1000) break;

    // Epoch harvest fields describe only a completed state download. Clear
    // them before launching the next epoch; cumulative fields remain additive.
    begin_group_harvest_epoch(policy);
    const LaunchChoice choice = scheduler.choose(epoch, original_roots, descendants, global_best);
    if (choice.scheme == nullptr) throw std::runtime_error("scheduler selected a null door");
    policy.selected_role = choice.role;
    policy.selected_source = choice.source_index;
    policy.has_selection = true;
    policy.epoch_door_action = 0;
    policy.epoch_door_score = -1;
    policy.epoch_door_source_replacement = false;
    sync_policy_telemetry(policy, scheduler);
    const uint64_t source_tag =
        (static_cast<uint64_t>(static_cast<int>(choice.role)) << 32) ^ choice.source_index;
    const uint64_t salt = run_seed ^ 0x9e3779b97f4a7c15ULL ^
                          (static_cast<uint64_t>(epoch + 1) * 0xbf58476d1ce4e5b9ULL) ^
                          (source_tag * 0x94d049bb133111ebULL);
    Scheme launch = permute_scheme(*choice.scheme, salt);
    const int launch_density = density(launch);
    std::vector<int64_t> seed_u(kCap, 0), seed_v(kCap, 0), seed_w(kCap, 0);
    for (size_t i = 0; i < launch.terms.size(); ++i) {
      seed_u[i] = static_cast<int64_t>(launch.terms[i].u);
      seed_v[i] = static_cast<int64_t>(launch.terms[i].v);
      seed_w[i] = static_cast<int64_t>(launch.terms[i].w);
    }
    cuda_check(cudaMemcpy(device.seed_u, seed_u.data(), seed_bytes, cudaMemcpyHostToDevice),
               "seed U upload");
    cuda_check(cudaMemcpy(device.seed_v, seed_v.data(), seed_bytes, cudaMemcpyHostToDevice),
               "seed V upload");
    cuda_check(cudaMemcpy(device.seed_w, seed_w.data(), seed_bytes, cudaMemcpyHostToDevice),
               "seed W upload");

    int mode = 0;
    if (config.mode == "hash" ||
        (config.mode == "alternate" &&
         scheduled_partner_mode(epoch, choice, scheduler) != 0)) {
      mode = 1;
    }
    policy.selected_mode = mode;
    int32_t params[7] = {static_cast<int32_t>(launch.terms.size()), kCap, config.steps, 1,
                         config.margin, launch_density, mode};
    cuda_check(cudaMemcpy(device.params, params, sizeof(params), cudaMemcpyHostToDevice),
               "parameter upload");

    const long long launch_elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                         std::chrono::steady_clock::now() - started)
                                         .count();
    write_text_atomic(config.status_path,
                      status_body("dispatch", epoch, 0, launch_elapsed, global_best,
                                  scheduled_door_count(original_roots, descendants,
                                                       global_best),
                                  run_seed, aggregate_attempts, aggregate_partners,
                                  candidates, exact_rejects, "", &policy));

    for (int dispatch = 0; dispatch < config.dispatches; ++dispatch) {
      if (mode == 0) {
        flipwalk_simd_scan<<<config.groups, 32>>>(
            device.work_u, device.work_v, device.work_w, device.best_u, device.best_v,
            device.best_w, device.state, device.seed_u, device.seed_v, device.seed_w,
            device.params);
        cuda_check(cudaGetLastError(), "flipwalk_simd_scan launch");
        cuda_check(cudaDeviceSynchronize(), "flipwalk_simd_scan synchronize");
      } else {
        flipwalk_simd_hash<<<config.groups, 32>>>(
            device.work_u, device.work_v, device.work_w, device.best_u, device.best_v,
            device.best_w, device.state, device.seed_u, device.seed_v, device.seed_w,
            device.params);
        cuda_check(cudaGetLastError(), "flipwalk_simd_hash launch");
        cuda_check(cudaDeviceSynchronize(), "flipwalk_simd_hash synchronize");
      }
      const int32_t continue_flag = 0;
      cuda_check(cudaMemcpy(device.params + 3, &continue_flag, sizeof(continue_flag),
                            cudaMemcpyHostToDevice),
                 "continuation flag upload");
      const long long elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                    std::chrono::steady_clock::now() - started)
                                    .count();
      write_text_atomic(config.status_path,
                        status_body("dispatch", epoch, dispatch + 1, elapsed, global_best,
                                    scheduled_door_count(original_roots, descendants,
                                                         global_best),
                                    run_seed, aggregate_attempts, aggregate_partners,
                                    candidates, exact_rejects, "", &policy));
      if (stop_requested) break;
    }

    std::vector<int32_t> states(state_values);
    cuda_check(cudaMemcpy(states.data(), device.state, state_bytes, cudaMemcpyDeviceToHost),
               "state download");
    unsigned long long epoch_attempts = 0;
    unsigned long long epoch_partners = 0;
    for (int group = 0; group < config.groups; ++group) {
      const size_t base = static_cast<size_t>(group) * kGroupStateWords;
      if (states.at(base + kGroupStateCompletedOffset) != 1) continue;
      epoch_attempts += static_cast<unsigned int>(states[base + 4]);
      epoch_partners += static_cast<unsigned int>(states[base + 5]);
    }
    const GroupHarvestSelection harvest_selection =
        select_group_harvest_endpoints(
            states, config.groups, static_cast<int>(launch.terms.size()),
            launch_density, config.harvest_top_k);
    if (!harvest_selection.has_absolute) {
      throw std::runtime_error("no CUDA group published a completed state");
    }
    const GroupHarvestEndpoint& absolute_endpoint = harvest_selection.absolute;
    const int best_rank = absolute_endpoint.rank;
    const int best_density = absolute_endpoint.density;
    const std::vector<GroupHarvestEndpoint>& selected_endpoints =
        harvest_selection.selected;
    complete_group_harvest_epoch(policy, states, config.groups,
                                 static_cast<int>(launch.terms.size()), launch_density);
    aggregate_attempts += epoch_attempts;
    aggregate_partners += epoch_partners;

    CandidateHarvestSummary candidate_harvest;
    candidate_harvest.selected_groups = selected_endpoints.size();
    std::string outcome = "neutral";
    DoorAdmission door_admission;
    bool epoch_exact_novel = false;
    bool epoch_fleet_best = false;

    struct DownloadedCandidate {
      GroupHarvestEndpoint endpoint;
      Scheme scheme;
      int computed_density = 0;
    };
    std::vector<DownloadedCandidate> downloaded_candidates;
    downloaded_candidates.reserve(selected_endpoints.size());

    // Download exactly the selected top-K prefix. Every scheme passes the
    // exhaustive host tensor and metadata gate before this epoch mutates the
    // archive, door bank, adaptive reward, or fleet best.
    for (const GroupHarvestEndpoint& endpoint : selected_endpoints) {
      Scheme candidate;
      candidate.source = "cuda epoch " + std::to_string(epoch) + " group " +
                         std::to_string(endpoint.group);
      candidate.terms.resize(static_cast<size_t>(endpoint.rank));
      std::vector<int64_t> out_u(endpoint.rank), out_v(endpoint.rank),
          out_w(endpoint.rank);
      const size_t offset = static_cast<size_t>(endpoint.group) * kCap;
      cuda_check(cudaMemcpy(out_u.data(), device.best_u + offset,
                            static_cast<size_t>(endpoint.rank) * sizeof(int64_t),
                            cudaMemcpyDeviceToHost),
                 "candidate U download");
      cuda_check(cudaMemcpy(out_v.data(), device.best_v + offset,
                            static_cast<size_t>(endpoint.rank) * sizeof(int64_t),
                            cudaMemcpyDeviceToHost),
                 "candidate V download");
      cuda_check(cudaMemcpy(out_w.data(), device.best_w + offset,
                            static_cast<size_t>(endpoint.rank) * sizeof(int64_t),
                            cudaMemcpyDeviceToHost),
                 "candidate W download");
      ++candidate_harvest.downloaded_schemes;
      candidate_harvest.transfer_bytes += group_endpoint_transfer_bytes(endpoint);
      for (int i = 0; i < endpoint.rank; ++i) {
        candidate.terms[static_cast<size_t>(i)] =
            {static_cast<uint64_t>(out_u[i]), static_cast<uint64_t>(out_v[i]),
             static_cast<uint64_t>(out_w[i])};
      }

      const VerifyResult verified =
          verify_device_candidate(candidate, endpoint.rank, endpoint.density);
      const int computed_density = density(candidate);
      if (!verified.exact) {
        ++exact_rejects;
        std::string reject_path = config.out_path + ".reject.epoch-" +
                                  std::to_string(epoch);
        if (config.harvest_top_k > 1) {
          reject_path += ".group-" + std::to_string(endpoint.group);
        }
        reject_path += ".txt";
        write_text_atomic(reject_path, serialize_scheme(candidate));
        complete_candidate_harvest_epoch(policy, candidate_harvest);
        const long long elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                      std::chrono::steady_clock::now() - started)
                                      .count();
        write_text_atomic(config.status_path,
                          status_body("exact-reject", epoch, config.dispatches, elapsed,
                                      global_best,
                                      scheduled_door_count(original_roots, descendants,
                                                           global_best),
                                      run_seed, aggregate_attempts, aggregate_partners,
                                      candidates, exact_rejects, verified.reason, &policy));
        throw std::runtime_error("GPU exact gate rejected epoch " + std::to_string(epoch) +
                                 " group " + std::to_string(endpoint.group) + ": " +
                                 verified.reason);
      }
      ++candidate_harvest.exact_schemes;
      ++candidates;
      downloaded_candidates.push_back(
          {endpoint, std::move(candidate), computed_density});
    }

    for (size_t candidate_index = 0;
         candidate_index < downloaded_candidates.size(); ++candidate_index) {
      DownloadedCandidate& downloaded = downloaded_candidates[candidate_index];
      Scheme& candidate = downloaded.scheme;
      const bool absolute_winner = candidate_index == 0;
      const std::string key = canonical_key(candidate);
      const bool novel = known.insert(key).second;
      if (novel) {
        ++candidate_harvest.novel_schemes;
        std::ostringstream name;
        const uint64_t digest = key_digest(key);
        name << config.archive_dir << "/epoch-" << std::setw(8) << std::setfill('0') << epoch;
        if (config.harvest_top_k > 1) {
          name << "-g" << std::setw(6) << std::setfill('0')
               << downloaded.endpoint.group;
        }
        name << "-r" << candidate.terms.size() << "-d" << downloaded.computed_density << "-h"
             << std::hex << std::setw(16) << std::setfill('0') << digest << ".txt";
        write_scheme_atomic(name.str(), candidate);
      }

      // The absolute endpoint alone owns fleet-best and scheduler reward.
      // Exact-novel auxiliaries may still become independent restart basins,
      // but only through the strict normal distance gate; they never inherit
      // the source-aware one-parent exception.
      if (absolute_winner) {
        epoch_exact_novel = novel;
        if (novel) {
          door_admission = admit_harvested_descendant(
              original_roots, descendants, candidate, descendant_capacity,
              config.door_min_distance, true, true, choice.role,
              choice.source_index);
          outcome = "exact-novel";
        } else {
          outcome = "exact-duplicate";
        }
        if (objective_better(candidate, global_best)) {
          epoch_fleet_best = true;
          global_best = candidate;
          write_scheme_atomic(config.out_path, global_best);
          outcome = "fleet-best";
        }
      } else if (novel) {
        const DoorAdmission auxiliary_admission = admit_harvested_descendant(
            original_roots, descendants, candidate, descendant_capacity,
            config.door_min_distance, false, true, choice.role,
            choice.source_index);
        if (auxiliary_admission.action != 0) {
          ++candidate_harvest.auxiliary_door_admissions;
        }
      }
    }
    complete_candidate_harvest_epoch(policy, candidate_harvest);

    scheduler.observe(choice, epoch_exact_novel, epoch_fleet_best);
    sync_policy_telemetry(policy, scheduler);
    policy.epoch_door_action = door_admission.action;
    policy.epoch_door_score = door_admission.score;
    policy.epoch_door_source_replacement = door_admission.source_replacement;

    const long long elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                  std::chrono::steady_clock::now() - started)
                                  .count();
    write_text_atomic(config.status_path,
                      status_body("epoch", epoch, config.dispatches, elapsed, global_best,
                                  scheduled_door_count(original_roots, descendants, global_best),
                                  run_seed, aggregate_attempts, aggregate_partners,
                                  candidates, exact_rejects, outcome, &policy));
    std::cout << "CUDA777_EPOCH epoch=" << epoch
              << " role=" << launch_role_name(choice.role)
              << " source=" << choice.source_index
              << " mode=" << mode << " kernel=" << (mode == 0 ? "scan" : "hash")
              << " seed=r" << launch.terms.size() << "/d"
              << launch_density << " device_best=r" << best_rank << "/d" << best_density
              << " fleet_best=r" << global_best.terms.size() << "/d" << density(global_best)
              << " attempts=" << epoch_attempts << " partners=" << epoch_partners
              << " policy=" << policy.role_epochs[0] << '/' << policy.role_epochs[1]
              << '/' << policy.role_epochs[2]
              << " adaptive_role_slots=" << policy.adaptive_role_slots
              << " role_stats=" << role_stats_text(policy.role_stats)
              << " epoch_door_action=" << door_admission.action
              << " epoch_door_score=" << door_admission.score
              << " epoch_door_source_replace="
              << (door_admission.source_replacement ? 1 : 0)
              << " harvest_epoch_completed="
              << policy.harvest_epoch.completed_groups
              << " harvest_epoch_improved=" << policy.harvest_epoch.improved_groups
              << " harvest_epoch_capture_groups="
              << policy.harvest_epoch.capture_groups
              << " harvest_epoch_capture_sum=" << policy.harvest_epoch.capture_sum
              << " harvest_total_completed="
              << policy.harvest_total.completed_groups
              << " harvest_total_improved=" << policy.harvest_total.improved_groups
              << " harvest_total_capture_groups="
              << policy.harvest_total.capture_groups
              << " harvest_total_capture_sum=" << policy.harvest_total.capture_sum
              << " harvest_top_k=" << policy.harvest_top_k
              << " harvest_epoch_selected="
              << policy.candidate_harvest_epoch.selected_groups
              << " harvest_epoch_downloaded="
              << policy.candidate_harvest_epoch.downloaded_schemes
              << " harvest_epoch_exact="
              << policy.candidate_harvest_epoch.exact_schemes
              << " harvest_epoch_novel="
              << policy.candidate_harvest_epoch.novel_schemes
              << " harvest_epoch_aux_doors="
              << policy.candidate_harvest_epoch.auxiliary_door_admissions
              << " harvest_epoch_bytes="
              << policy.candidate_harvest_epoch.transfer_bytes
              << " harvest_total_selected="
              << policy.candidate_harvest_total.selected_groups
              << " harvest_total_downloaded="
              << policy.candidate_harvest_total.downloaded_schemes
              << " harvest_total_exact="
              << policy.candidate_harvest_total.exact_schemes
              << " harvest_total_novel="
              << policy.candidate_harvest_total.novel_schemes
              << " harvest_total_aux_doors="
              << policy.candidate_harvest_total.auxiliary_door_admissions
              << " harvest_total_bytes="
              << policy.candidate_harvest_total.transfer_bytes
              << " original_sources="
              << original_source_stats_text(policy.original_stats)
              << " result=" << outcome << std::endl;

    ++epoch;
    if (static_cast<int>(global_best.terms.size()) <= config.stop_rank) break;
  }

  const long long elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();
  write_text_atomic(config.status_path,
                    status_body("done", epoch, 0, elapsed, global_best,
                                scheduled_door_count(original_roots, descendants, global_best),
                                run_seed, aggregate_attempts, aggregate_partners, candidates,
                                exact_rejects, stop_requested ? "signal" : "complete", &policy));
  std::cout << "CUDA777_DONE epochs=" << epoch << " elapsed_ms=" << elapsed
            << " best=r" << global_best.terms.size() << "/d" << density(global_best)
            << " candidates=" << candidates << " exact_rejects=" << exact_rejects
            << " harvest_total_completed=" << policy.harvest_total.completed_groups
            << " harvest_total_improved=" << policy.harvest_total.improved_groups
            << " harvest_total_capture_groups="
            << policy.harvest_total.capture_groups
            << " harvest_total_capture_sum=" << policy.harvest_total.capture_sum
            << " harvest_top_k=" << policy.harvest_top_k
            << " harvest_total_selected="
            << policy.candidate_harvest_total.selected_groups
            << " harvest_total_downloaded="
            << policy.candidate_harvest_total.downloaded_schemes
            << " harvest_total_exact="
            << policy.candidate_harvest_total.exact_schemes
            << " harvest_total_novel="
            << policy.candidate_harvest_total.novel_schemes
            << " harvest_total_aux_doors="
            << policy.candidate_harvest_total.auxiliary_door_admissions
            << " harvest_total_bytes="
            << policy.candidate_harvest_total.transfer_bytes
            << std::endl;
  return 0;
}
#endif

}  // namespace

int main(int argc, char** argv) {
  try {
    if (argc >= 2 && std::string(argv[1]) == "--self-test") {
      if (argc != 3) throw std::runtime_error("--self-test requires exactly one seed path");
      return self_test(argv[2]);
    }
    if (argc >= 2 && std::string(argv[1]) == "--policy-self-test") {
      std::vector<std::string> recipe_paths;
      for (int i = 2; i < argc; ++i) recipe_paths.emplace_back(argv[i]);
      const int result = policy_self_test(recipe_paths);
      if (result != 0) return result;
      const int status_result = policy_status_self_test();
      if (status_result != 0) return status_result;
      return group_harvest_self_test();
    }
    Config config = parse_config(argc, argv);
#ifdef METAFLIP_HOST_ONLY_TEST
    (void)config;
    throw std::runtime_error(
        "host-only test build supports only --self-test and --policy-self-test");
#else
    return run_campaign(config);
#endif
  } catch (const std::exception& error) {
    std::cerr << "CUDA777_FATAL " << error.what() << std::endl;
    return 2;
  }
}
