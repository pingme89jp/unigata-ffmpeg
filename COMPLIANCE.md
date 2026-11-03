# Unigata FFmpeg: what this is, and what you can do with it

This is FFmpeg, built unmodified from the official source release, for use by Unigata's ZenEnhancer to convert a television channel
into a video format a weak television can play. It is provided **as is**, with no warranty.

## Licence

* The program is **LGPL-2.1-or-later**. It is built **without** `--enable-gpl`, `--enable-nonfree` or `--enable-version3`, and with no
  x264, x265 or fdk-aac. The build script refuses to publish a program whose configure line says otherwise.
* The licence texts are in this archive (`LICENSE-LGPL-2.1.txt`, `LICENSE-FFmpeg.md`).
* **Source and rebuilding (LGPL-2.1 section 6).** The exact source of everything in the program is attached to the same release
  (`unigata-ffmpeg-sources-*.tar.xz`): FFmpeg, LAME, and the pinned commits of the hardware-encoder headers, oneVPL and OpenH264.
  `build.sh` and `versions.env` in this repository are the recipe, with every input pinned by hash, commit or signature. You may
  rebuild the program yourself and replace the one in this archive with it. `BUILD-INFO.txt` holds the exact configure line.

## What is inside, and what is not

* Audio out: **MP3** (LAME, LGPL) and MP2. **No AAC encoder** is built.
* Video out: the computer's own **hardware H.264 encoder** (NVENC, Intel QuickSync, AMD AMF, Apple VideoToolbox), driven through the
  vendor's driver, plus **OpenH264** where listed in `BUILD-INFO.txt`, plus MPEG-2 video.
* **OpenH264:** the program needs Cisco's OpenH264 library next to it to start. That library is **not** in this archive. ZenEnhancer
  downloads Cisco's own unmodified file from Cisco's server, checks it against the hash in `BUILD-INFO.txt`, and puts it beside the
  program. It is Cisco's software under Cisco's licence, and Cisco's patent cover applies to the binary Cisco distributes.
* FFmpeg's decoders (H.264, HEVC, AAC, AC-3 and others) are included so the program can read what a provider sends.

## What this document does not settle

Whether shipping or running codec code needs a patent licence in your country is a legal question this document does not answer.
H.264, HEVC, AAC and AC-3 are covered by patent pools. The hardware encoders are the computer maker's; the decoders and the MP3
encoder are in this program. Anyone redistributing it should take their own advice.
