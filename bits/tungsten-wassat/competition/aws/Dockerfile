FROM satcomp-infrastructure

USER root
ARG DEBIAN_FRONTEND=noninteractive
ARG WASSAT_REVISION

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        binutils clang git lld make \
    && rm -rf /var/lib/apt/lists/*

# A submission must pass an immutable public commit, for example:
#   --build-arg WASSAT_REVISION=<40-hex-commit>
# stage.sh refuses dirty source and constructs the same top-level /wassat
# layout exercised by the local packaging preflight.
RUN printf '%s\n' "${WASSAT_REVISION}" | grep -Eq '^[0-9a-f]{40}$' \
    && git clone https://github.com/tungsten-lang/tungsten.git /tmp/tungsten \
    && git -C /tmp/tungsten checkout --detach "${WASSAT_REVISION}" \
    && /tmp/tungsten/bits/tungsten-wassat/competition/stage.sh \
         parallel /wassat \
    && /wassat/build.sh \
    && rm -rf /tmp/tungsten

COPY solver_cmd.py /opt/amazon/scripting/harness/entrypoints/solver_cmd.py

WORKDIR /
USER ecs-user
