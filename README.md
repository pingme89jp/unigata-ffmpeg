# Unigata FFmpeg build

Builds FFmpeg from pinned official source for ZenEnhancer (owner, 2026-11-03). **Not yet run anywhere** (written on a machine with no compiler).

* `versions.env`: every input, pinned by signature, hash or commit. The only file you edit to change a version.
* `build.sh <target>`: builds one target and ends by running the program (licence check, forbidden-encoder check, a real encode).
* `sources.sh`: bundles the exact source for LGPL-2.1 section 6.
* `COMPLIANCE.md`: ships inside every archive.
* `.github/workflows/build.yml`: builds all five targets on GitHub. Nothing is published unless it is run by hand with "publish" ticked.

This folder is laid out to become the root of its own public repository (the workflow file only runs from a repository root).

## Known gaps
* Windows OpenH264 (`make OS=mingw_nt`) and the `openh264-8.dll` name Cisco's file must be given are untested.
* Linux has no TLS (http sources only). VAAPI is left out on purpose. No macOS or Windows-on-arm64 OpenH264 (Cisco's file names were not found); macOS uses VideoToolbox only.
* The runner label `macos-15-intel` is a guess at the current Intel macOS runner.
