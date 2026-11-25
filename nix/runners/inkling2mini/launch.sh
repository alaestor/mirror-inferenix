# shellcheck shell=bash
strata_parse_env_args "$@"
# shellcheck disable=SC2154
set -- "${strata_launch_args[@]}"
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  echo "Usage: ${0##*/} [--env-file PATH] [front-end options] [-- engine options]"
  exit 0
fi

inferenix_source_env || exit $?
inferenix_apply_frontend INKLING2MINI
inferenix_apply INKLING2MINI MODEL STRATA_INKLING2MINI_MODEL
inferenix_apply INKLING2MINI CTX STRATA_INKLING2MINI_CTX
inferenix_apply INKLING2MINI DRAFT STRATA_INKLING2MINI_DRAFT
inferenix_apply INKLING2MINI VRAM_RESERVE_MIB STRATA_INKLING2MINI_VRAM_RESERVE_MIB
strata_configure_sampling

model=${STRATA_INKLING2MINI_MODEL:-}
if [[ "$model" != *.gguf || ! -f "$model" || ! -r "$model" ]]; then
  echo "Set INFERENIX_MODEL_INKLING2MINI to a readable Inkling 2 Mini GGUF." >&2
  exit 1
fi

if declare -F inkling2mini_preflight >/dev/null; then inkling2mini_preflight; fi

# shellcheck disable=SC2154
if [[ ! -x "$inkling2mini_frontend" || ! -x "$inkling2mini_engine" ]]; then
  echo "Missing Inkling engine or frontend." >&2
  exit 1
fi

front_args=()
engine_args=()
while (( $# )); do
  if [[ "$1" == -- ]]; then
    shift
    engine_args=("$@")
    break
  fi
  front_args+=("$1")
  shift
done

draft_args=()
if [[ -n ${STRATA_INKLING2MINI_DRAFT:-} ]]; then
  if [[ ! -f "$STRATA_INKLING2MINI_DRAFT" || ! -r "$STRATA_INKLING2MINI_DRAFT" ]]; then
    echo "INFERENIX_DRAFT_INKLING2MINI must point to a readable native Strata drafter." >&2
    exit 1
  fi
  draft_args=(--dspark "$STRATA_INKLING2MINI_DRAFT")
fi

# The front end uses only the supplied local model. Keep llama.cpp offline.
export LLAMA_ARG_OFFLINE=1

exec "$inkling2mini_frontend" --engine "$inkling2mini_engine" -m "$model" --alias inkling-2-mini \
  --host "${STRATA_HOST:-127.0.0.1}" --port "${STRATA_PORT:-8080}" "${strata_sampling_args[@]}" "${front_args[@]}" -- \
  --native "$model" --max-context "${STRATA_INKLING2MINI_CTX:-4096}" --parallel 1 \
  --vram-reserve-mib "${STRATA_INKLING2MINI_VRAM_RESERVE_MIB:-4096}" \
  "${draft_args[@]}" "${engine_args[@]}"
