#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=native/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'HELP'
Usage: native/run.sh {qwen38|inkling2mini} [--gpu gfx1100] [--env-file PATH] [runner options]
       native/run.sh qwen38 [--gpu gfx1100] {start|stop|status|logs} [runner options]
HELP
}
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
model=${1:-}
native_model "$model"
shift
gpu=gfx1100
if [[ ${1:-} == --gpu ]]; then
  gpu=${2:-}
  native_gpu "$gpu"
  shift 2
fi
build="$work/build/$gpu/$model"
runners=$repo/nix/runners
# shellcheck source=nix/runners/launcher-common.sh
source "$runners/launcher-common.sh"

require_build() {
  [[ -f $build/ready ]] || native_fail "No completed build for $model ($gpu). Run native/build.sh $model --gpu $gpu."
}

if [[ $model == inkling2mini ]]; then
  inkling2mini_frontend="$build/frontend/unbiased-strata"
  inkling2mini_engine="$build/engine/strata-inkling"
  inkling2mini_preflight() {
    require_build
    native_check_runtime "$inkling2mini_frontend" "$inkling2mini_engine"
  }
  # shellcheck source=nix/runners/inkling2mini/launch.sh
  source "$runners/inkling2mini/launch.sh"
  exit
fi

qwen38_frontend="$build/strata/unbiased-strata"
qwen38_engine="$build/strata/strata"
qwen38_run() {
  local device="$build/strata/strata-device" variable
  require_build
  for variable in LD_LIBRARY_PATH HIP_VISIBLE_DEVICES ROCR_VISIBLE_DEVICES CUDA_VISIBLE_DEVICES GPU_DEVICE_ORDINAL; do
    if [[ -v $variable ]]; then export "${variable?}"; fi
  done
  native_check_runtime "$qwen38_frontend" "$qwen38_engine" "$device"
  if ! "$device" >/dev/null; then
    native_fail "Qwen3.8 could not initialize its GPU. Check ROCm, device access, and the build target ($gpu)."
    return
  fi
  strata_service_run_local strata-qwen38.service \
    -p "MemoryMax=${STRATA_QWEN38_MEMORY_MAX:-48G}" -p MemorySwapMax=0 \
    "$BASH" "$runners/qwen38/memory-preflight.sh" "$@"
}
qwen38_serve() {
  # shellcheck source=nix/runners/qwen38/qwen38-inputs.sh
  source "$runners/qwen38/qwen38-inputs.sh"
  # shellcheck source=nix/runners/qwen38/qwen38-serve.sh
  source "$runners/qwen38/qwen38-serve.sh"
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then qwen38_serve "$@"; exit 0; fi
case ${1:-} in
  status|stop) native_require systemctl ;;
  logs) native_require journalctl ;;
  *) native_require systemctl systemd-run jq stat ;;
esac
# shellcheck source=nix/runners/service-launcher.sh
source "$runners/service-launcher.sh"
strata_service_dispatch_local strata-qwen38.service true qwen38_serve "$@"
