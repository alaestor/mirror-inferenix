# InfereNix

[![License MIT](https://img.shields.io/badge/LICENSE-MIT-GREEN)](LICENSE)
![Hallucinated Slop](https://img.shields.io/badge/%E2%80%94_Hallucinated%20Slop_%E2%80%94-red)

A portmanteau of *inference* and *Nix*:
a flake for LLM inference focused on my hardware and personal usecases.

This flake packages model-specific inference stacks for Linux.
Each launcher names the backend and model family it was built for;
this isn't a router.

The first packages target AMD `gfx1100` and x86-64 Linux. The host needs
`amdgpu` and access to `/dev/kfd` and the GPU render node. Some launchers also need a
systemd user manager for more control of system resource consumption.

---

| Launcher | Inference backend | Local inputs |
| --- | --- | --- |
| `qwen36` | [UnbiasedStrata](pkgs/strata-unbiased/) HIP, `strata-poly` | Qwen3.6-35B-A3B GGUF |
| `qwen38` | [UnbiasedStrata](pkgs/strata-unbiased/) HIP, `strata` | Both Flash-Next GGUF shards and prepared packs |
| `inkling2mini` | [Niko Strata 0.1.67](pkgs/strata/) HIP, with the UnbiasedStrata HTTP frontend | Inkling 2 Mini GGUF |

## Run a model

Building without Nix or Podman? Start with the [native Linux guide](native/README.md).
It covers Inkling 2 Mini and Qwen3.8 on openSUSE and other Linux distros.

Launchers source the selected file as Bash.

```sh
test -e .env || cp .env.template .env
# Edit the model paths in .env.
nix run .#qwen36
curl --fail http://127.0.0.1:8080/health
```

Use `--env-file PATH` after the Nix argument separator to replace `.env`:
`nix run .#inkling2mini -- --env-file .env-inkling2mini`. You can also set
`INFERENIX_ENV_FILE`; the CLI path wins. Stop a foreground run with Ctrl-C.

Set `INFERENIX_CTX=8192` for a shared context and
`INFERENIX_CTX_QWEN38=16384` to override it for Qwen3.8. The order is CLI
flags, family-specific variables, shared variables, then runner defaults.
An empty family variable clears its shared value. The default contexts are
32768 for Qwen3.6, 8192 for Qwen3.8, and 4096 for Inkling.

`INFERENIX_MODEL` and `INFERENIX_MODEL_<FAMILY>` take a GGUF filename, whether
it comes from a manual download or a separate Nix package. Use the GGUF
inside the package output, not the output directory itself. A Nix
configuration can also generate an env file with `pkgs.writeText` and pass
its path with `--env-file`. Do not put secrets in a Nix store file.

For Qwen3.8, set `INFERENIX_MODEL_QWEN38` to the first shard and
`INFERENIX_PREPARED_DIR_QWEN38` to an existing pack directory. To make the
packs locally, run `nix run .#prepare-qwen38`. To include a draft pack, set
`INFERENIX_MTP_SOURCE_QWEN38` to a packed Q2_0 MTP GGUF or to raw draft tensors
with their manifest. Start with
`nix run .#qwen38`; use `nix run .#qwen38 -- start` to detach, and
`-- stop`, `-- status` or `-- logs` to manage it. The user service limits
memory to 48 GiB by default and disables service swap.

The flake does not download model weights, vision projectors, or draft
tensors. Supply any of those files your runner needs.

## Open Container Images

The [images](oci/) package Qwen3.8 Swift and Inkling 2 Mini for
`gfx1201` and `gfx1100` GPUs. The Qwen image can reuse existing packs or
prepare them offline. Best used with Podman.
