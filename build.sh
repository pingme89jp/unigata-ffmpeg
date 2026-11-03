#!/usr/bin/env bash
#
# Builds the Unigata FFmpeg for one target, from pinned source (owner, 2026-11-03: "I would prefer to create my own FFmpeg").
#
#   ./build.sh windows-x64 | linux-x64 | linux-arm64 | macos-arm64 | macos-x64
#
# Runs on the matching CI machine (Windows under MSYS2 MINGW64). Output: dist/unigata-ffmpeg-<version>-<build>-<target>.{zip,tar.xz}
#
# 🔴 THIS FILE IS PART OF THE LICENCE POSITION, not a convenience. It is published with every release so anyone can rebuild the
# program from the same source (LGPL-2.1 section 6). The rules it enforces:
#   * LGPL only: never --enable-gpl, --enable-nonfree or --enable-version3, and no x264 / x265 / fdk-aac.
#   * Audio out is MP3 (libmp3lame, LGPL; the MP3 patents have expired). No AAC encoder is built.
#   * H.264 out is the machine's own hardware encoder, or OpenH264 run from Cisco's own binary (see versions.env).
#   * Every source input is pinned in versions.env and verified (signature, hash or commit) before it is built.
#
# ⚠️ NOT YET RUN. Written 2026-11-03 on a machine with no compiler; the first CI run is its first test. Read the log, not the
# green tick: the last step runs the built program and encodes a test picture.

set -euo pipefail

TARGET="${1:?usage: build.sh <windows-x64|linux-x64|linux-arm64|macos-arm64|macos-x64>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.env
. "$HERE/versions.env"

WORK="${WORK:-$HERE/work/$TARGET}"
PREFIX="$WORK/prefix"
SRC="$WORK/src"
DIST="$HERE/dist"
JOBS="${JOBS:-$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) )}"
mkdir -p "$WORK" "$PREFIX/lib/pkgconfig" "$PREFIX/include" "$SRC" "$DIST"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

case "$TARGET" in
  windows-x64)  OS=windows; EXE=ffmpeg.exe; PACK=zip ;;
  linux-x64)    OS=linux;   EXE=ffmpeg;     PACK=tar ;;
  linux-arm64)  OS=linux;   EXE=ffmpeg;     PACK=tar ;;
  macos-arm64)  OS=macos;   EXE=ffmpeg;     PACK=tar ;;
  macos-x64)    OS=macos;   EXE=ffmpeg;     PACK=tar ;;
  *) echo "unknown target $TARGET" >&2; exit 2 ;;
esac

say() { printf '\n== %s\n' "$*"; }

# curl a file and refuse it unless its sha256 is the pinned one.
fetch() { # url file sha256
  local url="$1" file="$2" want="$3"
  [ -f "$file" ] || curl -fsSL --retry 3 -o "$file" "$url"
  local got; got="$(sha256sum "$file" | cut -d' ' -f1)"
  [ "$got" = "$want" ] || { echo "HASH MISMATCH for $file: wanted $want, got $got" >&2; exit 1; }
}

# clone a tag and refuse it unless it is the pinned commit.
clone() { # repo tag commit dir
  [ -d "$4/.git" ] || git clone --quiet --depth 1 --branch "$2" "$1" "$4"
  local got; got="$(git -C "$4" rev-parse HEAD)"
  [ "$got" = "$3" ] || { echo "COMMIT MISMATCH for $1 $2: wanted $3, got $got" >&2; exit 1; }
}

# ---------------------------------------------------------------------------------------------------------------- FFmpeg source
say "FFmpeg $FFMPEG_VERSION source: signature, then hash"
cd "$SRC"
[ -f ffmpeg.tar.xz ] || curl -fsSL --retry 3 -o ffmpeg.tar.xz "$FFMPEG_URL"
[ -f ffmpeg.tar.xz.asc ] || curl -fsSL --retry 3 -o ffmpeg.tar.xz.asc "$FFMPEG_SIG_URL"
[ -f ffmpeg-devel.asc ] || curl -fsSL --retry 3 -o ffmpeg-devel.asc "$FFMPEG_KEY_URL"
export GNUPGHOME="$WORK/gnupg"; mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
gpg --batch --import ffmpeg-devel.asc 2>/dev/null
gpg --batch --status-fd 1 --verify ffmpeg.tar.xz.asc ffmpeg.tar.xz 2>/dev/null | grep -q "VALIDSIG $FFMPEG_KEY_FINGERPRINT" \
  || { echo "FFmpeg signature is not a good one from $FFMPEG_KEY_FINGERPRINT" >&2; exit 1; }
fetch "$FFMPEG_URL" ffmpeg.tar.xz "$FFMPEG_SHA256"
[ -d "ffmpeg-$FFMPEG_VERSION" ] || tar -xf ffmpeg.tar.xz

CONF=()          # configure arguments, grown below
ENCODERS=(libmp3lame mp2)   # always: MP3 (and MP2, whose patents have also expired) audio
HW=()            # hardware H.264 encoders for this target

# ------------------------------------------------------------------------------------------------------------------- LAME (MP3)
say "LAME $LAME_VERSION"
fetch "$LAME_URL" lame.tar.gz "$LAME_SHA256"
[ -d "lame-$LAME_VERSION" ] || tar -xf lame.tar.gz
(
  cd "lame-$LAME_VERSION"
  ./configure --prefix="$PREFIX" --disable-shared --enable-static --disable-frontend --disable-decoder --disable-gtktest >/dev/null
  make -j"$JOBS" >/dev/null && make install >/dev/null
)
CONF+=(--enable-libmp3lame)

# ------------------------------------------------------------------------------------------------------- hardware H.264 encoders
case "$OS" in
  windows|linux)
    say "NVENC headers $NVCODEC_TAG"
    clone "$NVCODEC_REPO" "$NVCODEC_TAG" "$NVCODEC_COMMIT" "$SRC/nv-codec-headers"
    make -C "$SRC/nv-codec-headers" PREFIX="$PREFIX" install >/dev/null
    CONF+=(--enable-ffnvcodec); HW+=(h264_nvenc)
    ;;
esac
if [ "$OS" = windows ]; then
  say "AMF headers $AMF_TAG"
  clone "$AMF_REPO" "$AMF_TAG" "$AMF_COMMIT" "$SRC/AMF"
  mkdir -p "$PREFIX/include/AMF"; cp -r "$SRC/AMF/amf/public/include/." "$PREFIX/include/AMF/"
  CONF+=(--enable-amf); HW+=(h264_amf)
fi
case "$TARGET" in
  windows-x64|linux-x64)
    say "Intel oneVPL $VPL_TAG (static dispatcher; finds the Intel driver at run time)"
    clone "$VPL_REPO" "$VPL_TAG" "$VPL_COMMIT" "$SRC/libvpl"
    cmake -S "$SRC/libvpl" -B "$SRC/libvpl/build" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF \
      -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DBUILD_PREVIEW=OFF -DINSTALL_EXAMPLE_CODE=OFF >/dev/null
    cmake --build "$SRC/libvpl/build" -j"$JOBS" >/dev/null && cmake --install "$SRC/libvpl/build" >/dev/null
    CONF+=(--enable-libvpl); HW+=(h264_qsv)
    ;;
esac
if [ "$OS" = macos ]; then
  CONF+=(--enable-videotoolbox); HW+=(h264_videotoolbox)
fi
# Not built on purpose: VAAPI (it makes ffmpeg need libva at start-up on every Linux machine, even without an Intel/AMD GPU).

# ---------------------------------------------------------------------------------------------------------------- OpenH264
OPENH264_LIB=""
case "$TARGET" in
  windows-x64|linux-x64|linux-arm64)
    say "OpenH264 $OPENH264_TAG (headers and link library only; the library that RUNS is Cisco's)"
    clone "$OPENH264_REPO" "$OPENH264_TAG" "$OPENH264_COMMIT" "$SRC/openh264"
    case "$TARGET" in
      windows-x64)  make -C "$SRC/openh264" OS=mingw_nt ARCH=x86_64 PREFIX="$PREFIX" install-shared >/dev/null; OPENH264_LIB=openh264-8.dll
                    BIN_FILE="$OPENH264_WIN64_FILE"; BIN_SHA="$OPENH264_WIN64_SHA256" ;;
      linux-x64)    make -C "$SRC/openh264" OS=linux ARCH=x86_64 PREFIX="$PREFIX" install-shared >/dev/null; OPENH264_LIB=libopenh264.so.8
                    BIN_FILE="$OPENH264_LINUX64_FILE"; BIN_SHA="$OPENH264_LINUX64_SHA256" ;;
      linux-arm64)  make -C "$SRC/openh264" OS=linux ARCH=arm64 PREFIX="$PREFIX" install-shared >/dev/null; OPENH264_LIB=libopenh264.so.8
                    BIN_FILE="$OPENH264_LINUXARM64_FILE"; BIN_SHA="$OPENH264_LINUXARM64_SHA256" ;;
    esac
    CONF+=(--enable-libopenh264); HW+=(libopenh264)
    # Cisco's own file, checked against the hash pinned in versions.env, kept beside the program for the test run below and
    # recorded in the release so the Enhancer can fetch the same file.
    fetch "${OPENH264_BINARY_BASE}${BIN_FILE}" "$SRC/$BIN_FILE" "$BIN_SHA"
    ;;
esac

# ------------------------------------------------------------------------------------------------------------------------- TLS
case "$OS" in
  windows) CONF+=(--enable-schannel) ;;
  macos)   CONF+=(--enable-securetransport) ;;
  linux)   echo "NOTE: the Linux build has no TLS (http:// sources only); a TLS library would pull in a licence choice." ;;
esac

# --------------------------------------------------------------------------------------------------------------------- FFmpeg
say "FFmpeg configure"
ENC_LIST="$(IFS=,; echo "${ENCODERS[*]},${HW[*]}" | sed 's/,$//')"
ENABLE_ENCODERS=(); for e in ${ENC_LIST//,/ }; do ENABLE_ENCODERS+=("--enable-encoder=$e"); done
EXTRA_LD=(); [ "$OS" = windows ] && EXTRA_LD=(--extra-ldflags=-static)
[ "$TARGET" = macos-x64 ] && CONF+=(--arch=x86_64)

cd "$SRC/ffmpeg-$FFMPEG_VERSION"
CONFIGURE_LINE=(
  --prefix="$WORK/ffmpeg-out"
  --pkg-config-flags=--static
  --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib"
  ${EXTRA_LD[@]+"${EXTRA_LD[@]}"}
  --disable-shared --enable-static
  --disable-ffplay --disable-ffprobe --disable-doc --disable-debug
  --disable-autodetect
  --disable-encoders "${ENABLE_ENCODERS[@]}"
  --enable-encoder=mpeg2video
  "${CONF[@]}"
)
./configure "${CONFIGURE_LINE[@]}" || { cp ffbuild/config.log "$WORK/config.log" 2>/dev/null; tail -60 ffbuild/config.log; exit 1; }

say "FFmpeg build"
make -j"$JOBS"
make install
cp ffbuild/config.log "$WORK/config.log" 2>/dev/null || true

# ----------------------------------------------------------------------------------------------------------------- prove it
say "Proving the program: licence, encoders, and a real encode"
OUT="$WORK/ffmpeg-out/bin/$EXE"
# The program needs Cisco's OpenH264 library next to it to start, so the test uses the very file the Enhancer will fetch.
# On Linux the library is found through LD_LIBRARY_PATH (the Enhancer sets it to the program's folder when it starts ffmpeg).
if [ -n "$OPENH264_LIB" ]; then
  bunzip2 -c "$SRC/$BIN_FILE" > "$WORK/ffmpeg-out/bin/$OPENH264_LIB"
  chmod +x "$WORK/ffmpeg-out/bin/$OPENH264_LIB"
fi
export LD_LIBRARY_PATH="$WORK/ffmpeg-out/bin${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$OUT" -hide_banner -version | tee "$WORK/version.txt"
grep -q -i "enable-gpl\|enable-nonfree\|enable-version3" "$WORK/version.txt" && { echo "NOT LGPL: configure line has a GPL/nonfree/version3 flag" >&2; exit 1; }
"$OUT" -hide_banner -encoders 2>/dev/null | tee "$WORK/encoders.txt" | grep -E "libmp3lame|mpeg2video" >/dev/null \
  || { echo "expected encoders missing" >&2; exit 1; }
if "$OUT" -hide_banner -encoders 2>/dev/null | grep -E " (libx264|libx265|libfdk_aac|aac) " ; then
  echo "A forbidden encoder is present" >&2; exit 1
fi
# Audio+video encode with software parts that need no GPU: mpeg2video + mp3, into MPEG-TS, to a null sink.
"$OUT" -hide_banner -loglevel error -f lavfi -i testsrc=duration=1:size=320x240:rate=25 -f lavfi -i sine=duration=1 \
  -c:v mpeg2video -c:a libmp3lame -f mpegts -y "$WORK/proof.ts"
[ -s "$WORK/proof.ts" ] || { echo "the test encode wrote nothing" >&2; exit 1; }
echo "proof ok: $(wc -c < "$WORK/proof.ts") bytes of MPEG-TS"

# ------------------------------------------------------------------------------------------------------------------- package
say "Package"
NAME="unigata-ffmpeg-$FFMPEG_VERSION-$UNIGATA_BUILD-$TARGET"
PKG="$WORK/pkg/$NAME"; rm -rf "$WORK/pkg"; mkdir -p "$PKG/bin"
cp "$OUT" "$PKG/bin/$EXE"; strip "$PKG/bin/$EXE" 2>/dev/null || true
cp "$SRC/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$PKG/LICENSE-LGPL-2.1.txt"
cp "$SRC/ffmpeg-$FFMPEG_VERSION/LICENSE.md" "$PKG/LICENSE-FFmpeg.md"
cp "$HERE/COMPLIANCE.md" "$PKG/COMPLIANCE.md"
{
  echo "target:     $TARGET"
  echo "ffmpeg:     $FFMPEG_VERSION (sha256 $FFMPEG_SHA256)"
  echo "lame:       $LAME_VERSION (sha256 $LAME_SHA256)"
  echo "encoders:   $ENC_LIST,mpeg2video"
  echo "configure:  ${CONFIGURE_LINE[*]}"
  echo "openh264 library the program needs beside it: ${OPENH264_LIB:-none}"
  [ -n "${BIN_FILE:-}" ] && echo "cisco binary:   ${OPENH264_BINARY_BASE}${BIN_FILE} (sha256 $BIN_SHA)"
  echo; cat "$WORK/version.txt"
} > "$PKG/BUILD-INFO.txt"

cd "$WORK/pkg"
if [ "$PACK" = zip ]; then
  # `zip` (an MSYS2 package; GNU tar cannot write zip). The Enhancer reads it with Windows' own tar.
  zip -qr "$DIST/$NAME.zip" "$NAME"
else
  tar -cJf "$DIST/$NAME.tar.xz" "$NAME"
fi
( cd "$DIST" && sha256sum "$NAME".* > "$NAME.sha256" )
echo "built: $(ls "$DIST/$NAME".*)"
