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
native_require git jq sha256sum tar patch flock mkdir mktemp mv rm cat
native_source_paths "$model"
native_source_urls "$model"

mkdir -p -- "$work/sources"
exec 9>"$work/fetch.lock"
flock 9
scratch=$(mktemp -d -- "$work/.fetch.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT

fetch_commit() {
  local git_dir=$1 name=$2 url=$3 rev=$4 actual
  echo "Fetching $name at $rev"
  git --git-dir="$git_dir" init --quiet --bare --template= --object-format=sha1
  GIT_ALLOW_PROTOCOL=https GIT_TERMINAL_PROMPT=0 \
    git --git-dir="$git_dir" -c fetch.fsckObjects=true fetch --quiet --depth=1 \
      --no-tags --no-recurse-submodules -- "$url" "$rev"
  if ! actual=$(git --git-dir="$git_dir" rev-parse --verify 'FETCH_HEAD^{commit}') || [[ $actual != "$rev" ]]; then
    native_fail "Fetched commit for $name does not match the pin $rev."
    return
  fi
}

export_tree() {
  local git_dir=$1 rev=$2 dest=$3
  mkdir -p -- "$dest"
  # Use the committed archive attributes, independent of host Git settings.
  GIT_ATTR_NOSYSTEM=1 git --git-dir="$git_dir" -c core.attributesFile=/dev/null \
    -c tar.umask=0002 archive --format=tar "$rev" |
    tar -xf - --no-same-owner -C "$dest"
}

if [[ ! -d $strata_src ]]; then
  fetch_commit "$scratch/upstream.git" UnbiasedStrata "$upstream_url" "$upstream_rev"
  gitlink=$(git --git-dir="$scratch/upstream.git" ls-tree "$upstream_rev" -- third_party/llama.cpp)
  [[ $gitlink == "160000 commit $llama_rev"$'\tthird_party/llama.cpp' ]] ||
    native_fail "UnbiasedStrata's third_party/llama.cpp gitlink does not match the pin $llama_rev."
  fetch_commit "$scratch/llama.git" llama.cpp "$llama_url" "$llama_rev"
  export_tree "$scratch/upstream.git" "$upstream_rev" "$scratch/strata"
  export_tree "$scratch/llama.git" "$llama_rev" "$scratch/strata/third_party/llama.cpp"
  for patch_file in "${patches[@]}"; do
    patch --batch --forward --fuzz=0 -p1 -d "$scratch/strata" -i "$patch_file"
  done
  mv -T -- "$scratch/strata" "$strata_src"
fi
if [[ $model != qwen38 && ! -d $inkling_src ]]; then
  fetch_commit "$scratch/inkling.git" 'Inkling 2 Mini' "$inkling_url" "$inkling_rev"
  export_tree "$scratch/inkling.git" "$inkling_rev" "$scratch/inkling"
  mv -T -- "$scratch/inkling" "$inkling_src"
fi
echo "Sources ready in $work/sources"
