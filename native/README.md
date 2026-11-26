# Native Linux

Build and run Inkling 2 Mini or Qwen3.8 Swift on a Radeon without Nix or Podman.

## Dependencies

- x86-64 Linux with glibc, an AVX2 CPU, and a working `amdgpu` driver.
- Bash, GNU coreutils, grep, util-linux, curl, jq, tar, gzip, and patch.
- CMake 3.24 or newer, Ninja, and a C/C++20 toolchain.
- ROCm HIP development tools and runtime.
- For Qwen: hipBLAS development libraries and their rocBLAS dependencies,
  plus a systemd user manager with cgroup v2 memory control. To make
  packs, you'll also need Python 3 with venv and pip.

## TL;DR: Run Inkling 2 Mini

From the checkout root, copy [`.env.template`](../.env.template) to `.env`
if you don't have one. Set `INFERENIX_MODEL_INKLING2MINI` in `.env` to your
local GGUF path.

```bash
gpu=gfx1201  # RX 9070 or 9070 XT. Use your GPU's gfx target.
./native/fetch-sources.sh inkling2mini
./native/build.sh inkling2mini --gpu "$gpu"
./native/run.sh inkling2mini --gpu "$gpu"
```

The server listens on `127.0.0.1:8080` by default. The scripts don't
install dependencies or download model weights.

- [Usage](USAGE.md): Find your GPU target, configure a model, or set up Qwen.
- [Troubleshooting](TROUBLESHOOT.md): Fix build, GPU access, or service errors.
