# shellcheck shell=bash
qwen38_warn() { printf 'qwen38: warning: %s\n' "$*" >&2; }
qwen38_fail() { printf 'qwen38: %s\n' "$*" >&2; return 2; }

qwen38_check_model() {
  if [[ -z $1 || ! -f $1 || ! -r $1 || ! -s $1 ]]; then
    qwen38_fail "Set INFERENIX_MODEL_QWEN38 or pass a readable, nonempty model GGUF. Got: ${1:-<unset>}"
    return
  fi
  if [[ $1 != *.gguf ]]; then
    qwen38_warn "Model path does not end in .gguf: $1. The backend will check its format."
  fi
}

qwen38_check_pack() {
  local kind=$1 path=$2 file
  local -a files
  case $kind in
    pack) files=(dense.bin index.txt native_experts.txt expert-profile.bin) ;;
    mtp) files=(dense.bin dense.txt experts.bin draft_vocab.bin) ;;
    *) return 2 ;;
  esac
  if [[ ! -d $path ]]; then
    qwen38_warn "No $kind directory at $path."
    return 1
  fi
  local status=0
  for file in "${files[@]}"; do
    if [[ ! -f $path/$file || ! -r $path/$file || ! -s $path/$file ]]; then
      qwen38_warn "Expected readable, nonempty $kind file: $path/$file"
      status=1
    fi
  done
  return "$status"
}

# Current packs record shard names and sizes. Older packs may omit this file.
# These are diagnostics only: the backend also checks the files it opens.
qwen38_warn_provenance() {
  local pack=$1 model=$2 shards first name size actual dir=.
  local meta=$pack/conversions.json
  [[ -f $meta ]] || return 0
  if ! shards=$(jq -er '.source_shards | if type == "array" then .[] else empty end |
      select(.name | type == "string") | select(.size | type == "number") | [.name, .size] | @tsv' "$meta" 2>/dev/null); then
    qwen38_warn "Could not read the source shard list from $meta."
    return
  fi
  first=${shards%%$'\t'*}
  if [[ ${model##*/} != "$first" ]]; then
    qwen38_warn "Pack was prepared for $first, not ${model##*/}. Trying the supplied pack anyway."
    return
  fi
  if [[ $model == */* ]]; then dir=${model%/*}; fi
  while IFS=$'\t' read -r name size; do
    [[ -n $name && $name != */* ]] || continue
    if ! actual=$(stat -Lc '%s' -- "$dir/$name" 2>/dev/null); then
      qwen38_warn "Pack lists a model shard that cannot be read: $dir/$name"
    elif [[ $actual != "$size" ]]; then
      qwen38_warn "Shard size differs from the pack record: $dir/$name ($actual bytes, expected $size)."
    fi
  done <<< "$shards"
}
