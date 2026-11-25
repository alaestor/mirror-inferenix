#!/usr/bin/env bash
set -euo pipefail
common=$1
inputs=$2
prepare=$3
serve=$4
packaged_prepare=$5
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"
mkdir 'config data' tools data raw
export INFERENIX_ENV_FILE="$PWD/config data/empty"
touch "$INFERENIX_ENV_FILE"
printf 'weight data' > 'model shard.gguf'
printf 'manifest without pinned hash' > raw/mtp-manifest.json
printf 'profile' > data/expert-profile.bin
printf 'vocab' > data/draft_vocab.bin

run_prepare() (
  set -e
  source "$common"
  source "$inputs"
  qwen38_pack_tools=tools
  qwen38_pack_data=data
  python() {
    local tool=$1 in=$3 out=${*: -1}
    case $tool in
      tools/iq_pack.py)
        [[ $in == 'model shard.gguf' ]]
        mkdir "$out"
        printf data > "$out/dense.bin"
        if [[ ${FAIL_PACK:-} ]]; then return 42; fi
        printf data > "$out/index.txt"
        printf data > "$out/native_experts.txt"
        if [[ ${RACE_PACK:-} ]]; then
          local staging=${out%/*}
          mkdir "${staging%/*}/pack"
          printf winner > "${staging%/*}/pack/dense.bin"
        fi
        ;;
      tools/mtp_pack.py)
        [[ $in == raw ]]
        printf data > "$out"
        ;;
      tools/mtp_rt.py)
        [[ -s $in ]]
        mkdir "$out"
        printf data > "$out/dense.bin"
        printf data > "$out/dense.txt"
        printf data > "$out/experts.bin"
        ;;
      *) return 99 ;;
    esac
  }
  set -- "$@"
  source "$prepare"
)
run_serve() (
  source "$common"
  source "$inputs"
  qwen38_frontend=mock-frontend
  qwen38_run() { printf '%s\n' "$@"; }
  set -- "$@"
  source "$serve"
)
expect_failure() {
  local status=0
  "$@" > stdout 2> stderr || status=$?
  [[ $status != 0 ]]
}

# The installed wrapper gives actionable errors before creating outputs.
expect_failure "$packaged_prepare"
grep -F 'readable, nonempty model GGUF' stderr
expect_failure "$packaged_prepare" 'model shard.gguf' missing nonexistent
grep -F 'Draft source is not a readable GGUF or directory with mtp-manifest.json' stderr
[[ ! -e missing ]]

# Raw draft tensors with a caller-supplied manifest go straight to the converter.
run_prepare 'model shard.gguf' 'prepared data' raw > stdout
[[ -s 'prepared data/pack/dense.bin' && -s 'prepared data/mtp/draft_vocab.bin' ]]
[[ ! -e 'prepared data/mtp-q2_0.gguf' ]]
# Existing outputs stay intact; a rerun never needs to open the draft source.
run_prepare 'model shard.gguf' 'prepared data' nonexistent > stdout
grep -F 'No packs to prepare' stdout

# A failed converter publishes no partial pack or scratch directory.
set +e
FAIL_PACK=1 run_prepare 'model shard.gguf' failed raw > stdout 2> stderr
status=$?
set -e
[[ $status == 42 ]]
[[ -d failed && -z $(ls -A failed) ]]

# Another preparer can publish after the initial check. Keep that pack intact.
set +e
RACE_PACK=1 run_prepare 'model shard.gguf' racing > stdout 2> stderr
status=$?
set -e
[[ $status == 2 && $(cat racing/pack/dense.bin) == winner ]]
[[ $(ls -A racing) == pack && ! -s stdout ]]
grep -F 'Could not publish' stderr

# Prepare may produce a pack without a draft, and can fill in the draft later.
run_prepare 'model shard.gguf' nodraft > stdout 2> stderr
grep -F 'No draft source supplied' stderr
[[ -s nodraft/pack/dense.bin && ! -e nodraft/mtp ]]
printf 'existing' > nodraft/pack/dense.bin
printf 'packed MTP GGUF' > 'packed draft.gguf'
run_prepare 'model shard.gguf' nodraft 'packed draft.gguf' > stdout
[[ $(cat nodraft/pack/dense.bin) == existing && -s nodraft/mtp/experts.bin ]]

# The backend gets usable arguments even when optional inputs are missing.
run_serve 'model shard.gguf' missing --mmproj 'vision data.gguf' -- --spec 2 > stdout 2> stderr
grep -Fx 'mock-frontend' stdout
grep -Fx 'model shard.gguf' stdout
grep -Fx 'missing/pack' stdout
grep -Fx 'vision data.gguf' stdout
grep -Fx -- '--vision' stdout
if grep -Fxq -- '--mtp' stdout; then exit 1; fi
grep -F 'Trying the supplied pack anyway' stderr
grep -F 'Serving without MTP' stderr
run_serve 'model shard.gguf' 'prepared data' > stdout 2> stderr
grep -Fx 'prepared data/mtp' stdout
[[ ! -s stderr ]]

# Optional provenance is advisory, including for a renamed or replaced model.
printf '{"source_shards":[{"name":"model shard.gguf","size":1}]}' > 'prepared data/pack/conversions.json'
run_serve 'model shard.gguf' 'prepared data' > stdout 2> stderr
grep -F 'Shard size differs from the pack record' stderr
printf '{"source_shards":[{"name":"some other model.gguf","size":1}]}' > 'prepared data/pack/conversions.json'
run_serve 'model shard.gguf' 'prepared data' > stdout 2> stderr
grep -F 'Pack was prepared for some other model.gguf' stderr
grep -Fx 'mock-frontend' stdout
