#!/usr/bin/env bash
set -euo pipefail

common=$(realpath -- "${1:?launcher-common.sh}")
launcher=$(realpath -- "${2:?launch.sh}")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd -- "$work"
unset INFERENIX_ENV_FILE INFERENIX_HOST INFERENIX_PORT INFERENIX_CTX
unset INFERENIX_MODEL_INKLING2MINI INFERENIX_CTX_INKLING2MINI INFERENIX_DRAFT_INKLING2MINI INFERENIX_VRAM_RESERVE_MIB_INKLING2MINI

printf '#!%s\n' "$BASH" > front
cat >> front <<'STUB'
[[ ${LLAMA_ARG_OFFLINE:-} == 1 ]] || exit 1
printf '%s\n' "$@"
STUB
chmod +x front
touch 'model file.gguf' draft.safetensors
cat > .env <<'ENV'
INFERENIX_MODEL_INKLING2MINI="$PWD/model file.gguf"
INFERENIX_CTX_INKLING2MINI=38912
INFERENIX_CTX=163840
ENV

run() (
  # shellcheck disable=SC2034
  inkling2mini_frontend="$PWD/front"
  # shellcheck disable=SC2034
  inkling2mini_engine="$PWD/front"
  # shellcheck disable=SC1090
  source "$common"
  # shellcheck disable=SC1090
  source "$launcher"
)

run > actual
printf '%s\n' --engine "$PWD/front" -m "$PWD/model file.gguf" --alias inkling-2-mini \
  --host 127.0.0.1 --port 8080 -- --native "$PWD/model file.gguf" --max-context 38912 \
  --parallel 1 --vram-reserve-mib 4096 > expected
diff -u expected actual

cat > 'other profile' <<'ENV'
INFERENIX_MODEL_INKLING2MINI="$PWD/model file.gguf"
INFERENIX_DRAFT_INKLING2MINI="$PWD/draft.safetensors"
INFERENIX_HOST=localhost
INFERENIX_VRAM_RESERVE_MIB_INKLING2MINI=2048
ENV
run --env-file 'other profile' --temp 0 -- --max-context 8192 --draft dspark > actual
printf '%s\n' --engine "$PWD/front" -m "$PWD/model file.gguf" --alias inkling-2-mini \
  --host localhost --port 8080 --temp 0 -- --native "$PWD/model file.gguf" --max-context 4096 \
  --parallel 1 --vram-reserve-mib 2048 --dspark "$PWD/draft.safetensors" --max-context 8192 --draft dspark > expected
diff -u expected actual

cat > "inferenix profile" <<'ENV'
INFERENIX_MODEL_INKLING2MINI="$PWD/model file.gguf"
INFERENIX_CTX=6144
INFERENIX_CTX_INKLING2MINI=7168
INFERENIX_PORT=8090
INFERENIX_TEMPERATURE_INKLING2MINI=0
ENV
INFERENIX_ENV_FILE="$PWD/inferenix profile" run > actual
printf '%s\n' --engine "$PWD/front" -m "$PWD/model file.gguf" --alias inkling-2-mini \
  --host 127.0.0.1 --port 8090 --temp 0 -- --native "$PWD/model file.gguf" --max-context 7168 \
  --parallel 1 --vram-reserve-mib 4096 > expected
diff -u expected actual

fails_with() {
  local expected=$1
  shift
  if (run "$@") > actual 2>&1; then
    echo "Unexpected launch success: $*" >&2
    exit 1
  fi
  grep -Fq "$expected" actual || { cat actual >&2; exit 1; }
}
fails_with 'Cannot read configuration' --env-file missing
mv -- draft.safetensors unavailable
fails_with 'INFERENIX_DRAFT_INKLING2MINI' --env-file 'other profile'
mv -- 'model file.gguf' unavailable.gguf
fails_with 'INFERENIX_MODEL_INKLING2MINI'
