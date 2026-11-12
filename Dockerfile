# Tungsten in a container — a zero-local-setup way to try the language.
#
#   docker build -t tungsten .
#   docker run --rm -it tungsten                 # prints `tungsten start`
#   docker run --rm -it tungsten wit              # the playground REPL
#
# Builds the self-hosted compiler from source. The build runs with --strict:
# stage 1 and stage 2 must emit byte-identical LLVM IR, or the image build
# fails. clang/LLVM is required to compile .w programs, so it stays in the
# image, not just at build time.
#
# Base: plain Ubuntu LTS. The bootstrap is C and Tungsten only (stage 0 is the
# C VM in implementations/c), so the image carries no Ruby; `tungsten --ruby`,
# the separate Ruby implementation, is not available in it. The toolchain is
# the one CI and the release matrix use (scripts/install-linux-toolchain.sh:
# Clang, lld and the LLVM tools from apt.llvm.org; Linux links via
# -fuse-ld=lld), plus the runtime's C deps (oniguruma, zstd, and OpenBLAS for
# Linux scientific programs).
#
# .dockerignore keeps the build context to the files a release package ships,
# so binaries a working checkout has already built for its own host never
# reach the image.

FROM ubuntu:24.04

ARG LLVM_VERSION=22

COPY scripts/install-linux-toolchain.sh /tmp/install-linux-toolchain.sh
RUN bash /tmp/install-linux-toolchain.sh "$LLVM_VERSION" \
      libonig-dev libzstd-dev libopenblas-dev \
 && rm -rf /var/lib/apt/lists/* /tmp/install-linux-toolchain.sh

# clang is the image's only C compiler: name it for `make`, whose built-in
# default is `cc` (the C VM's Makefile is built again by `tungsten build`).
ENV PATH="/usr/lib/llvm-${LLVM_VERSION}/bin:${PATH}" \
    CC=clang

WORKDIR /tungsten
COPY . .

# Bootstrap the compiler (no Ruby involved). --no-bits keeps the image lean
# (bit entry points are optional tools; build them with `bin/tungsten build`
# later). --strict: a stage-identity mismatch fails this step.
RUN ( ulimit -s 131072 2>/dev/null || true; bin/tungsten bootstrap --no-bits --strict )

# Fail the image build if the freshly built compiler can't compile, link and
# run a program, or if the image's default command can't start.
RUN test "$(bin/tungsten -e '<< 6 * 7')" = 42
RUN bin/tungsten start >/dev/null

ENV PATH="/tungsten/bin:${PATH}"
CMD ["tungsten", "start"]
