# Niko Strata 0.1.67

[`default.nix`](default.nix) builds the standalone Inkling engine from
[Niko1221/Strata](https://github.com/Niko1221/Strata) at the checked revision
in [`source.json`](source.json). This engine needs **no local patches**. The
Inkling vocabulary compatibility patch belongs to the separately built
UnbiasedStrata frontend.

Set `INFERENIX_MODEL_INKLING2MINI` to a local Inkling 2 Mini GGUF and run
`nix run .#inkling2mini`. The context defaults to 4,096 tokens. Build just the
engine with `nix build .#strata`.

Leave `INFERENIX_DRAFT_INKLING2MINI` empty unless your workload benefits from DSpark.
On the RX 7900 XTX, stock UD-Q4_K_M decoded at 77.0 tok/s without draft
and 74.3 tok/s with the safetensors head. Benchmark your workload and
check the startup logs to confirm drafting is enabled. For a no-draft
comparison, run `nix run .#inkling2mini -- -- --draft off`.
