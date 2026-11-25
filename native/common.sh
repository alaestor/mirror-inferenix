# shellcheck shell=bash
native_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
repo=${native_dir%/*}
work=$native_dir/.work

native_fail() { printf 'inferenix: %s\n' "$*" >&2; return 1; }

native_require() {
  local cmd missing=()
  for cmd; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
  done
  if (( ${#missing[@]} )); then
    native_fail "Missing commands on PATH: ${missing[*]}. See native/README.md."
  fi
}

native_model() {
  case "$1" in
    qwen38|inkling2mini) ;;
    *) native_fail "Unknown model: ${1:-<unset>}. Choose qwen38 or inkling2mini." ;;
  esac
}

native_gpu() {
  [[ $1 =~ ^gfx[0-9a-f]+$ ]] || native_fail "Invalid GPU target: '$1'. Use a gfx name from rocminfo, such as gfx1201."
}

native_check_cmake() {
  local version
  if ! version=$(cmake --version 2>&1); then
    native_fail 'Cannot run cmake. Check the CMake installation on PATH.'
  elif [[ ! $version =~ ^cmake\ version\ ([0-9]+)\.([0-9]+) ]] ||
    (( BASH_REMATCH[1] < 3 || (BASH_REMATCH[1] == 3 && BASH_REMATCH[2] < 24) )); then
    native_fail 'CMake 3.24 or newer is required. Check which cmake is on PATH.'
  fi
}

native_check_runtime() {
  local binary result render
  native_require ldd || return
  for binary; do
    if [[ ! -x $binary ]]; then
      native_fail "Missing executable: $binary. Run native/build.sh for this model and GPU."
      return
    fi
    if ! result=$(ldd "$binary" 2>&1) || [[ $result == *'not found'* ]]; then
      printf '%s\n' "$result" >&2
      native_fail "Cannot load $binary. Check the system libraries and matching ROCm runtime."
      return
    fi
  done
  if [[ ! -c /dev/kfd || ! -r /dev/kfd || ! -w /dev/kfd ]]; then
    native_fail 'Cannot access /dev/kfd. Check the amdgpu driver and your GPU device permissions.'
    return
  fi
  for render in /dev/dri/renderD*; do
    if [[ -c $render && -r $render && -w $render ]]; then return 0; fi
  done
  native_fail 'No accessible GPU render node under /dev/dri. Check your GPU device permissions.'
}
