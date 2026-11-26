# shellcheck shell=bash
# Consumed by fetch, build and prepare. Only fetch uses the network.
native_source_rev() {
  local rev
  if ! rev=$(jq -er "$1 | strings | select(test(\"^[0-9a-f]{40}$\"))" "$2"); then
    native_fail "Expected a full Git commit ID at $1 in $2."
    return
  fi
  printf '%s\n' "$rev"
}

native_source_paths() {
  local manifest=$repo/pkgs/strata-unbiased/sources.json patch_names tree_key patch_hash patch
  upstream_rev=$(native_source_rev '.upstream.rev' "$manifest")
  llama_rev=$(native_source_rev '.llama.rev' "$manifest")
  patch_names=$(jq -er '.patches[]' "$manifest")
  patches=()
  while IFS= read -r patch; do
    patches+=("$repo/pkgs/strata-unbiased/patches/$patch")
  done <<< "$patch_names"
  patch_hash=$(cat -- "${patches[@]}" | sha256sum)
  tree_key=$(printf '%s\n' "$upstream_rev" "$llama_rev" "$patch_hash" | sha256sum)
  strata_src="$work/sources/strata-${tree_key%% *}"
  if [[ $1 != qwen38 ]]; then
    inkling_rev=$(native_source_rev '.rev' "$repo/pkgs/strata/source.json")
    inkling_src="$work/sources/inkling-$inkling_rev"
  fi
}

native_source_urls() {
  local manifest=$repo/pkgs/strata-unbiased/sources.json
  local query='"https://github.com/\(.owner)/\(.repo).git"'
  upstream_url=$(jq -er ".upstream | $query" "$manifest")
  llama_url=$(jq -er ".llama | $query" "$manifest")
  if [[ $1 != qwen38 ]]; then
    inkling_url=$(jq -er "$query" "$repo/pkgs/strata/source.json")
  fi
}
