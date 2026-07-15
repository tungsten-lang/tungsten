# Tungsten in a container — a zero-local-setup way to try the language.
#
#   docker build -t tungsten .
#   docker run --rm -it tungsten                 # prints `tungsten start`
#   docker run --rm -it tungsten wit              # the playground REPL
#
# Builds the self-hosted compiler from source (stage 1 == stage 2 byte-identity
# is checked). clang/LLVM is required to compile .w programs, so it stays in the
# image, not just at build time.
#
# Base: the official Ruby image (matches .ruby-version; bundles gcc/make/bundler
# so the driver's native-extension gems build cleanly). We add the Tungsten
# toolchain: clang + LLVM + lld (Linux links via -fuse-ld=lld) and the runtime's
# C deps (oniguruma, zstd, and OpenBLAS for Linux scientific programs).

FROM ruby:4.0.5

RUN apt-get update && apt-get install -y --no-install-recommends \
      clang llvm lld pkg-config \
      libonig-dev libzstd-dev libopenblas-dev \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tungsten
COPY . .

# Install the driver's gems, then bootstrap the compiler. --no-bits keeps the
# image lean (bit entry points are optional tools; build them with
# `bin/tungsten build` later).
RUN (cd implementations/ruby && bundle install) \
 && ( ulimit -s 131072 2>/dev/null || true; bin/tungsten build --no-bits )

# Fail the image build if the freshly built compiler can't run a program.
RUN bin/tungsten -e '<< 6 * 7'

ENV PATH="/tungsten/bin:${PATH}"
CMD ["tungsten", "start"]
