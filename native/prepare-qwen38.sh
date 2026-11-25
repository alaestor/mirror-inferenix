#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=native/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=native/sources.sh
source "$native_dir/sources.sh"

qwen38_prepare_dependencies() {
  native_require jq sha256sum cat mkdir mktemp cp mv rm
  native_source_paths qwen38
  if [[ ! -f $strata_src/tools/iq_pack.py || ! -d $strata_src/third_party/llama.cpp/gguf-py/gguf ]]; then
    native_fail 'Packing tools are missing. Run native/fetch-sources.sh qwen38 first.'
    return
  fi
  qwen38_python=python3
  if [[ -x $repo/.venv/bin/python ]]; then qwen38_python=$repo/.venv/bin/python; fi
  native_require "$qwen38_python"
  if ! "$qwen38_python" -c 'import numpy, regex, yaml, tqdm' > /dev/null 2>&1; then
    native_fail "Missing or unusable Qwen preparation packages in $qwen38_python. See native/README.md."
    return
  fi
  qwen38_pack_tools=$strata_src/tools
  qwen38_pack_data=$strata_src/data
  export STRATA_GGUF_PY=$strata_src/third_party/llama.cpp/gguf-py
}

# shellcheck source=nix/runners/launcher-common.sh
source "$repo/nix/runners/launcher-common.sh"
# shellcheck source=nix/runners/qwen38/qwen38-inputs.sh
source "$repo/nix/runners/qwen38/qwen38-inputs.sh"
# shellcheck source=nix/runners/qwen38/qwen38-prepare.sh
source "$repo/nix/runners/qwen38/qwen38-prepare.sh"
