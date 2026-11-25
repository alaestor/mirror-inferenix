# Nix integration

Backend recipes live in `pkgs/<platform>/default.nix`. Add an owner suffix only for a
fork, as in `pkgs/strata-unbiased/`. Keep source pins, build flags, and source
patches in the backend recipe. If a source patch is needed for just one
runner, give the backend a package override so other runners stay on the
unmodified build.

A runner is named for the model family, such as `qwen38` or `inkling2mini`. Put its
module and scripts in `runners/<family>/` and list the directory in
[`runners/default.nix`](runners/default.nix). Keep shared helpers in `runners/`.
Each runner selects its backend and owns tuning, preparation, and service policy.

Use `INFERENIX_<SETTING>` for shared values and
`INFERENIX_<SETTING>_<FAMILY>` for overrides. The suffix is the uppercase
runner family, regardless of which backend it uses. Source one trusted
config file, then resolve the settings the runner actually supports. A
shared name does not require every backend to implement that option.

Add a NixOS module here when a deployment needs boot-time service management.
Keep host paths and secrets out of engine derivations.

## Build and runtime trust

On Linux, build with `sandbox = true` and `sandbox-fallback = false`. Nix
isolates ordinary build jobs from the network. Fetchers are a separate
step: fixed-output derivations can use the network, and Nix checks their
output hash. A hash pins the bytes. It does not make the fetched code safe.

Build backend binaries from pinned sources. Do not run upstream installers
or updaters, package their download-and-execute flows, or add unsigned
binary caches. The Strata package builds and installs only the standalone
Inkling HIP target. The Inkling runner uses the UnbiasedStrata HTTP frontend,
not upstream Strata's application. New source pins need a review of the
build targets and the executable path the runner actually uses.

Users supply model weights, projectors, and draft tensors as host or Nix
store paths. Keep model acquisition outside this flake.

The Nix build sandbox does not apply to a running server, and a runtime
offline flag is not an egress sandbox. Build the launcher first and run
the built executable directly if you want to keep Nix acquisition and
launch separate. Use a service sandbox with outbound networking blocked
if you need enforced runtime isolation. Bind to loopback unless you mean
to expose the API. The runner sources `.env` as Bash; use only config
files you trust.
