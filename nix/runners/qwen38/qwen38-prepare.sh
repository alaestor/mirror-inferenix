# shellcheck shell=bash
strata_parse_env_args "$@"
set -- "${strata_launch_args[@]}"
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  echo 'Usage: prepare [--env-file PATH] [MODEL.gguf OUTPUT_DIR [DRAFT_SOURCE]]'
  exit 0
fi
load_qwen38_env
case $# in
  0) ;;
  2|3)
    STRATA_MODEL=$1
    STRATA_PREPARED_DIR=$2
    if (( $# == 3 )); then STRATA_QWEN38_MTP_SOURCE=$3; fi
    ;;
  *) qwen38_fail 'Usage: prepare [--env-file PATH] [MODEL.gguf OUTPUT_DIR [DRAFT_SOURCE]]' ;;
esac
qwen38_check_model "$STRATA_MODEL"
if [[ -z $STRATA_PREPARED_DIR ]]; then qwen38_fail 'Output directory must not be empty.'; fi

out=$STRATA_PREPARED_DIR
draft=$STRATA_QWEN38_MTP_SOURCE
want_pack=true
want_mtp=true
if [[ -e $out/pack || -L $out/pack ]]; then
  want_pack=false
  qwen38_check_pack pack "$out/pack" ||
    qwen38_warn 'Keeping the existing pack as-is. Use a fresh output directory to rebuild it.'
fi
if [[ -e $out/mtp || -L $out/mtp ]]; then
  want_mtp=false
  qwen38_check_pack mtp "$out/mtp" ||
    qwen38_warn 'Keeping the existing draft pack as-is. Use a fresh output directory to rebuild it.'
fi
if [[ $want_mtp == true ]]; then
  if [[ -z $draft ]]; then
    qwen38_warn 'No draft source supplied. Set INFERENIX_MTP_SOURCE_QWEN38 to a local tensor directory or packed MTP GGUF to prepare mtp/.'
    want_mtp=false
  elif [[ -d $draft && -f $draft/mtp-manifest.json && -r $draft/mtp-manifest.json ]]; then
    : # The converter validates its input layout. There is no inferenix hash allowlist.
  elif [[ -f $draft && -r $draft && -s $draft ]]; then
    : # Already packed MTP GGUF.
  else
    qwen38_fail "Draft source is not a readable GGUF or directory with mtp-manifest.json: $draft"
  fi
fi
if [[ $want_pack == false && $want_mtp == false ]]; then
  echo "No packs to prepare in $out."
  exit 0
fi

mkdir -p -- "$out"
work=$(mktemp -d -- "$out/.prepare.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
if [[ $want_pack == true ]]; then
  python "$qwen38_pack_tools/iq_pack.py" --gguf "$STRATA_MODEL" --out "$work/pack"
  cp -- "$qwen38_pack_data/expert-profile.bin" "$work/pack/expert-profile.bin"
  qwen38_check_pack pack "$work/pack"
  mv -T --update=none-fail -- "$work/pack" "$out/pack"
  echo "Prepared $out/pack"
fi
if [[ $want_mtp == true ]]; then
  if [[ -d $draft ]]; then
    python "$qwen38_pack_tools/mtp_pack.py" --src "$draft" --experts q2_0 --out "$work/mtp-q2_0.gguf"
    draft=$work/mtp-q2_0.gguf
  fi
  python "$qwen38_pack_tools/mtp_rt.py" --gguf "$draft" --out "$work/mtp"
  cp -- "$qwen38_pack_data/draft_vocab.bin" "$work/mtp/draft_vocab.bin"
  qwen38_check_pack mtp "$work/mtp"
  mv -T --update=none-fail -- "$work/mtp" "$out/mtp"
  echo "Prepared $out/mtp"
fi
