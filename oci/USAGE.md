# Inferenix for openSUSE Tumbleweed

This bundle is for the RX 9070 and 9070 XT (`gfx1201`). It has two Podman
images: Qwen3.8 Swift with smaller, GPU-specific ROCm libraries, and Inkling
2 Mini for text. You don't need Nix. Bring your own GGUF model files and, if
you have them, your existing Qwen packs.

## 1. Load the images once

Open a terminal in the extracted folder. If you unpacked it in Downloads,
it might look like this:

```sh
cd "$HOME/Downloads/inferenix-tumbleweed-gfx1201-slim"
ls
podman load -i images.tar.gz
```

Use the folder where `ls` shows this README and `images.tar.gz`. Leave
`images.tar.gz` as it is; Podman reads it directly. If `podman` is missing,
install the `podman` and `crun` packages through Tumbleweed's package manager.
Run all the Podman commands as your regular user, without `sudo`. Podman
keeps the loaded images for that user, so you don't have to load them again
or stay in the extracted folder.

## 2. Point Podman at your files

Your models and Qwen packs can live anywhere. For this example, we'll keep
`models/` and `qwen38-packs/` beside `images.tar.gz` so everything is easy to
find. If you're starting fresh, run `mkdir -p models` in the extracted folder
and put your GGUF files there. Keep their original filenames.

```text
inferenix-tumbleweed-gfx1201-slim/
├── README.md
├── images.tar.gz
├── models/
│   ├── inkling-2-mini.gguf
│   ├── qwen38-00001-of-00002.gguf
│   └── qwen38-00002-of-00002.gguf
└── qwen38-packs/
    ├── pack/
    └── mtp/  (optional)
```

Run these lines from the extracted folder, in the same terminal you'll use
to start a model. If your files are already somewhere else, change `models`
or `packs` to their full paths. No need to move a big download. Keep both
Qwen shards together and set `swift` to the first shard's filename. If you
only want Inkling, skip `packs` and `swift`.

```sh
models="$PWD/models"
packs="$PWD/qwen38-packs"
inkling2mini='inkling-2-mini.gguf'
swift='qwen38-00001-of-00002.gguf'
```

A mount makes a folder on your computer visible inside the container. In
`-v "$models:/models:ro"`, the left side is your real folder, the middle
is where the container sees it, and `ro` means read-only. So
`models/inkling-2-mini.gguf` in the extracted folder becomes
`/models/inkling-2-mini.gguf` inside the container. Nothing gets copied.
`$PWD` gives Podman a full path to your folder, so after setting the
variables you can run the commands from anywhere. If you open a new
terminal, go back to the extracted folder and set the variables again.

The container also needs access to the GPU. List the render nodes and pick
the one for your Radeon. If you have more than one GPU, `ls -l /dev/dri/by-path/`
can help match the nodes to their PCI devices.

```sh
ls /dev/dri/renderD*
render=/dev/dri/renderD128  # Change this if your Radeon uses another node.
ls -l /dev/kfd "$render"
```

Your regular user needs access to both devices. If Podman says permission
denied, check your GPU device permissions first. The commands below use
`crun` to pass your group access through to the container.

## 3. Start a model

Try Inkling first if you just want to check the setup. It doesn't need packs.

```sh
podman run --rm --pull=never --runtime=crun --userns=keep-id --group-add keep-groups \
  --device /dev/kfd --device "$render" -p 127.0.0.1:8080:8080 \
  -v "$models:/models:ro" -e "INFERENIX_MODEL_INKLING2MINI=/models/$inkling2mini" \
  localhost/inferenix/inkling2mini:gfx1201 serve
```

Leave that terminal open. In a second terminal, run
`curl --fail http://127.0.0.1:8080/health` to check whether the server is ready.
If it's still loading, give it a moment and try again. Press Ctrl+C in the
server terminal to stop it before switching models. Both use the same port.

### Qwen3.8 Swift

If you already have prepared packs, point `packs` at the folder **containing**
`pack/` and optionally `mtp/`, not at `pack/` itself. Skip the next command.

Otherwise, prepare the model pack once. This command can write to your pack
folder (`rw`); it can't change your weights (`ro`) or download anything.

```sh
mkdir -p -- "$packs"
podman run --rm --pull=never --network=none --userns=keep-id \
  -v "$models:/models:ro" -v "$packs:/packs:rw" \
  localhost/inferenix/qwen38:gfx1201-slim prepare "/models/$swift" /packs
```

For optional MTP drafting, add a final argument such as
`/models/my-draft.gguf` for a compatible local Q2_0 draft, or use a mounted
folder with raw draft tensors and `mtp-manifest.json`. Preparation preserves
existing packs and doesn't require files to match a fixed list of hashes.
Use a separate pack folder for a different set of Qwen weights.

Once the pack is ready, start Qwen. Both mounts are read-only now.

```sh
podman run --rm --pull=never --runtime=crun --userns=keep-id --group-add keep-groups \
  --device /dev/kfd --device "$render" \
  --memory 42g --cgroup-conf memory.swap.max=0 -p 127.0.0.1:8080:8080 \
  -v "$models:/models:ro" -v "$packs:/packs:ro" \
  -e INFERENIX_RAM_CAP_GIB_QWEN38=36 \
  localhost/inferenix/qwen38:gfx1201-slim serve "/models/$swift" /packs
```

The example gives the container a 42 GiB system RAM limit and the Qwen
engine a lower 36 GiB budget. Lower both if you need to leave more room for
your desktop. Check the same `/health` address once Qwen has loaded.

We verified that both images load in rootless Podman. GPU inference on a
9070 or 9070 XT has not been verified.
