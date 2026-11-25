# shellcheck shell=bash
# Shared by the packaged launchers. .env is trusted shell configuration.
strata_parse_env_args() {
  strata_launch_args=()
  while (( $# )); do
    case $1 in
      --env-file)
        if (( $# < 2 )) || [[ -z $2 || $2 == -* ]]; then
          echo '--env-file requires a nonempty path.' >&2
          return 2
        fi
        INFERENIX_ENV_FILE=$2
        shift 2
        ;;
      --env-file=*)
        INFERENIX_ENV_FILE=${1#*=}
        if [[ -z $INFERENIX_ENV_FILE ]]; then
          echo '--env-file requires a nonempty path.' >&2
          return 2
        fi
        shift
        ;;
      --)
        strata_launch_args+=("$@")
        break
        ;;
      *) strata_launch_args+=("$1"); shift ;;
    esac
  done
}

inferenix_source_env() {
  local selected=${INFERENIX_ENV_FILE:-}
  local env_file=${selected:-.env}
  if [[ -f "$env_file" && -r "$env_file" ]]; then
    [[ $env_file == /* ]] || env_file=./$env_file
    # shellcheck disable=SC1090
    source "$env_file"
  elif [[ -n $selected || -e $env_file || -L $env_file ]]; then
    echo "Cannot read configuration file: $env_file" >&2
    return 1
  fi
}

# The family override wins over the shared key, including an explicit empty
# value. Clear the internal value when neither key is set.
inferenix_apply() {
  local family=$1 key=$2
  local shared="INFERENIX_$key" specific="INFERENIX_${key}_$family"
  local target=${3:-STRATA_$key}
  if [[ -v $specific ]]; then
    printf -v "$target" '%s' "${!specific}"
  elif [[ -v $shared ]]; then
    printf -v "$target" '%s' "${!shared}"
  else
    printf -v "$target" '%s' ""
  fi
}

inferenix_apply_frontend() {
  local key
  for key in HOST PORT TEMPERATURE TOP_P TOP_K MIN_P PRESENCE_PENALTY REPEAT_PENALTY; do
    inferenix_apply "$1" "$key"
  done
}

inferenix_apply_qwen() {
  local key
  inferenix_apply_frontend "$1"
  for key in MODEL CTX KV THREADS MMPROJ VISION_TOKENS; do
    inferenix_apply "$1" "$key"
  done
}

load_strata_env() {
  inferenix_source_env || return
  STRATA_ENGINE_KIND=poly
  inferenix_apply_qwen QWEN36
}

load_qwen38_env() {
  inferenix_source_env || return
  STRATA_ENGINE_KIND=flash
  inferenix_apply_qwen QWEN38
  inferenix_apply QWEN38 PREPARED_DIR
  inferenix_apply QWEN38 RAM_CAP_GIB
  inferenix_apply QWEN38 MTP_SOURCE STRATA_QWEN38_MTP_SOURCE
  inferenix_apply QWEN38 MEMORY_MAX STRATA_QWEN38_MEMORY_MAX
  inferenix_apply QWEN38 VRAM_RESERVE_MIB STRATA_QWEN38_VRAM_RESERVE_MIB
  STRATA_PREPARED_DIR=${STRATA_PREPARED_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/unbiased-strata/qwen38}
  STRATA_CTX=${STRATA_CTX:-8192}
  STRATA_RAM_CAP_GIB=${STRATA_RAM_CAP_GIB:-40}
  STRATA_VISION_TOKENS=${STRATA_VISION_TOKENS:-1024}
}

strata_configure_sampling() {
  strata_sampling_args=()
  local name flag
  while read -r name flag; do
    if [[ -n ${!name:-} ]]; then
      strata_sampling_args+=("$flag" "${!name}")
    fi
  done <<'SAMPLING'
STRATA_TEMPERATURE --temp
STRATA_TOP_P --top-p
STRATA_TOP_K --top-k
STRATA_MIN_P --min-p
STRATA_PRESENCE_PENALTY --presence-penalty
STRATA_REPEAT_PENALTY --repeat-penalty
SAMPLING
}

strata_configure_args() {
  strata_server_args=(--host "${STRATA_HOST:-127.0.0.1}" --port "${STRATA_PORT:-8080}")
  strata_configure_sampling
  strata_server_args+=("${strata_sampling_args[@]}")
  local kv=${STRATA_KV:-} kind=${STRATA_ENGINE_KIND:-poly}
  if [[ $kind == flash ]]; then
    kv=${kv:-q4_0}
  else
    kv=${kv:-q8_0}
  fi
  strata_engine_args=(--max-context "${STRATA_CTX:-32768}" --kv "$kv")
  if [[ $kind == flash && -n ${STRATA_RAM_CAP_GIB:-} ]]; then
    strata_engine_args+=(--resident-budget-gib "$STRATA_RAM_CAP_GIB")
  fi
  if [[ -n ${STRATA_MMPROJ:-} ]]; then
    strata_server_args+=(--mmproj "$STRATA_MMPROJ" --image-max-tokens "${STRATA_VISION_TOKENS:-1024}")
    if [[ $kind == flash ]]; then strata_engine_args+=(--vision); fi
  fi
  if [[ -n ${STRATA_THREADS:-} ]]; then
    strata_server_args+=(--threads "$STRATA_THREADS")
    if [[ $kind == flash ]]; then
      strata_engine_args+=(--pool-workers "$STRATA_THREADS")
    else
      strata_engine_args+=(--threads "$STRATA_THREADS")
    fi
  fi
  local engine=false arg
  while [[ $# -gt 0 ]]; do
    arg=$1
    shift
    if [[ $arg == -- && $engine == false ]]; then
      engine=true
    elif [[ $engine == true ]]; then
      strata_engine_args+=("$arg")
    elif [[ $arg == --ctx=* ]]; then
      strata_engine_args+=(--max-context "${arg#*=}")
    elif [[ $arg == --mmproj=* ]]; then
      strata_server_args+=("$arg")
      if [[ $kind == flash ]]; then strata_engine_args+=(--vision); fi
    elif [[ $arg == --ctx ]]; then
      [[ $# -gt 0 ]] || { echo "$arg requires a value" >&2; return 2; }
      strata_engine_args+=(--max-context "$1")
      shift
    elif [[ $arg == --image-max-tokens ]]; then
      [[ $# -gt 0 ]] || { echo "$arg requires a value" >&2; return 2; }
      strata_server_args+=(--image-max-tokens "$1")
      shift
    elif [[ $arg == --mmproj ]]; then
      [[ $# -gt 0 ]] || { echo "$arg requires a value" >&2; return 2; }
      strata_server_args+=(--mmproj "$1")
      if [[ $kind == flash ]]; then strata_engine_args+=(--vision); fi
      shift
    else
      strata_server_args+=("$arg")
    fi
  done
}
