# Script body for `nix run .#release`; the flake supplies the input paths.
name=inferenix-tumbleweed-gfx1201-slim
dist=$PWD/dist
archive=$dist/$name.tar
if [[ -e $archive || -L $archive ]]; then
  printf 'Refusing to overwrite %s\n' "$archive" >&2
  exit 1
fi
if ! command -v podman >/dev/null; then
  printf 'Install Podman on the build machine before running this release.\n' >&2
  exit 1
fi
mkdir -p -- "$dist"
stage=$(mktemp -d -- "$dist/.$name.XXXXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir -- "$stage/$name"

podman load --quiet -i "$qwenArchive"
podman load --quiet -i "$inkling2miniArchive"
podman save --quiet --format docker-archive --multi-image-archive \
  localhost/inferenix/qwen38:gfx1201-slim localhost/inferenix/inkling2mini:gfx1201 \
  | gzip -6 > "$stage/$name/images.tar.gz"
cp -- "$usageGuide" "$stage/$name/README.md"
tar -C "$stage" -cf "$stage/$name.tar" "$name/README.md" "$name/images.tar.gz"
mv -T --update=none-fail -- "$stage/$name.tar" "$archive"
printf '%s\n' "$archive"
