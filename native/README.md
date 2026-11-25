# Build and run inferenix on Linux

This guide runs Inkling 2 Mini and Qwen3.8 Swift on your AMD GPU without Nix
or Podman. Start with Inkling if you want to try the setup with one GGUF
file. Qwen needs two GGUF shards and a prepared pack.

## 1. Open the checkout and check your tools

Open a terminal in your inferenix checkout. For example, if you cloned it
into Downloads:

```sh
cd "$HOME/Downloads/inferenix"
ls
```

Use the folder where `ls` shows `flake.nix` and `native/`. Run the commands
below from **that folder**, not from inside `native/`. Use your regular
account for building and serving.

You need x86-64 Linux with glibc, an AVX2 CPU, and a Radeon with a working
`amdgpu` driver. Your account needs read and write access to `/dev/kfd` and
the GPU's render node under `/dev/dri/`. If access is denied, check your
distro's GPU permissions and sign back in after any group changes.

The scripts check for dependencies but don't install them. Use your
distro's package manager or ask an administrator for these:

- Bash, GNU coreutils, grep, util-linux, curl, jq, tar, gzip, and patch.
- CMake 3.24 or newer, Ninja, and a C/C++20 toolchain. On Tumbleweed, look
  for `cmake`, `ninja`, `gcc`, and `gcc-c++`. On Ubuntu, look for `cmake`,
  `ninja-build`, and `build-essential`.
- ROCm development tools and libraries for your GPU. On Tumbleweed, look
  for `hipcc` and `rocm-hip-devel`. Qwen also needs `hipblas-devel` and
  its rocBLAS dependencies. On Ubuntu or another distro, check
  [AMD's setup guide](https://rocm.docs.amd.com/en/latest/install/rocm.html)
  for packages that match your GPU and distro.
- For Qwen serving, a systemd user manager and cgroup v2 memory control.
  For making Qwen packs, Python 3 with venv and pip support. Inkling needs
  neither.

## 2. Fetch and build

Choose the GPU target for your card. The RX 9070 and 9070 XT use `gfx1201`;
the RX 7900 XT and 7900 XTX use `gfx1100`. If you're unsure, run
`rocminfo | grep gfx` and look for your Radeon. Use the same target when
you build and run. Set `gpu` again if you open a new terminal.

```sh
gpu=gfx1201  # Change this to gfx1100 for an RX 7900 XT or XTX.
./native/fetch-sources.sh inkling2mini
./native/build.sh inkling2mini --gpu "$gpu"
```

For Qwen, replace `inkling2mini` with `qwen38` in both commands. The fetch
step downloads and verifies the pinned source archives. The build uses
those local sources and doesn't download anything. Both put their output
under `native/.work/`. You can run them again after an update. If the
compile makes your desktop sluggish, add `--jobs 2` to the build command.

## 3. Point inferenix at your models

You don't need to move existing downloads. Use full paths if your files
are elsewhere. To keep everything together for this example, run
`mkdir -p models` from the checkout and put your GGUFs there. Keep their
original filenames, especially the two Qwen shards.

```text
inferenix/
├── .env
├── native/
├── models/
│   ├── inkling-2-mini.gguf
│   ├── qwen38-00001-of-00002.gguf
│   └── qwen38-00002-of-00002.gguf
└── qwen38-packs/
    ├── pack/
    └── mtp/       optional draft pack
```

Run `test -e .env || cp .env.template .env` to create a config only if one
doesn't already exist. Open `.env` in your editor and **replace** the example
settings for the model you want to run. Use your actual filenames:

```sh
INFERENIX_MODEL_INKLING2MINI="models/inkling-2-mini.gguf"
INFERENIX_MODEL_QWEN38="models/qwen38-00001-of-00002.gguf"
INFERENIX_PREPARED_DIR_QWEN38="qwen38-packs"
```

These relative paths work when you run from the checkout. For Qwen, point
at the first shard and at the folder **containing** `pack/`, not at
`pack/` itself. If you prefer a separate config, pass `--env-file PATH`
to prepare or serve. It replaces `.env`. Use only configs you trust:
inferenix reads them as Bash.

## 4. Start a model

For Inkling, you're ready:

```sh
./native/run.sh inkling2mini --gpu "$gpu"
```

For Qwen, skip the next block if your existing pack loads. Otherwise,
create the Python environment and prepare the pack once. This takes disk
space and leaves your GGUFs alone.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install numpy regex pyyaml tqdm
./native/prepare-qwen38.sh
```

Drafting is optional. To prepare a draft too, set `INFERENIX_MTP_SOURCE_QWEN38`
to a compatible local Q2_0 draft GGUF or a folder of raw tensors with its
`mtp-manifest.json`, then run prepare again. It keeps existing packs. Use a
separate pack folder for a different set of weights.

```sh
./native/run.sh qwen38 --gpu "$gpu"
```

Leave the server terminal open. In another terminal, run
`curl --fail http://127.0.0.1:8080/health`. If the server is still loading,
give it a moment and retry. Use Ctrl+C to stop it before switching models.
Both use port 8080 by default.

To leave Qwen running in the background, add `start` after the GPU option.
Use `./native/run.sh qwen38 status`, `logs`, or `stop` to manage the service.
Those commands don't need a GPU option or model config.

## If you get stuck

- **The build reports a dependency problem.** If it says "Trying the
  build anyway," you can let it finish. The preflight can't recognize
  every ROCm layout. If the build stops, open the log it points to:
  `dependencies.log` has the small compiler check and `configure-*.log`
  has the actual CMake setup. For a custom install, export `ROCM_PATH`
  and add its prefix to `CMAKE_PREFIX_PATH` so CMake can find the SDK.
  If compiler discovery fails, set `HIPCXX` for Qwen to ROCm's absolute
  `clang++` path. For Inkling, set `INFERENIX_NATIVE_HIPCC` to the path
  of either `hipcc` or ROCm's `clang++`.
- **A shared library or GPU can't be found at launch.** Use the matching
  ROCm runtime. For a custom install, export `LD_LIBRARY_PATH` with its
  library directories. Check `ls -l /dev/kfd /dev/dri/renderD*` and confirm
  the build target matches your card.

### Qwen service troubleshooting

Run `systemctl --user status` as your regular user. If it can't reach the
user manager, sign in directly rather than using `sudo` or `su`. If the
service reports missing cgroup memory files, ask your administrator to
check memory accounting and delegation for the user service. Qwen runs in
that service even in the foreground so the RAM limit and swap limit apply.
The defaults are a 48 GiB service cap and a 40 GiB engine budget. On a
machine with less RAM, lower `INFERENIX_MEMORY_MAX_QWEN38` and
`INFERENIX_RAM_CAP_GIB_QWEN38` together, keeping the engine budget lower.
