#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=native/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=native/sources.sh
source "$native_dir/sources.sh"

usage() { echo 'Usage: native/build.sh {qwen38|inkling2mini} [--gpu gfx1100] [--jobs 4]'; }
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
model=${1:-}
native_model "$model"
shift
gpu=gfx1100 jobs=4
while (( $# )); do
  case $1 in
    --gpu|--jobs)
      if [[ -z ${2:-} ]]; then usage >&2; exit 2; fi
      if [[ $1 == --gpu ]]; then gpu=$2; else jobs=$2; fi
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
native_gpu "$gpu"
[[ $jobs =~ ^[1-9][0-9]*$ ]] || native_fail 'Use a positive number for --jobs.'
native_require cmake ninja jq sha256sum cat flock grep mkdir rm
native_check_cmake
native_source_paths "$model"
if [[ ! -f $strata_src/CMakeLists.txt || ! -f $strata_src/third_party/llama.cpp/ggml/CMakeLists.txt ||
  ( $model == inkling2mini && ! -f $inkling_src/engine/src/inkling2/CMakeLists.txt ) ]]; then
  native_fail "Pinned sources are missing. Run native/fetch-sources.sh $model first."
fi

build="$work/build/$gpu/$model"
mkdir -p -- "$build"
exec 9>"$build/build.lock"
flock -n 9 || native_fail "Another build for $model on $gpu is running."

hip_flags=()
if [[ $model == inkling2mini ]]; then
  if [[ -n ${INFERENIX_NATIVE_HIPCC:-} ]]; then
    hip_cxx=$(command -v "$INFERENIX_NATIVE_HIPCC") ||
      native_fail "Cannot find the compiler set by INFERENIX_NATIVE_HIPCC: $INFERENIX_NATIVE_HIPCC. Fix the path or unset it for automatic discovery."
    if [[ $hip_cxx != /* ]]; then hip_cxx="$PWD/$hip_cxx"; fi
    hip_flags+=("-DSTRATA_HIP_CXX=$hip_cxx")
  fi
elif [[ -n ${ROCM_PATH:-} ]]; then
  hip_flags+=("-DCMAKE_HIP_COMPILER_ROCM_ROOT=$ROCM_PATH")
fi

log="$build/dependencies.log"
if ! {
  cmake --fresh -S "$native_dir/dependency-check" -B "$build/dependency-check" -G Ninja \
    "-DSTRATA_CHECK_MODEL=$model" "-DCMAKE_HIP_ARCHITECTURES=$gpu" "${hip_flags[@]}" &&
    cmake --build "$build/dependency-check"
} >"$log" 2>&1; then
  # The small probe cannot cover every compiler wrapper or ROCm layout.
  # Let the real configuration and build decide whether they can proceed.
  printf 'inferenix: warning: compiler or ROCm SDK check did not pass for %s (%s). Trying the build anyway. See %s.\n' \
    "$model" "$gpu" "$log" >&2
  grep -F 'Strata dependency:' "$log" >&2 || true
fi

# Never let a failed rebuild look ready to launch. Use --fresh so changing a
# pinned source, compiler or SDK does not leave an old CMake cache in charge.
rm -f -- "$build/ready"
configure() {
  local component=$1 source=$2 log status
  shift 2
  log="$build/configure-$component.log"
  cmake --fresh -G Ninja -DCMAKE_BUILD_TYPE=Release -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -S "$source" -B "$build/$component" "$@" >"$log" 2>&1 || {
    status=$?
    native_fail "Could not configure $model $component. See $log and native/README.md." || return "$status"
  }
}
frontend_flags=(-DSTRATA_ENABLE_CUDA=OFF -DSTRATA_BUILD_TESTS=OFF -DSTRATA_PORTABLE=ON -DBUILD_SHARED_LIBS=OFF)
if [[ $model == qwen38 ]]; then
  configure strata "$strata_src" "${frontend_flags[@]}" \
    -DSTRATA_ENABLE_HIP=ON "-DCMAKE_HIP_ARCHITECTURES=$gpu" "${hip_flags[@]}"
  cmake --build "$build/strata" --parallel "$jobs" --target unbiased-strata strata strata-device native_expert_parity
else
  configure engine "$inkling_src/engine/src/inkling2" \
    -DSTRATA_ENABLE_HIP=ON "-DSTRATA_HIP_ARCHS=$gpu" "${hip_flags[@]}"
  configure frontend "$strata_src" "${frontend_flags[@]}" -DSTRATA_ENABLE_HIP=OFF
  cmake --build "$build/engine" --parallel "$jobs" --target strata-inkling
  "$build/engine/strata-inkling" --version
  cmake --build "$build/frontend" --parallel "$jobs" --target unbiased-strata
fi
printf '%s\n' "$strata_src" > "$build/ready"
echo "Built $model for $gpu in $build"
