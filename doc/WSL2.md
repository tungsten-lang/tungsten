# Tungsten on Windows (WSL2)

Tungsten targets **macOS and Linux**. There is no native Windows build yet, but
Tungsten runs great on Windows through **WSL2** (the Windows Subsystem for Linux),
which gives you a real Linux environment. Once WSL2 is set up you follow the
ordinary Linux instructions.

## 1. Install WSL2

In an **administrator** PowerShell:

```powershell
wsl --install
```

This installs WSL2 with Ubuntu by default. Reboot if prompted, then launch
**Ubuntu** from the Start menu and create your Linux username/password. Full
guide: <https://learn.microsoft.com/windows/wsl/install>.

## 2. Install the toolchain (inside Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y git clang llvm lld make pkg-config libonig-dev libzstd-dev
```

`lld` matters: Tungsten links Linux binaries with `-fuse-ld=lld` (GNU `ld` can't
read the runtime's LTO-bitcode archive).

## 3. Install Tungsten

One-liner (builds from source; prefers a prebuilt binary once releases exist):

```bash
curl -fsSL https://tungsten-lang.org/install | sh
```

Or from a clone:

```bash
git clone https://github.com/tungsten-lang/tungsten
cd tungsten
bin/tungsten start          # orient
bin/tungsten build          # bootstrap the self-hosted compiler
```

## 4. Try it

```bash
bin/tungsten -e '<< 1 + 1'
echo '<< "hello world"' > hello.w
bin/tungsten hello.w
```

## Tips

- **Work inside the Linux filesystem** (e.g. `~/tungsten`), not `/mnt/c/...` —
  builds are much faster and avoid cross-filesystem permission quirks.
- **Docker Desktop** with the WSL2 backend also works: `docker build -t tungsten .`
  then `docker run --rm -it tungsten` (see the repo `Dockerfile`).
- Editors: VS Code's *WSL* extension opens the Linux checkout directly; pair it
  with the Tungsten extension (see the editor setup docs).
