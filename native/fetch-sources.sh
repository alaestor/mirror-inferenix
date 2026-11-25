#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=native/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=native/sources.sh
source "$native_dir/sources.sh"

usage() { echo 'Usage: native/fetch-sources.sh [qwen38|inkling2mini|all]'; }
case ${1:-all} in
  -h|--help) usage; exit 0 ;;
  qwen38|inkling2mini|all) model=${1:-all} ;;
  *) usage >&2; exit 2 ;;
esac
(( $# <= 1 )) || { usage >&2; exit 2; }
native_require curl jq sha256sum tar gzip patch flock mkdir mktemp mv rm cat
native_source_paths "$model"
native_source_urls "$model"

mkdir -p -- "$work/archives" "$work/sources"
exec 9>"$work/fetch.lock"
flock 9
scratch=$(mktemp -d -- "$work/.fetch.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

archive() {
  local name=$1 hash=$2 url=$3 dest
  dest="$work/archives/$hash.tar.gz"
  if [[ -f $dest ]]; then
    if ! printf '%s  %s\n' "$hash" "$dest" | sha256sum --status --check; then
      native_fail "Checksum failed for $dest. Move it aside and rerun fetch-sources.sh."
    fi
    return
  fi
  echo "Fetching $name"
  curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
    --output "$scratch/download.tar.gz" "$url"
  if ! printf '%s  %s\n' "$hash" "$scratch/download.tar.gz" | sha256sum --status --check; then
    native_fail "Checksum failed for $name. The download was not saved."
    return
  fi
  mv -T -- "$scratch/download.tar.gz" "$dest"
}

unpack() {
  tar -xzf "$work/archives/$1.tar.gz" --strip-components=1 --no-same-owner -C "$2"
}

archive UnbiasedStrata "$upstream_sha" "$upstream_url"
archive llama.cpp "$llama_sha" "$llama_url"
if [[ ! -d $strata_src ]]; then
  mkdir "$scratch/strata"
  unpack "$upstream_sha" "$scratch/strata"
  mkdir -p "$scratch/strata/third_party/llama.cpp"
  unpack "$llama_sha" "$scratch/strata/third_party/llama.cpp"
  for patch_file in "${patches[@]}"; do
    patch --batch --forward --fuzz=0 -p1 -d "$scratch/strata" -i "$patch_file"
  done
  mv -T -- "$scratch/strata" "$strata_src"
fi
if [[ $model != qwen38 ]]; then
  archive 'Inkling 2 Mini' "$inkling_sha" "$inkling_url"
  if [[ ! -d $inkling_src ]]; then
    mkdir "$scratch/inkling"
    unpack "$inkling_sha" "$scratch/inkling"
    mv -T -- "$scratch/inkling" "$inkling_src"
  fi
fi
echo "Sources ready in $work/sources"
