# Native usage

Run these commands from the inferenix checkout root, beside `flake.nix`,
as your regular user. If you're starting with Inkling 2 Mini, the
[quick start and dependency list](README.md) cover the basics.

## Choose a GPU target

Use the same target when building and serving. The RX 9070 and 9070 XT use
`gfx1201`, and the RX 7900 XT and 7900 XTX use `gfx1100`. If you're unsure,
run `rocminfo | grep gfx` and look for the entry for your Radeon. See
[AMD's ROCm installation guide](https://rocm.docs.amd.com/en/latest/install/rocm.html)
for setup instructions for your GPU and distro.

```bash
gpu=gfx1201  # Set this again if you open a new terminal.
```

## Configure local models

Copy [`.env.template`](../.env.template) to `.env` if you don't already
have one. Set the entries for the model you want to run, using your actual
filenames. Relative paths in these examples are relative to the checkout
root. Full paths work too, so you don't have to move any downloads.

```bash
INFERENIX_MODEL_INKLING2MINI="models/inkling-2-mini.gguf"
INFERENIX_MODEL_QWEN38="models/qwen38-00001-of-00002.gguf"
INFERENIX_PREPARED_DIR_QWEN38="qwen38-packs"
```

Inkling needs one GGUF. Qwen needs both shards in the same directory with
their original filenames. Point at the first shard and set
`INFERENIX_PREPARED_DIR_QWEN38` to the directory that contains `pack/`,
rather than to `pack/` itself. Use a different pack directory for each
set of weights.

For a separate config, use `--env-file PATH` on prepare or serve, or set
`INFERENIX_ENV_FILE`. The flag wins over the variable, and either replaces
`.env`. Inferenix reads the selected file as Bash, so only use configs you
trust.

## Build and run Qwen3.8 Swift

```bash
./native/fetch-sources.sh qwen38
./native/build.sh qwen38 --gpu "$gpu"
```

The fetch step downloads and verifies the pinned archives. The build uses
local sources. Both write under `native/.work/`; rerun them after updating
the checkout. If compilation slows your desktop, add `--jobs 2` to the
build command. The same applies to Inkling.

If you already have a working pack, skip preparation. Otherwise, create
the Python environment and prepare the pack once. This uses additional
disk space and leaves the GGUFs untouched.

```bash
python3 -m venv .venv
.venv/bin/python -m pip install numpy regex pyyaml tqdm
./native/prepare-qwen38.sh
```

For optional speculative decoding, set `INFERENIX_MTP_SOURCE_QWEN38` to a
compatible local Q2_0 draft GGUF or a directory of raw BF16 tensors with its
`mtp-manifest.json`, then run prepare again. Preparation keeps existing
`pack/` and `mtp/` directories. To rebuild a pack, use a fresh output
directory.

```bash
./native/run.sh qwen38 --gpu "$gpu"
```

To run Qwen in the background instead, append `start` after the GPU option.
Use `./native/run.sh qwen38 status`, `logs`, or `stop` to manage it.
Those three commands don't need a GPU option or model config.

## Check readiness

Leave the foreground server running. From a second terminal, check the
default endpoint:

```bash
curl --fail http://127.0.0.1:8080/health
```

Retry if the model is still loading. Both runners use port 8080 by default.
Press Ctrl+C to stop a foreground server before switching models. If the
server won't start, see [Troubleshooting](TROUBLESHOOT.md).
