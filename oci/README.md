# Tumbleweed containers

Inferenix builds Podman images for Qwen3.8 Swift with optional vision and
Inkling 2 Mini for text. Both have `gfx1201` (RX 9070 XT) and `gfx1100`
builds. The target machine needs Podman and a working AMD kernel driver,
not Nix or ROCm userspace. The images contain dependencies and launchers,
not weights or packs. If someone sent you the two-image `.tar` bundle, start
with the [Tumbleweed quickstart](USAGE.md). You can skip the build
steps here.

## Build and load

Keep one image per model so you can update or transfer it independently.

On the Nix build machine, open a terminal in the Inferenix checkout, beside
`flake.nix`:

```sh
gpu_arch=gfx1201 # Set this to the target GPU's architecture.
mkdir -p dist
nix build ".#qwen38-oci-$gpu_arch" -o "dist/inferenix-qwen38-swift-$gpu_arch.tar.gz"
nix build ".#inkling2mini-oci-$gpu_arch" -o "dist/inferenix-inkling-2-mini-text-$gpu_arch.tar.gz"
```

The files in `dist/` are symlinks into the Nix store. Copy the archives
they point to, not the links themselves. On Tumbleweed, open a terminal in
the folder you copied the archives to. Set `gpu_arch` to the value used for
the build and load the images as your regular user, without `sudo`:

```sh
gpu_arch=gfx1201
podman load -i "inferenix-qwen38-swift-$gpu_arch.tar.gz"
podman load -i "inferenix-inkling-2-mini-text-$gpu_arch.tar.gz"
```

### Tumbleweed distribution

For a single transfer to an RX 9070 or 9070 XT host, build the slim Qwen
image and the standalone Inkling text image into one archive. Run this
from the Inferenix checkout on the build machine with Nix and Podman:

```sh
nix run .#release
```

The command builds both images and loads them into your local Podman store
to make one archive with shared layers. It writes
`dist/inferenix-tumbleweed-gfx1201-slim.tar` and won't overwrite an existing
bundle. Move the old archive aside first if you're making a new one.

Transfer that `.tar` to Tumbleweed and extract it there. The bundle contains
`images.tar.gz` and the [quickstart](USAGE.md) as `README.md`. One
`podman load` imports both images under separate tags.

### Add another GPU target

Find the GPU's `gfx` name in `rocminfo` on a host with ROCm tools. Add it
to `imageTargets` in [`default.nix`](default.nix) and build with that value
of `gpu_arch`. Changing a Podman tag alone does not retarget the compiled
kernels. The compiler, ROCm libraries, and both engines must support the
target. Before sharing an archive, run each image on that GPU and check
that it can generate a response.

### Smaller Qwen image

The experimental `slim` image builds ROCm's math libraries for `gfx1201`
only. It uses the same Qwen runner and cache layout. The regular image
remains the fallback until the slim image has run on an RX 9070 XT.

```sh
nix build .#qwen38-oci-gfx1201-slim -o dist/inferenix-qwen38-swift-gfx1201-slim.tar.gz
podman load -i dist/inferenix-qwen38-swift-gfx1201-slim.tar.gz
```

Use `localhost/inferenix/qwen38:gfx1201-slim` in the Qwen commands below.
The Tumbleweed distribution above uses this image.

## Run on Tumbleweed

Your models and packs can live anywhere. This example uses `models/` and
`qwen38-packs/` beside the archives. To follow that layout, start in the
archive folder and set the variables below in the terminal you'll use to run
the models. If your files already live elsewhere, use their full paths
instead. Keep both Qwen shards together, and use your real filenames rather
than renaming them to match the examples.

```sh
models="$PWD/models"
packs="$PWD/qwen38-packs"
swift='qwen38-00001-of-00002.gguf'
inkling2mini='inkling-2-mini.gguf'
gpu_arch=gfx1201  # Use the same tag you loaded.
ls /dev/dri/renderD*
render=/dev/dri/renderD128  # Pick the node that belongs to your Radeon.
```

In `-v "$models:/models:ro"`, `$models` is the folder on your computer,
`/models` is where the container sees it, and `ro` means read-only. For
example, `models/inkling-2-mini.gguf` appears inside the container as
`/models/inkling-2-mini.gguf`. Podman doesn't copy it. Since `$PWD` gives
the variables full paths, you can change folders after setting them. Set
them again if you open a new terminal.

Use Podman as your regular user. The examples use `crun` and
`--group-add keep-groups` so the container can use your existing access to
`/dev/kfd` and the render node. Run one model at a time. Press Ctrl+C in
its terminal to stop it before starting the other.

## Qwen3.8 serve

Point `packs` at the existing openSUSE `PREPARED_DIR`, the folder containing
`pack/` and, if using speculative decoding, `mtp/`. If you don't have a
pack yet, jump to [Qwen3.8 prepare](#qwen38-prepare) first. Keep a separate
pack folder for each set of weights.

```sh
podman run --rm --pull=never --runtime=crun --userns=keep-id --group-add keep-groups \
  --device /dev/kfd --device "$render" \
  --memory 42g --cgroup-conf memory.swap.max=0 \
  -p 127.0.0.1:8080:8080 \
  -v "$models:/models:ro" -v "$packs:/packs:ro" \
  -e INFERENIX_RAM_CAP_GIB_QWEN38=36 \
  "localhost/inferenix/qwen38:$gpu_arch" serve "/models/$swift" /packs
```

For vision, add `-e "INFERENIX_MMPROJ_QWEN38=/models/your-projector.gguf"`
before the image name, with your projector's actual filename. Adjust the
container memory limit and the lower resident budget for the host. They
do not limit VRAM; use `INFERENIX_VRAM_RESERVE_MIB_QWEN38` for GPU headroom.
If page-locking fails, check the host's locked-memory limit and Podman's
cgroup delegation.

The launcher reports missing files and shard names or sizes that differ
from the pack's metadata. Those checks are advisory: the backend decides
whether it can load the supplied files. To serve without drafting, bind
only `"$packs/pack:/packs/pack:ro"` instead of the whole cache.

## Qwen3.8 prepare

Skip this step if the existing packs load. The same image can fill an
empty or partial cache. Here `:rw` lets the container write to your pack
folder, so the files remain on your computer after the container exits. Set
`draft` to either a directory of BF16 tensors with its `mtp-manifest.json`,
or a packed Q2_0 MTP GGUF compatible with the backend. Both must already
be available locally.

```sh
mkdir -p -- "$packs"
podman run --rm --pull=never --network=none --userns=keep-id \
  -v "$models:/models:ro" -v "$packs:/packs:rw" \
  "localhost/inferenix/qwen38:$gpu_arch" prepare "/models/$swift" /packs "/models/$draft"
```

Omit the last argument to prepare only the model pack. You can add the
draft pack later. Preparation accepts user-supplied manifests; it does
not compare them or the files to an inferenix hash allowlist. It publishes
each completed pack separately and preserves any existing `pack/` or
`mtp/`. Use a new directory to rebuild an existing pack. Nothing runs
automatically at serve time.

## Inkling serve

Inkling only needs the model mount. Set `inkling2mini` to the local GGUF filename:

```sh
podman run --rm --pull=never --runtime=crun --userns=keep-id --group-add keep-groups \
  --device /dev/kfd --device "$render" -p 127.0.0.1:8080:8080 \
  -v "$models:/models:ro" -e "INFERENIX_MODEL_INKLING2MINI=/models/$inkling2mini" \
  "localhost/inferenix/inkling2mini:$gpu_arch" serve
```

Leave the server terminal open. From a second terminal, check
`curl --fail http://127.0.0.1:8080/health` once the model has loaded.
Settings can be passed as `-e INFERENIX_…` or in a trusted Bash file
mounted read-only and selected with the runner's `--env-file PATH`. Model
paths in a mounted config are container paths. Publish the port on
loopback as shown above unless the API is meant to be reachable remotely.
