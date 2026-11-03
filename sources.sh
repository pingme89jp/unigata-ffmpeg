#!/usr/bin/env bash
# Bundles the exact source of everything in the program, for LGPL-2.1 section 6 (owner, 2026-11-03). Same pins as build.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.env
. "$HERE/versions.env"
OUT="$HERE/dist"; W="$HERE/work/sources/unigata-ffmpeg-sources-$FFMPEG_VERSION-$UNIGATA_BUILD"
rm -rf "$HERE/work/sources"; mkdir -p "$W" "$OUT"
curl -fsSL --retry 3 -o "$W/ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_URL"
curl -fsSL --retry 3 -o "$W/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "$FFMPEG_SIG_URL"
curl -fsSL --retry 3 -o "$W/lame-$LAME_VERSION.tar.gz" "$LAME_URL"
echo "$FFMPEG_SHA256  ffmpeg-$FFMPEG_VERSION.tar.xz" | (cd "$W" && sha256sum -c -)
echo "$LAME_SHA256  lame-$LAME_VERSION.tar.gz" | (cd "$W" && sha256sum -c -)
for spec in "nv-codec-headers $NVCODEC_REPO $NVCODEC_TAG $NVCODEC_COMMIT" "AMF $AMF_REPO $AMF_TAG $AMF_COMMIT" \
            "libvpl $VPL_REPO $VPL_TAG $VPL_COMMIT" "openh264 $OPENH264_REPO $OPENH264_TAG $OPENH264_COMMIT"; do
  set -- $spec
  git clone --quiet --depth 1 --branch "$3" "$2" "$W/$1"
  [ "$(git -C "$W/$1" rev-parse HEAD)" = "$4" ] || { echo "commit mismatch for $1" >&2; exit 1; }
  rm -rf "$W/$1/.git"
done
cp "$HERE/build.sh" "$HERE/versions.env" "$HERE/sources.sh" "$HERE/COMPLIANCE.md" "$W/"
tar -C "$HERE/work/sources" -cJf "$OUT/unigata-ffmpeg-sources-$FFMPEG_VERSION-$UNIGATA_BUILD.tar.xz" "$(basename "$W")"
( cd "$OUT" && sha256sum "unigata-ffmpeg-sources-$FFMPEG_VERSION-$UNIGATA_BUILD.tar.xz" > "unigata-ffmpeg-sources-$FFMPEG_VERSION-$UNIGATA_BUILD.sha256" )
echo "sources bundled"
