# inferenix

Package the fastest *validated* stack for a model and host. Choose the backend
when launching a runner. Do not add runtime routing.

## Layout and configuration

- Put backend recipes in `pkgs/<platform>/default.nix`, with an owner suffix only for
  forks, such as `pkgs/strata-unbiased/`. Keep source pins, build flags and
  ordered source patches in the recipe. Prefer upstream interfaces and
  submit broadly useful HIP fixes upstream. When upstream replaces a local
  fix, remove its patch, tests and docs together unless a runner still needs
  them. When updating a pin, review its patch series and companion pins,
  including UnbiasedStrata's llama.cpp gitlink.
- Name runners for the model family, including version and variant where
  needed, such as `qwen38` and `inkling2mini`. Put runner
  wiring under `nix/runners/<family>/`, with a `default.nix` module listed in
  `nix/runners/default.nix`. A runner owns backend selection, tuning,
  preparation and service policy. Use a backend package override when only
  one runner needs a build flag or patch.
- Read one trusted Bash config: `--env-file`, then `INFERENIX_ENV_FILE`,
  then `.env`. Name local presets `.env-<preset>`. Never layer presets,
  overwrite local configs, or commit them. Update `.env.template` for
  shareable examples.
- Settings resolve from CLI flags to `INFERENIX_<SETTING>_<FAMILY>`,
  then `INFERENIX_<SETTING>`, then runner defaults.
  For example, `INFERENIX_CTX_QWEN38` overrides `INFERENIX_CTX`. Accept
  host-local and Nix-store model paths without fetching missing weights.

- Keep OCI definitions and Podman instructions in `oci/`. Reuse native
  runner settings. Build images without models or packs; prepare writes a
  host cache and serve opens it read-only.
- Keep non-Nix build scripts and their user guide in `native/`. Reuse pins
  and patch order from `pkgs/` and Bash runner policy from `nix/runners/`.
  The native fetch step verifies pinned Git commits; build, prepare, and serve
  use local inputs. Check for host dependencies without installing them.

## Trust boundaries and validation

- Review the upstream code the package actually builds and runs. For
  Inkling, build only Niko's pinned standalone HIP engine and serve it
  through UnbiasedStrata. Do not invoke upstream installers, updaters or
  download-and-execute paths. PolyStrata is not installed separately.
- Keep Linux Nix sandboxing on, with fallback off. Separate hashed
  acquisition from compilation and serving. Fixed-output fetchers have
  network access; a hash checks bytes, not trustworthiness. Leave model
  acquisition to the user. Runners and pack preparation use local inputs.
- The build sandbox does not follow the running server. An offline flag
  is not an egress restriction. Bind to loopback by default and use a
  runtime sandbox when network or filesystem isolation is required.
- Run `nix flake check --offline` after packaging or runner changes.
  Benchmark pin or tuning changes on the target GPU before changing
  defaults. Compare the same quant, context and prompts; check output
  quality, latency, decode rate and peak memory. Say what was not tested.
