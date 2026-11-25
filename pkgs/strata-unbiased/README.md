# UnbiasedStrata

[`sources.json`](sources.json) pins robertkarl/UnbiasedStrata at `9f75192` and
the exact llama.cpp revision recorded by that commit. Nix and the native
builder share these pins and the ordered patch list. Nix verifies the
unpacked trees with `hash`; the native fetcher verifies archive bytes with
`archiveSha256`. Check both digests when updating either source.

[`default.nix`](default.nix) builds the
Qwen HIP engines and HTTP frontend, or just the CPU frontend for the Inkling
runner. The Qwen packing tools and small runtime data come from that same
source pin.

The ordered [patch queue](patches/) preserves the source changes from the
AMD/Nix fork:

1. Fix HIP build and link issues, including missing optional sources and
   blocking synchronization.
2. Apply model-card sampling defaults and recognize Inkling's loop GGUF when
   loading its vocabulary. This includes tests for sampling overrides.
3. Distinguish signed-zero differences from actual mismatches in the FP16
   parity diagnostic.

On a pin bump, check the upstream llama.cpp gitlink, drop patches superseded
upstream, and run `nix flake check`. On AMD hardware, run
`nix run .#check-gpu` and test both Qwen runners before changing the default
pin. A CPU-only frontend build does not validate the HIP engine.
