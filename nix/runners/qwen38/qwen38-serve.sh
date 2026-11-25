# shellcheck shell=bash
strata_parse_env_args "$@"
set -- "${strata_launch_args[@]}"
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  echo 'Usage: serve [--env-file PATH] [MODEL.gguf PREPARED_DIR] [frontend options] [-- engine options]'
  exit 0
fi
load_qwen38_env
if (( $# )) && [[ $1 != -* ]]; then
  if (( $# < 2 )) || [[ $2 == -* || -z $2 ]]; then
    qwen38_fail 'A positional model path requires a prepared directory.'
  fi
  STRATA_MODEL=$1
  STRATA_PREPARED_DIR=$2
  shift 2
fi
qwen38_check_model "$STRATA_MODEL"
strata_configure_args "$@"

pack=$STRATA_PREPARED_DIR/pack
mtp=$STRATA_PREPARED_DIR/mtp
qwen38_check_pack pack "$pack" ||
  qwen38_warn 'Trying the supplied pack anyway. If the backend fails, check the model and pack or run prepare into a fresh directory.'
qwen38_warn_provenance "$pack" "$STRATA_MODEL"
draft_args=()
if [[ -d $mtp ]]; then
  qwen38_check_pack mtp "$mtp" ||
    qwen38_warn 'Trying the supplied draft pack anyway.'
  draft_args=(--mtp "$mtp" --spec 4)
else
  qwen38_warn "No draft pack at $mtp. Serving without MTP."
fi

export LLAMA_ARG_OFFLINE=1
qwen38_run "$qwen38_frontend" --engine strata --model "$STRATA_MODEL" \
  "${strata_server_args[@]}" -- \
  --native "$STRATA_MODEL" --pack "$pack" "${draft_args[@]}" \
  --expert-profile "$pack/expert-profile.bin" --expert-cache auto --prefill auto \
  --resident-experts --ple-io mmap \
  --vram-reserve-mib "${STRATA_QWEN38_VRAM_RESERVE_MIB:-4096}" \
  "${strata_engine_args[@]}"
