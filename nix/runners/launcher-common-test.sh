#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=nix/launcher-common.sh
source "$1"
work=$(mktemp -d)
trap 'rm -r "$work"' EXIT
cd "$work"
export INFERENIX_ENV_FILE="$work/config.env"
touch "$INFERENIX_ENV_FILE"
unset INFERENIX_CTX INFERENIX_KV INFERENIX_THREADS INFERENIX_MMPROJ
load_strata_env
strata_configure_args
[[ ${strata_server_args[*]} == '--host 127.0.0.1 --port 8080' ]]
[[ ${strata_engine_args[*]} == '--max-context 32768 --kv q8_0' ]]
# Explicit KV formats are passed through, not silently remapped.
INFERENIX_KV=q4_0
load_strata_env
strata_configure_args
[[ ${strata_engine_args[*]} == '--max-context 32768 --kv q4_0' ]]
unset INFERENIX_KV
INFERENIX_MMPROJ='/models/a projector.gguf'
load_strata_env
strata_configure_args --ctx 8192 --image-max-tokens 256 -- --lookup 0
[[ ${strata_server_args[*]} == '--host 127.0.0.1 --port 8080 --mmproj /models/a projector.gguf --image-max-tokens 1024 --image-max-tokens 256' ]]
[[ ${strata_engine_args[*]} == '--max-context 32768 --kv q8_0 --max-context 8192 --lookup 0' ]]
for flag in --ctx --mmproj --image-max-tokens; do
  if strata_configure_args "$flag" 2>/dev/null; then echo "missing $flag value accepted" >&2; exit 1; fi
done
INFERENIX_ENV_FILE="$work/missing.env"
if load_strata_env 2>/dev/null; then echo 'missing config accepted' >&2; exit 1; fi
INFERENIX_ENV_FILE="$work/config.env"
INFERENIX_MODEL_QWEN38='/models/flash next.gguf'
unset INFERENIX_MMPROJ
INFERENIX_MMPROJ_QWEN38='/models/flash projector.gguf'
INFERENIX_THREADS=4
load_qwen38_env
strata_configure_args --mmproj '/override/projector.gguf' -- --ple-io mmap
[[ $STRATA_MODEL == '/models/flash next.gguf' ]]
[[ ${strata_server_args[*]} == '--host 127.0.0.1 --port 8080 --mmproj /models/flash projector.gguf --image-max-tokens 1024 --threads 4 --mmproj /override/projector.gguf' ]]
[[ ${strata_engine_args[*]} == '--max-context 8192 --kv q4_0 --resident-budget-gib 40 --vision --pool-workers 4 --vision --ple-io mmap' ]]
INFERENIX_KV=q4_0
INFERENIX_MMPROJ_QWEN38=
load_qwen38_env
strata_configure_args --ctx=2048 --mmproj='/pictures/a b.gguf' --image-max-tokens=128
[[ ${strata_server_args[*]} == '--host 127.0.0.1 --port 8080 --threads 4 --mmproj=/pictures/a b.gguf --image-max-tokens=128' ]]
[[ ${strata_engine_args[*]} == '--max-context 8192 --kv q4_0 --resident-budget-gib 40 --pool-workers 4 --max-context 2048 --vision' ]]
# The trusted config overrides inherited variables and preserves paths with spaces.
cat > "$INFERENIX_ENV_FILE" <<'CONFIG'
INFERENIX_MODEL='/models/local model.gguf'
INFERENIX_CTX=4096
CONFIG
INFERENIX_MODEL=/ignored.gguf
load_strata_env
[[ $STRATA_MODEL == '/models/local model.gguf' && $STRATA_CTX == 4096 ]]
# Shared sampling overrides preserve zero and precede CLI overrides, never engine options.
cat >> "$INFERENIX_ENV_FILE" <<'CONFIG'
INFERENIX_TEMPERATURE=0
INFERENIX_TOP_P=0.8
INFERENIX_TOP_K=20
INFERENIX_MIN_P=0
INFERENIX_PRESENCE_PENALTY=0
INFERENIX_REPEAT_PENALTY=1
CONFIG
load_strata_env
strata_configure_args --temp 0.6 -- --lookup 0
[[ ${strata_server_args[*]} == *'--temp 0 --top-p 0.8 --top-k 20 --min-p 0 --presence-penalty 0 --repeat-penalty 1'*'--temp 0.6' ]]
[[ ${strata_engine_args[*]} != *--temp* ]]
echo 'INFERENIX_TEMPERATURE=' >> "$INFERENIX_ENV_FILE"
load_strata_env
strata_configure_sampling
[[ ${strata_sampling_args[*]} != *--temp* ]]
# CLI config selection overrides the environment and preserves remaining arguments.
cat > "$work/alternate config.env" <<'CONFIG'
INFERENIX_MODEL_QWEN38='/models/alternate flash.gguf'
INFERENIX_CTX_QWEN38=2048
CONFIG
echo 'INFERENIX_PORT=9091' > .env
strata_parse_env_args '/models/explicit model.gguf' --env-file "$work/alternate config.env" '/packs/explicit pack' --ctx 1024 -- --env-file engine-value
[[ $INFERENIX_ENV_FILE == "$work/alternate config.env" ]]
[[ ${#strata_launch_args[@]} == 7 ]]
[[ ${strata_launch_args[0]} == '/models/explicit model.gguf' && ${strata_launch_args[1]} == '/packs/explicit pack' ]]
[[ ${strata_launch_args[5]} == --env-file && ${strata_launch_args[6]} == engine-value ]]
load_qwen38_env
[[ $STRATA_MODEL == '/models/alternate flash.gguf' && $STRATA_CTX == 2048 && -z $STRATA_PORT ]]
strata_parse_env_args --env-file="$work/config.env" --temp 0.6
[[ $INFERENIX_ENV_FILE == "$work/config.env" && ${strata_launch_args[*]} == '--temp 0.6' ]]
for form in missing empty equals option; do
  case $form in
    missing) args=(--env-file) ;;
    empty) args=(--env-file '') ;;
    equals) args=(--env-file=) ;;
    option) args=(--env-file --temp 0.6) ;;
  esac
  if strata_parse_env_args "${args[@]}" 2>/dev/null; then
    echo "invalid env-file form accepted: $form" >&2; exit 1
  fi
done
strata_parse_env_args --env-file "$work/missing.env"
if load_strata_env 2>/dev/null; then echo 'missing CLI config accepted' >&2; exit 1; fi
cat > "$work/inferenix.env" <<'CONFIG'
INFERENIX_CTX=12288
INFERENIX_CTX_QWEN38=6144
INFERENIX_MODEL="/models/default.gguf"
INFERENIX_MODEL_QWEN38="/nix/store/example-output/flash shard.gguf"
INFERENIX_MMPROJ="/models/shared projector.gguf"
INFERENIX_MMPROJ_QWEN38=
INFERENIX_PORT_QWEN38=8090
CONFIG
INFERENIX_ENV_FILE="$work/inferenix.env"
(
  load_strata_env
  [[ $STRATA_MODEL == /models/default.gguf && $STRATA_CTX == 12288 ]]
)
(
  load_qwen38_env
  [[ $STRATA_MODEL == "/nix/store/example-output/flash shard.gguf" && $STRATA_CTX == 6144 ]]
  strata_configure_args --ctx 8192
  [[ ${strata_server_args[*]} == *"--port 8090"* && ${strata_server_args[*]} != *--mmproj* ]]
  [[ ${strata_engine_args[*]} == "--max-context 6144"*"--max-context 8192" ]]
)
echo 'PASS: engine routing, images, sampling, config selection, invalid values/config'
