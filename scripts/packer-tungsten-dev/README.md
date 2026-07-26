# tungsten-dev AMIs (Graviton + Intel)

One Packer template, two architecture-specific AMIs, one shared provisioner.

AMIs are per-architecture (they contain compiled binaries), so Graviton (arm64)
and Intel/AMD (x86_64) each get their own image — but both are built from the
same `provision.sh`, since `dnf`/`pip`/`gem` install arch-native packages and the
SAT solvers build from source.

## Build

```bash
brew install packer                 # or https://developer.hashicorp.com/packer
cd scripts/packer-tungsten-dev
packer init .
packer build .                      # → tungsten-dev-arm64-<ts> AND -x86_64-<ts>
packer build -only='tungsten-dev.amazon-ebs.arm64' .    # one arch only
packer build -var region=us-west-2 -var volume_gb=30 .
```

Produced AMI IDs land in `manifest.json`. Builders run on **spot** (pennies) and
Packer auto-creates/deletes a temporary key pair + security group and picks a
public subnet (this account has no default VPC, so the template uses a
`subnet_filter`).

## What's baked in

- **Tungsten toolchain:** clang/llvm/lld (WIRE→LLVM→native backend), gcc/g++,
  make/cmake/ninja, git, plus the -devel libs the runtime links against.
- **Ruby:** interpreter + bundler/rake/rspec/rubocop (the `--ruby` bootstrap and
  the gem).
- **Python ML:** numpy, scipy, **scikit-learn**, pandas, matplotlib (binary
  wheels on both arches; provisioner asserts they didn't fall back to source).
- **SAT solvers:** CaDiCaL, Kissat (built from source → `/usr/local/bin`).

Edit `provision.sh` to add/trim. Note: CUDA/GPU ML frameworks are x86-only — bake
those into the x86 image or a dedicated GPU box, not the Graviton image.
