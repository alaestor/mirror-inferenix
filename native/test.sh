#!/usr/bin/env bash
# Test the native entry points without ROCm, network access, or model weights.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
fixture="$scratch/inferenix test"
mkdir -p "$fixture/native" "$scratch/bin"
cp "$here"/{common,sources,fetch-sources,build,prepare-qwen38,run}.sh "$fixture/native/"
cp -r "$here/../pkgs" "$here/../nix" "$fixture/"
export PATH="$scratch/bin:$PATH" CALLS="$scratch/calls" PROBE_FAIL=0 BUILD_FAIL=0 CONFIGURE_FAIL=0
unset INFERENIX_ENV_FILE INFERENIX_NATIVE_HIPCC ROCM_PATH

printf '#!%s\n' "$BASH" > "$scratch/bin/cmake"
cat >> "$scratch/bin/cmake" <<'MOCK'
set -eu
if [[ $1 == --version ]]; then echo 'cmake version 3.24.0'; exit 0; fi
printf '%s\n' "$*" >> "$CALLS"
if [[ $* == *dependency-check* && $PROBE_FAIL == 1 ]]; then
  echo 'Strata dependency: missing hipBLAS development package.'
  echo 'Raw CMake diagnostic'
  exit 1
fi
if [[ $1 == --fresh && $* != *dependency-check* && $CONFIGURE_FAIL == 1 ]]; then
  echo 'Raw configure diagnostic'
  exit 8
fi
if [[ $1 == --build && $* != *dependency-check* ]]; then exit "$BUILD_FAIL"; fi
MOCK
printf '#!%s\nexit 0\n' "$BASH" > "$scratch/bin/ninja"
printf '#!%s\n' "$BASH" > "$scratch/bin/curl"
cat >> "$scratch/bin/curl" <<'MOCK'
while [[ $1 != --output ]]; do shift; done
printf 'bad archive' > "$2"
MOCK
chmod +x "$scratch/bin/"{cmake,ninja,curl}
cd -- "$fixture"

run() {
  local expected=$1 actual=0
  shift
  : > "$CALLS"
  "$@" > "$scratch/output" 2>&1 || actual=$?
  if [[ $actual != "$expected" ]]; then
    cat "$scratch/output" >&2
    printf 'Expected exit %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
    exit 1
  fi
}
says() { grep -Fq -- "$1" "$scratch/output" || { cat "$scratch/output" >&2; return 1; }; }
silent_about() {
  ! grep -F -- "$1" "$scratch/output" || { cat "$scratch/output" >&2; return 1; }
}

# Missing required commands are reported together before CMake runs.
mkdir "$scratch/minimal"
for tool in bash dirname cmake ninja; do ln -s "$(command -v "$tool")" "$scratch/minimal/$tool"; done
run 1 env PATH="$scratch/minimal" native/build.sh qwen38
says 'Missing commands on PATH: jq sha256sum'
[[ ! -s $CALLS ]]

# Do not compile or try to download implicitly when sources are absent.
run 1 native/build.sh qwen38 --gpu gfx1201
says 'Run native/fetch-sources.sh qwen38 first'
[[ ! -s $CALLS ]]
run 1 native/fetch-sources.sh qwen38
says 'Checksum failed for UnbiasedStrata'
[[ -z $(ls -A native/.work/archives) && -z $(ls -A native/.work/sources) ]]

# shellcheck source=native/common.sh
source "$fixture/native/common.sh"
# shellcheck source=native/sources.sh
source "$fixture/native/sources.sh"
native_source_paths qwen38
mkdir -p "$strata_src/third_party/llama.cpp/ggml"
touch "$strata_src/CMakeLists.txt" "$strata_src/third_party/llama.cpp/ggml/CMakeLists.txt"
build=native/.work/build/gfx1201/qwen38
run 0 native/build.sh qwen38 --gpu gfx1201 --jobs 2
silent_about 'inferenix: warning:'
grep -Fq -- '-DFETCHCONTENT_FULLY_DISCONNECTED=ON' "$CALLS"
grep -Fq -- '--parallel 2 --target unbiased-strata strata strata-device native_expert_parity' "$CALLS"
[[ -e $build/ready ]]

# A failed probe is advisory. The real build may work with this toolchain.
export PROBE_FAIL=1
run 0 native/build.sh qwen38 --gpu gfx1201
says 'Trying the build anyway.'
says 'missing hipBLAS development package'
silent_about 'Raw CMake diagnostic'
grep -Fq 'Raw CMake diagnostic' "$build/dependencies.log"
[[ -e $build/ready ]]

# A real configure failure stops the build and points to the full log.
export PROBE_FAIL=0 CONFIGURE_FAIL=1
run 8 native/build.sh qwen38 --gpu gfx1201
says 'configure-strata.log'
silent_about 'Raw configure diagnostic'
grep -Fq 'Raw configure diagnostic' "$build/configure-strata.log"
[[ ! -e $build/ready ]]
if grep -Fq -- '--target' "$CALLS"; then exit 1; fi

export CONFIGURE_FAIL=0
run 0 native/build.sh qwen38 --gpu gfx1201
export BUILD_FAIL=7
run 7 native/build.sh qwen38 --gpu gfx1201
[[ ! -e $build/ready ]]
run 0 native/run.sh qwen38 --gpu gfx1201 --help

# Leave compiler discovery to CMake unless the caller names a compiler.
native_source_paths inkling2mini
mkdir -p "$inkling_src/engine/src/inkling2"
touch "$inkling_src/engine/src/inkling2/CMakeLists.txt"
run 8 env CONFIGURE_FAIL=1 native/build.sh inkling2mini
says 'configure-engine.log'
if grep -Fq -- '-DSTRATA_HIP_CXX=' "$CALLS"; then exit 1; fi
run 1 env INFERENIX_NATIVE_HIPCC="$scratch/missing-compiler" native/build.sh inkling2mini
says 'Fix the path or unset it for automatic discovery.'
[[ ! -s $CALLS ]]

# Reusing packs does not require Python or staged packing tools.
printf gguf > 'test model.gguf'
mkdir -p packs/pack
for file in dense.bin index.txt native_experts.txt expert-profile.bin; do printf pack > "packs/pack/$file"; done
run 0 native/prepare-qwen38.sh 'test model.gguf' packs
says 'No packs to prepare'
echo 'PASS: native fetch integrity, build preflight, and local pack reuse'
