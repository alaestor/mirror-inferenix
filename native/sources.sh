# shellcheck shell=bash
# Consumed by fetch, build and prepare. Only fetch uses the network.
native_source_paths() {
  local manifest=$repo/pkgs/strata-unbiased/sources.json patch_names tree_key patch_hash patch
  upstream_sha=$(jq -er '.upstream.archiveSha256' "$manifest")
  llama_sha=$(jq -er '.llama.archiveSha256' "$manifest")
  patch_names=$(jq -er '.patches[]' "$manifest")
  patches=()
  while IFS= read -r patch; do
    patches+=("$repo/pkgs/strata-unbiased/patches/$patch")
  done <<< "$patch_names"
  patch_hash=$(cat -- "${patches[@]}" | sha256sum)
  tree_key=$(printf '%s\n' "$upstream_sha" "$llama_sha" "$patch_hash" | sha256sum)
  strata_src="$work/sources/strata-${tree_key%% *}"
  if [[ $1 != qwen38 ]]; then
    inkling_sha=$(jq -er '.sha256' "$repo/pkgs/strata/source.json")
    inkling_src="$work/sources/inkling-$inkling_sha"
  fi
}

native_source_urls() {
  local manifest=$repo/pkgs/strata-unbiased/sources.json
  local query='"https://codeload.github.com/\(.owner)/\(.repo)/tar.gz/\(.rev)"'
  upstream_url=$(jq -er ".upstream | $query" "$manifest")
  llama_url=$(jq -er ".llama | $query" "$manifest")
  if [[ $1 != qwen38 ]]; then
    inkling_url=$(jq -er '.url' "$repo/pkgs/strata/source.json")
  fi
}
