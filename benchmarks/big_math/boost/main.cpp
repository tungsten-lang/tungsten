// Boost.Multiprecision cpp_int lane for `tungsten bench bignum`.
//
// Implements the shared external-harness contract (see rust/src/main.rs and
// odin/main.odin): deterministic xorshift operands, per-cell validation,
// 500us warm-up, pilot calibration, and one
// "external\tboost\t<op>\t<limbs>\t<iterations>\t<ns>" row per size.
//
// cpp_int results are ordinary immutable-style values, so like the Rust and
// Python lanes each iteration keeps the previous result live while the next
// one is computed. Operand pointers are laundered through an asm barrier
// every iteration so LLVM cannot hoist a loop-invariant computation out of
// the timed region (the same hazard the Rust lane covers with black_box).

#include <boost/multiprecision/cpp_int.hpp>
#include <boost/version.hpp>

#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using boost::multiprecision::cpp_int;

namespace {

constexpr std::uint64_t kSeedA = 0x243f6a8885a308d3ull;
constexpr std::uint64_t kSeedB = 0x13198a2e03707344ull;
constexpr std::uint64_t kPowmodMSeed = 0xa4093822299f31d0ull;
constexpr unsigned kPowExponent = 5;
constexpr unsigned kShiftBits = 13;
constexpr long kMaxIterations = 40'000'000;
constexpr double kPilotMinNs = 20'000.0;
constexpr double kWarmNs = 500'000.0;

const char* const kSupportedOperations[] = {
    "add", "sub", "mul", "sqr", "div", "mod", "gcd",
    "and", "or",  "xor", "shl", "shr", "cmp", "neg", "abs",
    "pow", "powmod", "lcm", "isqrt", "tostr", "fromstr",
    "add1", "sub1", "mul1", "div1",
};

// Asymmetric "big op small" rows: the second operand is one 64-bit limb,
// and the lane times cpp_int's builtin-integer operator overloads.
bool is_word_row(const std::string& operation) {
  return operation == "add1" || operation == "sub1" ||
         operation == "mul1" || operation == "div1";
}

volatile std::uint64_t bench_sink;

template <typename T>
inline const T* launder_pointer(const T* pointer) {
  asm volatile("" : "+r"(pointer) : : "memory");
  return pointer;
}

double now_ns() {
  return std::chrono::duration<double, std::nano>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

std::uint64_t xorshift_word(std::uint64_t& state) {
  std::uint64_t x = state;
  x ^= x >> 12;
  x ^= x << 25;
  x ^= x >> 27;
  state = x;
  return x * 2685821657736338717ull;
}

std::vector<unsigned char> operand_bytes(std::size_t limbs,
                                         std::uint64_t seed) {
  std::vector<unsigned char> bytes(limbs * 8);
  std::uint64_t state = seed;
  for (std::size_t limb = 0; limb < limbs; ++limb) {
    const std::uint64_t word = xorshift_word(state);
    for (int index = 0; index < 8; ++index) {
      bytes[limb * 8 + index] =
          static_cast<unsigned char>(word >> (8 * index));
    }
  }
  bytes.front() |= 1;
  bytes.back() |= 0x80;
  return bytes;
}

cpp_int from_little_endian(const std::vector<unsigned char>& bytes) {
  cpp_int value;
  boost::multiprecision::import_bits(value, bytes.begin(), bytes.end(), 8,
                                     false);
  return value;
}

cpp_int operand(std::size_t limbs, std::uint64_t seed) {
  return from_little_endian(operand_bytes(limbs, seed));
}

struct Operands {
  std::size_t row_limbs = 0;
  cpp_int a;
  cpp_int b;
  std::uint64_t b_word = 0;
  cpp_int modulus;
  std::string decimal;
};

std::uint64_t low_word(const cpp_int& value);

Operands make_operands(const std::string& operation, std::size_t limbs) {
  Operands input;
  input.row_limbs = limbs;
  std::size_t a_limbs = limbs;
  if (operation == "div" || operation == "mod" || operation == "isqrt") {
    a_limbs = 2 * limbs;
  }
  input.a = operand(a_limbs, kSeedA ^ limbs);
  if (operation == "cmp") {
    input.b = input.a ^ 1;
  } else if (is_word_row(operation)) {
    input.b = operand(1, kSeedB ^ limbs);
  } else {
    input.b = operand(limbs, kSeedB ^ limbs);
  }
  input.b_word = low_word(input.b);
  if (operation == "powmod") {
    input.modulus = operand(limbs, kPowmodMSeed ^ limbs);
  }
  if (operation == "abs") {
    input.a = -input.a;
  }
  if (operation == "fromstr") {
    input.decimal = input.a.str();
  }
  return input;
}

std::uint64_t low_word(const cpp_int& value) {
  if (value.is_zero()) {
    return 0;
  }
  return static_cast<std::uint64_t>(value.backend().limbs()[0]);
}

std::size_t bit_length(const cpp_int& value) {
  if (value.is_zero()) {
    return 0;
  }
  const cpp_int magnitude = boost::multiprecision::abs(value);
  return boost::multiprecision::msb(magnitude) + 1;
}

using ApplyFn = cpp_int (*)(const cpp_int&, const cpp_int&, const cpp_int&,
                            const std::string&, std::uint64_t);

ApplyFn apply_for(const std::string& operation) {
  if (operation == "add") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a + b); };
  }
  if (operation == "sub") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a - b); };
  }
  if (operation == "mul") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a * b); };
  }
  if (operation == "sqr") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a * a); };
  }
  if (operation == "div") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a / b); };
  }
  if (operation == "mod") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a % b); };
  }
  if (operation == "gcd") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) {
      return cpp_int(boost::multiprecision::gcd(a, b));
    };
  }
  if (operation == "and") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a & b); };
  }
  if (operation == "or") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a | b); };
  }
  if (operation == "xor") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a ^ b); };
  }
  if (operation == "shl") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a << kShiftBits); };
  }
  if (operation == "shr") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(a >> kShiftBits); };
  }
  if (operation == "neg") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) { return cpp_int(-a); };
  }
  if (operation == "abs") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) {
      return cpp_int(boost::multiprecision::abs(a));
    };
  }
  if (operation == "pow") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) {
      return cpp_int(boost::multiprecision::pow(a, kPowExponent));
    };
  }
  if (operation == "powmod") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int& modulus,
              const std::string&, std::uint64_t) {
      return cpp_int(boost::multiprecision::powm(a, b, modulus));
    };
  }
  if (operation == "lcm") {
    return [](const cpp_int& a, const cpp_int& b, const cpp_int&,
              const std::string&, std::uint64_t) {
      return cpp_int(boost::multiprecision::lcm(a, b));
    };
  }
  if (operation == "isqrt") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t) {
      return cpp_int(boost::multiprecision::sqrt(a));
    };
  }
  if (operation == "fromstr") {
    return [](const cpp_int&, const cpp_int&, const cpp_int&,
              const std::string& decimal, std::uint64_t) {
      return cpp_int(decimal);
    };
  }
  if (operation == "add1") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t word) {
      return cpp_int(a + word);
    };
  }
  if (operation == "sub1") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t word) {
      return cpp_int(a - word);
    };
  }
  if (operation == "mul1") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t word) {
      return cpp_int(a * word);
    };
  }
  if (operation == "div1") {
    return [](const cpp_int& a, const cpp_int&, const cpp_int&,
              const std::string&, std::uint64_t word) {
      return cpp_int(a / word);
    };
  }
  return nullptr;
}

double bench_bigint(const Operands& input, long iterations, ApplyFn apply) {
  cpp_int previous;
  std::uint64_t sink = 0;
  const double start = now_ns();
  for (long index = 0; index < iterations; ++index) {
    const cpp_int& a = *launder_pointer(&input.a);
    const cpp_int& b = *launder_pointer(&input.b);
    cpp_int result = apply(a, b, input.modulus, input.decimal, input.b_word);
    sink ^= low_word(result) + static_cast<std::uint64_t>(index);
    // The move occurs after the successor is complete, so the prior
    // allocation cannot be released early and reused while the next result
    // is being formed.
    previous = std::move(result);
  }
  const double elapsed = now_ns() - start;
  bench_sink ^= sink ^ low_word(previous);
  return elapsed / static_cast<double>(iterations);
}

double bench_cmp(const Operands& input, long iterations) {
  std::uint64_t sink = 0;
  const double start = now_ns();
  for (long index = 0; index < iterations; ++index) {
    const cpp_int& a = *launder_pointer(&input.a);
    const cpp_int& b = *launder_pointer(&input.b);
    sink ^= static_cast<std::uint64_t>(static_cast<std::int64_t>(
                a.compare(b))) +
            static_cast<std::uint64_t>(index);
  }
  const double elapsed = now_ns() - start;
  bench_sink ^= sink;
  return elapsed / static_cast<double>(iterations);
}

double bench_tostr(const Operands& input, long iterations) {
  std::uint64_t sink = 0;
  const double start = now_ns();
  for (long index = 0; index < iterations; ++index) {
    const cpp_int& a = *launder_pointer(&input.a);
    // String results are not retained between iterations, matching the
    // native lane's tostr lifecycle.
    const std::string text = a.str();
    sink ^= static_cast<std::uint64_t>(text.size()) +
            static_cast<std::uint64_t>(index);
  }
  const double elapsed = now_ns() - start;
  bench_sink ^= sink;
  return elapsed / static_cast<double>(iterations);
}

long warm_iterations(const std::string& operation, std::size_t limbs) {
  // Match the native harness's cheap/expensive warm-up granularity.
  if (operation == "powmod" || (operation == "isqrt" && limbs >= 4) ||
      (operation == "lcm" && limbs >= 16) ||
      ((operation == "div" || operation == "mod" || operation == "gcd") &&
       limbs >= 128)) {
    return 1;
  }
  if (((operation == "mul" || operation == "sqr") && limbs >= 256) ||
      ((operation == "pow" || operation == "tostr" ||
        operation == "fromstr") &&
       limbs >= 64)) {
    return 8;
  }
  return 1024;
}

double run_once(const std::string& operation, const Operands& input,
                long iterations) {
  if (operation == "cmp") {
    return bench_cmp(input, iterations);
  }
  if (operation == "tostr") {
    return bench_tostr(input, iterations);
  }
  return bench_bigint(input, iterations, apply_for(operation));
}

double measure(const std::string& operation, const Operands& input,
               long iterations) {
  const long warm = warm_iterations(operation, input.row_limbs);
  const double warm_start = now_ns();
  do {
    run_once(operation, input, warm);
  } while (now_ns() - warm_start < kWarmNs);
  return run_once(operation, input, iterations);
}

long calibrate(const std::string& operation, const Operands& input,
               double target_ns) {
  long pilot = 1;
  for (;;) {
    const double ns_per_operation = measure(operation, input, pilot);
    if (ns_per_operation * static_cast<double>(pilot) >= kPilotMinNs ||
        pilot >= 4096) {
      const double estimate =
          target_ns / std::max(ns_per_operation, 0.001);
      if (estimate < 1.0) {
        return 1;
      }
      if (estimate > static_cast<double>(kMaxIterations)) {
        return kMaxIterations;
      }
      return static_cast<long>(estimate);
    }
    pilot = std::min(pilot * 16, 4096l);
  }
}

bool validate_case(const std::string& operation, const Operands& input,
                   std::size_t limbs, std::string& error) {
  std::size_t expected_a_bits = 64 * limbs;
  if (operation == "div" || operation == "mod" || operation == "isqrt") {
    expected_a_bits = 128 * limbs;
  }
  if (bit_length(input.a) != expected_a_bits) {
    error = "operand width mismatch";
    return false;
  }
  const std::size_t expected_b_bits =
      is_word_row(operation) ? 64 : 64 * limbs;
  if (operation != "cmp" && bit_length(input.b) != expected_b_bits) {
    error = "second operand width mismatch";
    return false;
  }
  if (is_word_row(operation) && cpp_int(input.b_word) != input.b) {
    error = "hoisted word does not match the one-limb operand";
    return false;
  }
  error = operation + " validation failed";
  const cpp_int& a = input.a;
  const cpp_int& b = input.b;
  if (operation == "add") {
    return cpp_int(cpp_int(a + b) - b) == a;
  }
  if (operation == "sub") {
    return cpp_int(cpp_int(a - b) + b) == a;
  }
  if (operation == "mul") {
    const cpp_int product = a * b;
    return cpp_int(product / a) == b && cpp_int(product % a) == 0;
  }
  if (operation == "sqr") {
    return cpp_int(boost::multiprecision::sqrt(cpp_int(a * a))) == a;
  }
  if (operation == "div" || operation == "mod") {
    const cpp_int quotient = a / b;
    const cpp_int remainder = a % b;
    return cpp_int(quotient * b + remainder) == a && remainder >= 0 &&
           remainder < b;
  }
  if (operation == "gcd") {
    const cpp_int result = boost::multiprecision::gcd(a, b);
    return cpp_int(a % result) == 0 && cpp_int(b % result) == 0;
  }
  if (operation == "and") {
    const cpp_int result = a & b;
    return cpp_int(result & a) == result && cpp_int(result & b) == result;
  }
  if (operation == "or") {
    const cpp_int result = a | b;
    return cpp_int(result | a) == result && cpp_int(result | b) == result;
  }
  if (operation == "xor") {
    return cpp_int(cpp_int(a ^ b) ^ b) == a;
  }
  if (operation == "shl") {
    return cpp_int(cpp_int(a << kShiftBits) >> kShiftBits) == a;
  }
  if (operation == "shr") {
    const cpp_int mask = (cpp_int(1) << kShiftBits) - 1;
    return cpp_int(cpp_int(cpp_int(a >> kShiftBits) << kShiftBits) +
                   cpp_int(a & mask)) == a;
  }
  if (operation == "cmp") {
    return a.compare(b) == 1;
  }
  if (operation == "neg") {
    return cpp_int(-cpp_int(-a)) == a;
  }
  if (operation == "abs") {
    return a < 0 && cpp_int(boost::multiprecision::abs(a)) == cpp_int(-a);
  }
  if (operation == "pow") {
    const cpp_int square = a * a;
    return cpp_int(boost::multiprecision::pow(a, kPowExponent)) ==
           cpp_int(square * square * a);
  }
  if (operation == "powmod") {
    const cpp_int result = boost::multiprecision::powm(a, b, input.modulus);
    return bit_length(input.modulus) == 64 * limbs && result >= 0 &&
           result < input.modulus;
  }
  if (operation == "lcm") {
    const cpp_int result = boost::multiprecision::lcm(a, b);
    const cpp_int divisor = boost::multiprecision::gcd(a, b);
    return result >= 0 && cpp_int(result * divisor) == cpp_int(a * b);
  }
  if (operation == "isqrt") {
    const cpp_int result = boost::multiprecision::sqrt(a);
    const cpp_int next = result + 1;
    return cpp_int(result * result) <= a && cpp_int(next * next) > a;
  }
  if (operation == "tostr") {
    return cpp_int(a.str()) == a;
  }
  if (operation == "fromstr") {
    return cpp_int(input.decimal) == a;
  }
  if (operation == "add1") {
    return cpp_int(cpp_int(a + input.b_word) - input.b_word) == a;
  }
  if (operation == "sub1") {
    return cpp_int(cpp_int(a - input.b_word) + input.b_word) == a;
  }
  if (operation == "mul1") {
    const cpp_int product = a * input.b_word;
    return cpp_int(product / input.b_word) == a &&
           cpp_int(product % input.b_word) == 0;
  }
  if (operation == "div1") {
    const cpp_int quotient = a / input.b_word;
    const cpp_int remainder = a % input.b_word;
    return cpp_int(quotient * input.b_word + remainder) == a &&
           remainder >= 0 && remainder < cpp_int(input.b_word);
  }
  error = "unknown operation: " + operation;
  return false;
}

bool is_supported(const std::string& operation) {
  for (const char* candidate : kSupportedOperations) {
    if (operation == candidate) {
      return true;
    }
  }
  return false;
}

int run_sweep(const std::string& operation, const std::string& size_csv,
              long runs, double target_ms) {
  if (!is_supported(operation)) {
    std::fprintf(stderr, "unknown operation: %s\n", operation.c_str());
    return 2;
  }
  if (runs <= 0 || !(target_ms > 0.0)) {
    std::fprintf(stderr, "invalid runs or target-ms\n");
    return 2;
  }
  const double target_ns = target_ms * 1e6;
  std::size_t position = 0;
  while (position < size_csv.size()) {
    std::size_t comma = size_csv.find(',', position);
    if (comma == std::string::npos) {
      comma = size_csv.size();
    }
    const std::string piece = size_csv.substr(position, comma - position);
    position = comma + 1;
    char* end = nullptr;
    const long limbs = std::strtol(piece.c_str(), &end, 10);
    if (end == piece.c_str() || *end != '\0' || limbs < 1 || limbs > 16384) {
      std::fprintf(stderr, "limb count outside 1..16384: %s\n",
                   piece.c_str());
      return 2;
    }
    const Operands input =
        make_operands(operation, static_cast<std::size_t>(limbs));
    std::string error;
    if (!validate_case(operation, input, static_cast<std::size_t>(limbs),
                       error)) {
      std::fprintf(stderr, "%s\n", error.c_str());
      return 1;
    }
    const long iterations = calibrate(operation, input, target_ns);
    double best = 1e300;
    for (long run = 0; run < runs; ++run) {
      best = std::min(best, measure(operation, input, iterations));
    }
    std::printf("external\tboost\t%s\t%ld\t%ld\t%.3f\n", operation.c_str(),
                limbs, iterations, best);
    std::fflush(stdout);
  }
  return 0;
}

int run_self_test() {
  const cpp_int a("123456789012345678901234567890");
  const cpp_int b("9876543210987654321");
  const cpp_int m("18446744073709551557");
  int failures = 0;
  int checks = 0;
  const auto check = [&](const char* label, const cpp_int& value,
                         const char* expected) {
    ++checks;
    if (value.str() != expected) {
      std::fprintf(stderr, "self-test %s: expected %s, got %s\n", label,
                   expected, value.str().c_str());
      ++failures;
    }
  };
  // Pin the shared xorshift/import contract before checking arithmetic.
  check("operand1", operand(1, kSeedA ^ 1), "10535676081691261443");
  check("operand2", operand(2, kSeedA ^ 2),
        "277571816122073303554693665492320838317");
  check("add", cpp_int(a + b), "123456789022222222112222222211");
  check("sub", cpp_int(a - b), "123456789002469135690246913569");
  check("mul", cpp_int(a * b),
        "1219326311370217952249657064223746380111126352690");
  check("sqr", cpp_int(a * a),
        "15241578753238836750495351562536198787501905199875019052100");
  check("div", cpp_int(a / b), "12499999886");
  check("mod", cpp_int(a % b), "925925941327160484");
  check("gcd", boost::multiprecision::gcd(a, b), "9");
  check("and", cpp_int(a & b), "9300074690673838224");
  check("or", cpp_int(a | b), "123456789012922147421548383987");
  check("xor", cpp_int(a ^ b), "123456789003622072730874545763");
  check("shl", cpp_int(a << kShiftBits),
        "1011358015589135801558913580154880");
  check("shr", cpp_int(a >> kShiftBits), "15070408814983603381498360");
  ++checks;
  if (a.compare(b) != 1) {
    std::fprintf(stderr, "self-test cmp: expected 1, got %d\n",
                 a.compare(b));
    ++failures;
  }
  check("neg", cpp_int(-a), "-123456789012345678901234567890");
  check("abs", cpp_int(boost::multiprecision::abs(cpp_int(-a))),
        "123456789012345678901234567890");
  check("pow", boost::multiprecision::pow(a, kPowExponent),
        "2867971861733704037813816270841549639248697656451325047518479002888"
        "6798337811616713594453748240629383657483209495862454267363852838672"
        "048294900000");
  check("powmod", boost::multiprecision::powm(a, b, m),
        "15615546817603933683");
  check("lcm", boost::multiprecision::lcm(a, b),
        "135480701263357550249961896024860708901236261410");
  check("isqrt", boost::multiprecision::sqrt(a), "351364182882014");
  check("fromstr", cpp_int("123456789012345678901234567890"),
        "123456789012345678901234567890");
  ++checks;
  if (a.str() != "123456789012345678901234567890") {
    std::fprintf(stderr, "self-test tostr: got %s\n", a.str().c_str());
    ++failures;
  }
  if (failures != 0) {
    return 1;
  }
  std::printf("Boost bignum self-test: %d/%d passed\n", checks, checks);
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--self-test") == 0) {
    return run_self_test();
  }
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::printf("%s\n", BOOST_LIB_VERSION);
    return 0;
  }
  if (argc != 6 || std::strcmp(argv[1], "--sweep") != 0) {
    std::fprintf(stderr,
                 "usage: bench_big_math_boost --self-test | --version | "
                 "--sweep OP CSV_SIZES RUNS TARGET_MS\n");
    return 2;
  }
  char* end = nullptr;
  const long runs = std::strtol(argv[4], &end, 10);
  if (end == argv[4] || *end != '\0') {
    std::fprintf(stderr, "invalid run count: %s\n", argv[4]);
    return 2;
  }
  end = nullptr;
  const double target_ms = std::strtod(argv[5], &end);
  if (end == argv[5] || *end != '\0') {
    std::fprintf(stderr, "invalid target-ms: %s\n", argv[5]);
    return 2;
  }
  const int status = run_sweep(argv[2], argv[3], runs, target_ms);
  if (bench_sink == 0xdeadbeefdeadbeefull) {
    std::printf("\n");
  }
  return status;
}
