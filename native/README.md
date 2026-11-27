# Native Linux

Build and run Inkling 2 Mini or Qwen3.8 Swift on a Radeon without Nix or Podman.

## Dependencies

- x86-64 Linux with glibc, an AVX2 CPU, and a working `amdgpu` driver.
- Bash, Git 2.29 or newer, GNU coreutils, grep, util-linux, jq, tar, and patch.
- CMake 3.24 or newer, Ninja, and a C/C++20 toolchain.
- ROCm HIP development tools and runtime.
- For Qwen: hipBLAS development libraries and their rocBLAS dependencies,
  plus a systemd user manager with cgroup v2 memory control. To make
  packs, you'll also need Python 3 with venv and pip.

## TL;DR: Build both models

From the checkout root, run these commands with
[your GPU's gfx target](USAGE.md#choose-a-gpu-target):

```bash
gpu=gfx1201  # RX 9070 or 9070 XT
./native/fetch-sources.sh all
./native/build.sh inkling2mini --gpu "$gpu"
./native/build.sh qwen38 --gpu "$gpu"
```

To build just one, replace `all` with `inkling2mini` or `qwen38` and run
only the matching build command. These steps don't need `.env` or model weights.

## Run a model

Copy [`.env.template`](../.env.template) to `.env` if you don't have one.
For Inkling, set `INFERENIX_MODEL_INKLING2MINI` to the path of your local GGUF:

```bash
./native/run.sh inkling2mini --gpu "$gpu"
```

The server listens on `127.0.0.1:8080` by default. The scripts don't install
dependencies or download model weights.

- [Usage](USAGE.md): See [`.env` examples](USAGE.md#configure-local-models)
  and learn how to [prepare and run Qwen](USAGE.md#build-and-run-qwen38-swift).
- [Troubleshooting](TROUBLESHOOT.md): Fix build, GPU access, or service errors.
